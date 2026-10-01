import { describe, it, expect } from 'vitest';
import request from 'supertest';
import { createApp } from '../src/server/app';

const app = createApp();

describe('OpenAI Endpoints', () => {
  it('GET /health returns 200 ok', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
  });

  it('GET /v1/models returns model catalog', async () => {
    const res = await request(app).get('/v1/models');
    expect(res.status).toBe(200);
    expect(res.body.object).toBe('list');
    expect(Array.isArray(res.body.data)).toBe(true);
    expect(res.body.data.some((m: { id: string }) => m.id === 'gpt-4o')).toBe(true);
  });

  it('GET /v1/models/:model returns single model info', async () => {
    const res = await request(app).get('/v1/models/gpt-4o');
    expect(res.status).toBe(200);
    expect(res.body.id).toBe('gpt-4o');
  });

  it('POST /v1/chat/completions (non-streaming) returns standard completion', async () => {
    const res = await request(app)
      .post('/v1/chat/completions')
      .send({
        model: 'gpt-4o',
        messages: [{ role: 'user', content: 'What is 2+2?' }],
      });

    expect(res.status).toBe(200);
    expect(res.body.object).toBe('chat.completion');
    expect(res.body.choices[0].message.role).toBe('assistant');
    expect(res.body.choices[0].message.content).toBeDefined();
    expect(res.body.usage).toBeDefined();
  });

  it('POST /v1/chat/completions (streaming) returns SSE stream', async () => {
    const res = await request(app)
      .post('/v1/chat/completions')
      .set('x-stream-delay', '1')
      .send({
        model: 'fake-gpt-fast',
        messages: [{ role: 'user', content: 'Stream this test' }],
        stream: true,
      });

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toContain('text/event-stream');
    expect(res.text).toContain('data: [DONE]');
    expect(res.text).toContain('chat.completion.chunk');
  });

  it('POST /v1/chat/completions supports simulated tool calling', async () => {
    const res = await request(app)
      .post('/v1/chat/completions')
      .send({
        model: 'fake-gpt-tool',
        messages: [{ role: 'user', content: 'What is the weather in SF?' }],
        tools: [
          {
            type: 'function',
            function: { name: 'get_weather', description: 'Get current weather' },
          },
        ],
        tool_choice: 'auto',
      });

    expect(res.status).toBe(200);
    expect(res.body.choices[0].finish_reason).toBe('tool_calls');
    expect(res.body.choices[0].message.tool_calls[0].function.name).toBe('get_weather');
  });

  it('POST /v1/responses (modern Responses API) returns response object', async () => {
    const res = await request(app).post('/v1/responses').send({
      model: 'gpt-4o',
      input: 'Modern responses test',
    });

    expect(res.status).toBe(200);
    expect(res.body.object).toBe('response');
    expect(res.body.status).toBe('completed');
    expect(res.body.output[0].content[0].type).toBe('output_text');
  });

  it('POST /v1/images/generations returns generated images', async () => {
    const res = await request(app).post('/v1/images/generations').send({
      model: 'dall-e-3',
      prompt: 'Futuristic hypercar',
      n: 1,
    });

    expect(res.status).toBe(200);
    expect(res.body.data.length).toBe(1);
    expect(res.body.data[0].url).toBeDefined();
  });

  it('POST /v1/audio/speech returns audio buffer', async () => {
    const res = await request(app).post('/v1/audio/speech').send({
      model: 'tts-1',
      input: 'Testing audio speech synthesis',
      response_format: 'wav',
    });

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toBe('audio/wav');
    expect(res.body).toBeDefined();
  });

  it('POST /v1/embeddings returns float vector array', async () => {
    const res = await request(app).post('/v1/embeddings').send({
      model: 'text-embedding-3-small',
      input: 'Test embedding string',
    });

    expect(res.status).toBe(200);
    expect(res.body.object).toBe('list');
    expect(res.body.data[0].embedding.length).toBe(1536);
  });

  it('handles scenario errors properly (e.g. x-error: 429)', async () => {
    const res = await request(app)
      .post('/v1/chat/completions')
      .set('x-error', '429')
      .send({
        model: 'gpt-4o',
        messages: [{ role: 'user', content: 'Trigger error' }],
      });

    expect(res.status).toBe(429);
    expect(res.body.error.type).toBe('rate_limit_error');
  });
});
