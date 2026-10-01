import { describe, it, expect } from 'vitest';
import { fakeEngine } from '../src/fake/engine';
import { generateEmbeddingVector } from '../src/fake/embeddings';
import { generateSyntheticWavBuffer } from '../src/fake/audio';
import { generateSvgDataUrl } from '../src/fake/image';
import { chunkText } from '../src/streaming/stream';

describe('Fake AI Engine', () => {
  it('generates non-streaming text response', async () => {
    const res = await fakeEngine.generateText({
      model: 'gpt-4o',
      messages: [{ role: 'user', content: 'Hello there' }],
    });

    expect(res.type).toBe('text');
    if (res.type === 'text') {
      expect(res.content).toContain('Hello there');
    }
  });

  it('generates structured JSON response when response_format is json_object', async () => {
    const res = await fakeEngine.generateText({
      model: 'gpt-4o',
      messages: [{ role: 'user', content: 'Give me JSON' }],
      response_format: { type: 'json_object' },
    });

    expect(res.type).toBe('text');
    if (res.type === 'text') {
      const parsed = JSON.parse(res.content);
      expect(parsed.simulated).toBe(true);
      expect(parsed.data.status).toBe('success');
    }
  });

  it('generates simulated tool calls when requested', async () => {
    const res = await fakeEngine.generateText({
      model: 'gpt-4o',
      messages: [{ role: 'user', content: 'What is the weather in SF?' }],
      tools: [
        {
          type: 'function',
          function: { name: 'get_weather', description: 'Get weather' },
        },
      ],
      tool_choice: 'auto',
      behavior: { toolCall: true },
    });

    expect(res.type).toBe('tool_call');
    if (res.type === 'tool_call') {
      expect(res.toolCall.function.name).toBe('get_weather');
      const args = JSON.parse(res.toolCall.function.arguments);
      expect(args.location).toBe('San Francisco, CA');
    }
  });

  it('generates deterministic embedding vectors', () => {
    const v1 = generateEmbeddingVector('artificial intelligence', 1536);
    const v2 = generateEmbeddingVector('artificial intelligence', 1536);
    const v3 = generateEmbeddingVector('different query', 1536);

    expect(v1.length).toBe(1536);
    expect(v1).toEqual(v2); // Pure determinism
    expect(v1).not.toEqual(v3);
  });

  it('synthesizes valid RIFF/WAVE audio buffers', () => {
    const wav = generateSyntheticWavBuffer(1.0, 440);
    expect(wav.subarray(0, 4).toString('ascii')).toBe('RIFF');
    expect(wav.subarray(8, 12).toString('ascii')).toBe('WAVE');
    expect(wav.length).toBeGreaterThan(44);
  });

  it('generates SVG data URLs for images', () => {
    const dataUrl = generateSvgDataUrl('Cyberpunk cityscape', '512x512');
    expect(dataUrl.startsWith('data:image/svg+xml;base64,')).toBe(true);
  });

  it('chunks text accurately across multiple strategies', () => {
    const text = 'Hello world! How are you doing?';

    const words = chunkText(text, 'word');
    expect(words.join('')).toBe(text);

    const chars = chunkText(text, 'char');
    expect(chars.join('')).toBe(text);
    expect(chars.length).toBe(text.length);

    const sentences = chunkText(text, 'sentence');
    expect(sentences.length).toBe(2);
  });
});
