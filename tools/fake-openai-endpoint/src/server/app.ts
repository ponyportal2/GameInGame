import express, { Express, Request, Response } from 'express';
import {
  corsMiddleware,
  requestIdMiddleware,
  loggingMiddleware,
  authMiddleware,
  notFoundHandler,
  globalErrorHandler,
} from './middleware';
import { openaiRouter } from '../openai/routes';
import { anthropicRouter } from '../anthropic/routes';

export function createApp(): Express {
  const app = express();

  // Basic body parsers
  app.use(express.json({ limit: '50mb' }));
  app.use(express.urlencoded({ extended: true, limit: '50mb' }));

  // Global middlewares
  app.use(corsMiddleware);
  app.use(requestIdMiddleware);
  app.use(loggingMiddleware);
  app.use(authMiddleware);

  // Health and readiness checks
  app.get('/health', (_req: Request, res: Response) => {
    res.json({
      status: 'ok',
      service: 'fake-ai-api-simulator',
      uptime: process.uptime(),
      timestamp: new Date().toISOString(),
    });
  });

  app.get('/ready', (_req: Request, res: Response) => {
    res.json({ status: 'ready' });
  });

  // Legacy backwards compatibility endpoints
  app.get('/test', (_req: Request, res: Response) => {
    res.send('This is test response');
  });

  app.get('/', (_req: Request, res: Response) => {
    res.send(`
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8" />
        <title>Fake AI API Simulator</title>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f172a; color: #e2e8f0; max-width: 800px; margin: 40px auto; padding: 20px; line-height: 1.6; }
          h1 { color: #38bdf8; }
          code { background: #1e293b; padding: 2px 6px; border-radius: 4px; color: #a5b4fc; }
          .card { background: #1e293b; border-radius: 8px; padding: 16px; margin: 16px 0; border: 1px solid #334155; }
        </style>
      </head>
      <body>
        <h1>Fake AI API Simulator</h1>
        <p>A fast, local, protocol-compatible AI API server simulating OpenAI & Anthropic endpoints for development and testing.</p>
        <div class="card">
          <h3>OpenAI Endpoints</h3>
          <ul>
            <li><code>GET /v1/models</code> - List models</li>
            <li><code>POST /v1/chat/completions</code> - Chat completions (streaming & non-streaming)</li>
            <li><code>POST /v1/responses</code> - Modern OpenAI Responses API</li>
            <li><code>POST /v1/images/generations</code> - Image generation</li>
            <li><code>POST /v1/audio/speech</code> - Audio text-to-speech</li>
            <li><code>POST /v1/audio/transcriptions</code> - Audio transcription</li>
            <li><code>POST /v1/embeddings</code> - Deterministic embeddings</li>
          </ul>
        </div>
        <div class="card">
          <h3>Anthropic Endpoints</h3>
          <ul>
            <li><code>POST /v1/messages</code> or <code>POST /messages</code> - Messages API (streaming & non-streaming)</li>
          </ul>
        </div>
      </body>
      </html>
    `);
  });

  // Mount API protocols
  app.use('/v1', openaiRouter);
  app.use('/', anthropicRouter);

  // 404 & Error Handlers
  app.use(notFoundHandler);
  app.use(globalErrorHandler);

  return app;
}
