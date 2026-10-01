import { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import { config } from '../config';
import { logger } from '../utils/logger';
import { sendOpenAIError, sendAnthropicError, APIError } from '../utils/errors';

export function requestIdMiddleware(req: Request, res: Response, next: NextFunction) {
  const reqId =
    (req.headers['x-request-id'] as string) || `req_${Math.random().toString(36).substring(2, 12)}`;
  req.headers['x-request-id'] = reqId;
  res.setHeader('x-request-id', reqId);
  next();
}

export function authMiddleware(req: Request, res: Response, next: NextFunction) {
  // If no API key configured on server, allow all requests
  if (!config.apiKey) {
    return next();
  }

  // Health and test routes don't require auth
  if (req.path === '/health' || req.path === '/ready' || req.path === '/' || req.path === '/test') {
    return next();
  }

  const authHeader = req.headers.authorization;
  const xApiKey = req.headers['x-api-key'] as string | undefined;

  let providedToken: string | undefined;

  if (authHeader && authHeader.startsWith('Bearer ')) {
    providedToken = authHeader.substring(7).trim();
  } else if (xApiKey) {
    providedToken = xApiKey.trim();
  }

  if (!providedToken || providedToken !== config.apiKey) {
    if (req.path.includes('/messages')) {
      return sendAnthropicError(res, 401, 'Invalid or missing API key', 'authentication_error');
    }
    return sendOpenAIError(
      res,
      401,
      'Incorrect API key provided. You can find your API key in your simulator settings.',
      'invalid_request_error',
      'invalid_api_key'
    );
  }

  next();
}

export function loggingMiddleware(req: Request, res: Response, next: NextFunction) {
  const startTime = Date.now();
  const requestId = req.headers['x-request-id'] as string;

  res.on('finish', () => {
    const durationMs = Date.now() - startTime;
    logger.info(`${req.method} ${req.originalUrl} ${res.statusCode} (${durationMs}ms)`, {
      requestId,
      method: req.method,
      url: req.originalUrl,
      status: res.statusCode,
      durationMs,
    });
  });

  next();
}

export const corsMiddleware = cors({
  origin: config.corsOrigin === '*' ? true : config.corsOrigin.split(','),
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: [
    'Content-Type',
    'Authorization',
    'x-api-key',
    'x-request-id',
    'x-scenario',
    'x-delay',
    'x-stream-delay',
    'x-error',
    'x-chunk',
    'anthropic-version',
  ],
  credentials: true,
});

export function notFoundHandler(req: Request, res: Response) {
  if (req.path.startsWith('/messages') || req.path.startsWith('/v1/messages')) {
    return sendAnthropicError(
      res,
      404,
      `Endpoint not found: ${req.method} ${req.originalUrl}`,
      'not_found_error'
    );
  }
  return sendOpenAIError(
    res,
    404,
    `Unrecognized request URL (${req.method}: ${req.originalUrl}). Please verify your endpoint path.`,
    'invalid_request_error'
  );
}

export function globalErrorHandler(err: unknown, req: Request, res: Response, _next: NextFunction) {
  logger.error('Unhandled server error:', {
    error: err instanceof Error ? err.stack || err.message : String(err),
  });

  const isAnthropic = req.path.includes('/messages');
  if (err instanceof APIError) {
    if (isAnthropic) {
      return sendAnthropicError(res, err.status, err.message, err.type);
    }
    return sendOpenAIError(
      res,
      err.status,
      err.message,
      err.type,
      err.code ? String(err.code) : null
    );
  }

  const message = err instanceof Error ? err.message : 'Internal server error';
  if (isAnthropic) {
    return sendAnthropicError(res, 500, message, 'api_error');
  }
  return sendOpenAIError(res, 500, message, 'server_error');
}
