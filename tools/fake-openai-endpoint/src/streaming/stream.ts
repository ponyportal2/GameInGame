import { Response } from 'express';
import { ChunkStrategy } from '../types';

/**
 * Asynchronously wait for a given duration, respecting an AbortSignal.
 */
export function delay(ms: number, signal?: AbortSignal): Promise<void> {
  if (ms <= 0) return Promise.resolve();
  if (signal?.aborted) return Promise.reject(new Error('Request aborted'));

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      signal?.removeEventListener('abort', onAbort);
      resolve();
    }, ms);

    function onAbort() {
      clearTimeout(timer);
      reject(new Error('Request aborted'));
    }

    signal?.addEventListener('abort', onAbort, { once: true });
  });
}

/**
 * Splits text according to the desired chunking strategy.
 */
export function chunkText(text: string, strategy: ChunkStrategy = 'word'): string[] {
  if (!text) return [];

  switch (strategy) {
    case 'char':
      return Array.from(text);

    case 'sentence': {
      // Split on sentence boundaries, retaining punctuation
      const matches = text.match(/[^.!?]+[.!?]+(\s+|$)|[^.!?]+$/g);
      return matches ? matches : [text];
    }

    case 'token': {
      // Approximate LLM tokens: ~3-4 characters each
      const chunks: string[] = [];
      let i = 0;
      while (i < text.length) {
        const chunkSize = Math.floor(Math.random() * 2) + 3; // 3 or 4 chars
        chunks.push(text.slice(i, i + chunkSize));
        i += chunkSize;
      }
      return chunks;
    }

    case 'word':
    default: {
      // Split by words while preserving whitespace attached to chunks
      const regex = /\S+\s*/g;
      const chunks = text.match(regex);
      return chunks && chunks.length > 0 ? chunks : [text];
    }
  }
}

export interface StreamTextOptions {
  text: string;
  res: Response;
  delayMs?: number;
  chunkStrategy?: ChunkStrategy;
  onChunk: (chunk: string, index: number, isLast: boolean) => boolean | void;
  signal?: AbortSignal;
}

/**
 * Streams text chunks incrementally over time with cancellation support.
 */
export async function streamText(
  options: StreamTextOptions
): Promise<{ chunkCount: number; byteCount: number }> {
  const { text, res, delayMs = 30, chunkStrategy = 'word', onChunk, signal } = options;
  const chunks = chunkText(text, chunkStrategy);

  let byteCount = 0;
  let chunkCount = 0;

  for (let i = 0; i < chunks.length; i++) {
    if (signal?.aborted || res.writableEnded || res.destroyed) {
      break;
    }

    const chunk = chunks[i];
    const isLast = i === chunks.length - 1;

    onChunk(chunk, i, isLast);
    chunkCount++;
    byteCount += Buffer.byteLength(chunk, 'utf-8');

    if (!isLast && delayMs > 0) {
      try {
        await delay(delayMs, signal);
      } catch {
        // Aborted during delay
        break;
      }
    }
  }

  return { chunkCount, byteCount };
}

export interface StreamBytesOptions {
  buffer: Buffer;
  res: Response;
  chunkSize?: number;
  delayMs?: number;
  signal?: AbortSignal;
}

/**
 * Streams raw binary bytes incrementally.
 */
export async function streamBytes(options: StreamBytesOptions): Promise<void> {
  const { buffer, res, chunkSize = 1024 * 4, delayMs = 20, signal } = options;

  let offset = 0;
  while (offset < buffer.length) {
    if (signal?.aborted || res.writableEnded || res.destroyed) {
      break;
    }

    const chunk = buffer.subarray(offset, offset + chunkSize);
    res.write(chunk);
    offset += chunk.length;

    if (offset < buffer.length && delayMs > 0) {
      try {
        await delay(delayMs, signal);
      } catch {
        break;
      }
    }
  }
}
