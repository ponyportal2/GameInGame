import { Response } from 'express';

export class APIError extends Error {
  public status: number;
  public type: string;
  public code?: string | number;

  constructor(
    status: number,
    message: string,
    type: string = 'invalid_request_error',
    code?: string | number
  ) {
    super(message);
    this.name = 'APIError';
    this.status = status;
    this.type = type;
    this.code = code;
  }
}

export function sendOpenAIError(
  res: Response,
  status: number,
  message: string,
  type: string = 'invalid_request_error',
  code: string | null = null,
  param: string | null = null
) {
  if (res.headersSent) {
    return;
  }
  return res.status(status).json({
    error: {
      message,
      type,
      param,
      code,
    },
  });
}

export function sendAnthropicError(
  res: Response,
  status: number,
  message: string,
  type: string = 'invalid_request_error'
) {
  if (res.headersSent) {
    return;
  }
  return res.status(status).json({
    type: 'error',
    error: {
      type,
      message,
    },
  });
}

export function sendError(
  res: Response,
  error: unknown,
  protocol: 'openai' | 'anthropic' = 'openai'
) {
  if (error instanceof APIError) {
    if (protocol === 'anthropic') {
      return sendAnthropicError(res, error.status, error.message, error.type);
    }
    return sendOpenAIError(
      res,
      error.status,
      error.message,
      error.type,
      error.code ? String(error.code) : null
    );
  }

  const message = error instanceof Error ? error.message : 'An internal server error occurred';
  if (protocol === 'anthropic') {
    return sendAnthropicError(res, 500, message, 'api_error');
  }
  return sendOpenAIError(res, 500, message, 'server_error');
}
