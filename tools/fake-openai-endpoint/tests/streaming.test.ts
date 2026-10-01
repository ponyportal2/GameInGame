import { describe, it, expect } from 'vitest';
import { streamText, delay } from '../src/streaming/stream';
import { Response } from 'express';

describe('Streaming Engine & Abort Handling', () => {
  it('delays correctly and respects AbortSignal', async () => {
    const start = Date.now();
    await delay(50);
    const elapsed = Date.now() - start;
    expect(elapsed).toBeGreaterThanOrEqual(40);

    const controller = new AbortController();
    controller.abort();
    await expect(delay(1000, controller.signal)).rejects.toThrow('Request aborted');
  });

  it('streams text chunks incrementally and invokes onChunk', async () => {
    const mockRes = {
      writableEnded: false,
      destroyed: false,
      write: () => true,
    } as unknown as Response;

    const collected: string[] = [];
    const stats = await streamText({
      text: 'One two three four five',
      res: mockRes,
      delayMs: 5,
      chunkStrategy: 'word',
      onChunk: (chunk) => {
        collected.push(chunk);
      },
    });

    expect(collected.length).toBe(5);
    expect(collected.join('')).toBe('One two three four five');
    expect(stats.chunkCount).toBe(5);
    expect(stats.byteCount).toBeGreaterThan(0);
  });

  it('stops streaming immediately when aborted', async () => {
    const mockRes = {
      writableEnded: false,
      destroyed: false,
      write: () => true,
    } as unknown as Response;

    const controller = new AbortController();
    const collected: string[] = [];

    const promise = streamText({
      text: 'One two three four five six seven eight nine ten',
      res: mockRes,
      delayMs: 100,
      chunkStrategy: 'word',
      signal: controller.signal,
      onChunk: (chunk, index) => {
        collected.push(chunk);
        if (index === 1) {
          controller.abort();
        }
      },
    });

    await promise;
    expect(collected.length).toBeLessThan(5);
  });
});
