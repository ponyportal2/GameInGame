import { describe, it, expect } from 'vitest';
import request from 'supertest';
import { createApp } from '../src/server/app';

const app = createApp();

describe('Anthropic Messages Endpoints', () => {
  it('POST /v1/messages (non-streaming) returns Anthropic message format', async () => {
    const res = await request(app)
      .post('/v1/messages')
      .send({
        model: 'claude-3-5-sonnet-20241022',
        messages: [{ role: 'user', content: 'Hello Claude!' }],
        max_tokens: 1024,
      });

    expect(res.status).toBe(200);
    expect(res.body.type).toBe('message');
    expect(res.body.role).toBe('assistant');
    expect(res.body.content[0].type).toBe('text');
    expect(res.body.content[0].text).toContain('Hello Claude!');
    expect(res.body.stop_reason).toBe('end_turn');
  });

  it('POST /v1/messages (streaming) returns valid Anthropic SSE events', async () => {
    const res = await request(app)
      .post('/v1/messages')
      .set('x-stream-delay', '1')
      .send({
        model: 'claude-3-5-sonnet-20241022',
        messages: [{ role: 'user', content: 'Stream test' }],
        stream: true,
      });

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toContain('text/event-stream');
    expect(res.text).toContain('event: message_start');
    expect(res.text).toContain('event: content_block_start');
    expect(res.text).toContain('event: content_block_delta');
    expect(res.text).toContain('event: content_block_stop');
    expect(res.text).toContain('event: message_delta');
    expect(res.text).toContain('event: message_stop');
  });

  it('POST /v1/messages supports tool use format', async () => {
    const res = await request(app)
      .post('/v1/messages')
      .set('x-scenario', 'tool')
      .send({
        model: 'claude-3-5-sonnet-20241022',
        messages: [{ role: 'user', content: 'What is the weather in SF?' }],
        tools: [
          {
            name: 'get_weather',
            description: 'Get current weather',
            input_schema: {
              type: 'object',
              properties: { location: { type: 'string' } },
            },
          },
        ],
      });

    expect(res.status).toBe(200);
    expect(res.body.type).toBe('message');
    expect(res.body.stop_reason).toBe('tool_use');
    expect(res.body.content[0].type).toBe('tool_use');
    expect(res.body.content[0].name).toBe('get_weather');
  });

  it('POST /v1/messages returns validation error on empty messages', async () => {
    const res = await request(app).post('/v1/messages').send({
      model: 'claude-3-5-sonnet-20241022',
      messages: [],
    });

    expect(res.status).toBe(400);
    expect(res.body.type).toBe('error');
    expect(res.body.error.type).toBe('invalid_request_error');
  });
});
