import { Request, Response } from 'express';
import { z } from 'zod';
import { extractBehavior, config } from '../config';
import { fakeEngine } from '../fake/engine';
import { initSSE, writeSSE, closeSSE } from '../streaming/sse';
import { streamText } from '../streaming/stream';
import { sendError, sendAnthropicError } from '../utils/errors';
import { Message } from '../types';

const AnthropicMessageSchema = z.object({
  model: z.string().min(1, 'model is required'),
  messages: z
    .array(
      z.object({
        role: z.enum(['user', 'assistant']),
        content: z.union([z.string(), z.array(z.any())]),
      })
    )
    .min(1, 'messages cannot be empty'),
  system: z.union([z.string(), z.array(z.any())]).optional(),
  stream: z.boolean().optional().default(false),
  max_tokens: z.number().optional().default(1024),
  temperature: z.number().optional(),
  tools: z.array(z.any()).optional(),
  tool_choice: z.any().optional(),
});

export async function handleAnthropicMessages(req: Request, res: Response) {
  const parseResult = AnthropicMessageSchema.safeParse(req.body);
  if (!parseResult.success) {
    return sendAnthropicError(
      res,
      400,
      `Invalid request schema: ${parseResult.error.errors.map((e) => e.message).join(', ')}`
    );
  }

  const { model, messages, system, stream, tools } = parseResult.data;
  const behavior = extractBehavior(req.headers, model);
  const streamDelayMs = behavior.streamDelay ?? config.streamDelayMs;
  const chunkStrategy = behavior.chunk ?? config.streamChunkStrategy;

  // Convert system prompt to standard message format
  const internalMessages: Message[] = [];
  if (system) {
    const sysContent = typeof system === 'string' ? system : JSON.stringify(system);
    internalMessages.push({ role: 'system', content: sysContent });
  }

  for (const m of messages) {
    internalMessages.push({
      role: m.role,
      content: typeof m.content === 'string' ? m.content : JSON.stringify(m.content),
    });
  }

  try {
    const generated = await fakeEngine.generateText({
      model,
      messages: internalMessages,
      stream,
      tools,
      behavior,
    });

    const msgId = `msg_${Math.random().toString(36).substring(2, 14)}`;
    const fullText =
      generated.type === 'tool_call' ? JSON.stringify(generated.toolCall) : generated.content;
    const inputTokens = Math.ceil(JSON.stringify(internalMessages).length / 4);
    const outputTokens = Math.ceil(fullText.length / 4);

    // Non-streaming response
    if (!stream) {
      if (generated.type === 'tool_call') {
        const tool = generated.toolCall;
        let parsedArgs = {};
        try {
          parsedArgs = JSON.parse(tool.function.arguments);
        } catch {
          parsedArgs = { value: tool.function.arguments };
        }

        return res.json({
          id: msgId,
          type: 'message',
          role: 'assistant',
          model,
          content: [
            {
              type: 'tool_use',
              id: tool.id,
              name: tool.function.name,
              input: parsedArgs,
            },
          ],
          stop_reason: 'tool_use',
          stop_sequence: null,
          usage: {
            input_tokens: inputTokens,
            output_tokens: outputTokens,
          },
        });
      }

      return res.json({
        id: msgId,
        type: 'message',
        role: 'assistant',
        model,
        content: [
          {
            type: 'text',
            text: fullText,
          },
        ],
        stop_reason: 'end_turn',
        stop_sequence: null,
        usage: {
          input_tokens: inputTokens,
          output_tokens: outputTokens,
        },
      });
    }

    // Streaming mode (Anthropic SSE Protocol)
    initSSE(res);

    // 1. message_start
    writeSSE(
      res,
      {
        type: 'message_start',
        message: {
          id: msgId,
          type: 'message',
          role: 'assistant',
          content: [],
          model,
          stop_reason: null,
          stop_sequence: null,
          usage: {
            input_tokens: inputTokens,
            output_tokens: 1,
          },
        },
      },
      'message_start'
    );

    // 2. content_block_start
    writeSSE(
      res,
      {
        type: 'content_block_start',
        index: 0,
        content_block: {
          type: 'text',
          text: '',
        },
      },
      'content_block_start'
    );

    // 3. content_block_delta stream
    await streamText({
      text: fullText,
      res,
      delayMs: streamDelayMs,
      chunkStrategy,
      onChunk: (chunk) => {
        writeSSE(
          res,
          {
            type: 'content_block_delta',
            index: 0,
            delta: {
              type: 'text_delta',
              text: chunk,
            },
          },
          'content_block_delta'
        );
      },
    });

    // 4. content_block_stop
    writeSSE(
      res,
      {
        type: 'content_block_stop',
        index: 0,
      },
      'content_block_stop'
    );

    // 5. message_delta
    writeSSE(
      res,
      {
        type: 'message_delta',
        delta: {
          stop_reason: 'end_turn',
          stop_sequence: null,
        },
        usage: {
          output_tokens: outputTokens,
        },
      },
      'message_delta'
    );

    // 6. message_stop
    writeSSE(
      res,
      {
        type: 'message_stop',
      },
      'message_stop'
    );

    closeSSE(res);
  } catch (err) {
    sendError(res, err, 'anthropic');
  }
}
