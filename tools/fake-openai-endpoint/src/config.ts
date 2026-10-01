import dotenv from 'dotenv';
import { FakeBehavior, ChunkStrategy } from './types';

dotenv.config();

export const config = {
  port: parseInt(process.env.PORT || '3000', 10),
  host: process.env.HOST || '0.0.0.0',
  apiKey: process.env.API_KEY || '',
  defaultDelayMs: parseInt(process.env.DEFAULT_DELAY_MS || '300', 10),
  streamDelayMs: parseInt(process.env.STREAM_DELAY_MS || '30', 10),
  streamChunkStrategy: (process.env.STREAM_CHUNK_STRATEGY || 'word') as ChunkStrategy,
  deterministic: process.env.DETERMINISTIC !== 'false',
  seed: parseInt(process.env.SEED || '42', 10),
  corsOrigin: process.env.CORS_ORIGIN || '*',
  logLevel: process.env.LOG_LEVEL || 'info',
};

/**
 * Extracts simulation behavior overrides from headers or model name.
 * e.g.
 * - Header: `x-scenario: slow` or `x-delay: 2000` or `x-error: 500`
 * - Model: `fake-gpt-slow`, `fake-gpt-error`, `fake-gpt-tool`
 */
export function extractBehavior(
  headers: Record<string, string | string[] | undefined>,
  model?: string
): FakeBehavior {
  const behavior: FakeBehavior = {};

  const headerScenario =
    typeof headers['x-scenario'] === 'string' ? headers['x-scenario'] : undefined;
  const scenario = headerScenario || (model?.startsWith('fake-') ? model : undefined);

  if (scenario) {
    if (scenario.includes('slow') || scenario.includes('lag')) {
      behavior.delay = 1500;
      behavior.streamDelay = 150;
    } else if (scenario.includes('fast')) {
      behavior.delay = 10;
      behavior.streamDelay = 5;
    } else if (scenario.includes('error-500') || scenario.includes('server-error')) {
      behavior.error = 500;
    } else if (scenario.includes('error-429') || scenario.includes('rate-limit')) {
      behavior.error = 429;
    } else if (scenario.includes('error-400') || scenario.includes('invalid')) {
      behavior.error = 400;
    } else if (scenario.includes('tool')) {
      behavior.toolCall = true;
    } else if (scenario.includes('invalid-json')) {
      behavior.invalidJson = true;
    } else if (scenario.includes('partial')) {
      behavior.partialResponse = true;
    }
  }

  // Direct header overrides
  if (typeof headers['x-delay'] === 'string') {
    behavior.delay = parseInt(headers['x-delay'], 10);
  }
  if (typeof headers['x-stream-delay'] === 'string') {
    behavior.streamDelay = parseInt(headers['x-stream-delay'], 10);
  }
  if (typeof headers['x-error'] === 'string') {
    behavior.error = parseInt(headers['x-error'], 10);
  }
  if (typeof headers['x-chunk'] === 'string') {
    behavior.chunk = headers['x-chunk'] as ChunkStrategy;
  }

  return behavior;
}
