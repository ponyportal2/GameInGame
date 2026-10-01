import { Response } from 'express';

/**
 * Initializes SSE headers on the Express response.
 */
export function initSSE(res: Response) {
  if (!res.headersSent) {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no', // Disable proxy buffering (Nginx, etc.)
    });
    res.flushHeaders?.();
  }
}

/**
 * Writes a Server-Sent Event frame.
 */
export function writeSSE(res: Response, data: unknown, event?: string): boolean {
  if (res.writableEnded || res.destroyed) {
    return false;
  }

  let payload = '';
  if (event) {
    payload += `event: ${event}\n`;
  }

  const serialized = typeof data === 'string' ? data : JSON.stringify(data);
  payload += `data: ${serialized}\n\n`;

  return res.write(payload, 'utf-8');
}

/**
 * Writes the OpenAI standard stream termination signal `data: [DONE]\n\n` and closes the stream.
 */
export function writeSSEDone(res: Response) {
  if (!res.writableEnded && !res.destroyed) {
    res.write('data: [DONE]\n\n', 'utf-8');
    res.end();
  }
}

/**
 * Closes the SSE stream gracefully.
 */
export function closeSSE(res: Response) {
  if (!res.writableEnded && !res.destroyed) {
    res.end();
  }
}
