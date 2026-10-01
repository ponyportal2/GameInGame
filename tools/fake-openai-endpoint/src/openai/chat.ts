import { Request, Response } from 'express';
import { z } from 'zod';
import { extractBehavior, config } from '../config';
import { fakeEngine } from '../fake/engine';
import { initSSE, writeSSE, writeSSEDone } from '../streaming/sse';
import { streamText } from '../streaming/stream';
import { sendError, sendOpenAIError } from '../utils/errors';
import { Message, ToolDefinition } from '../types';

const ChatCompletionSchema = z.object({
  model: z.string().min(1, 'model is required'),
  messages: z.array(z.any()).min(1, 'messages cannot be empty'),
  stream: z.boolean().optional().default(false),
  tools: z.array(z.any()).optional(),
  tool_choice: z.any().optional(),
  response_format: z.object({ type: z.string(), json_schema: z.any().optional() }).optional(),
  temperature: z.number().optional(),
  max_tokens: z.number().optional(),
});

export async function handleChatCompletions(req: Request, res: Response) {
  const parseResult = ChatCompletionSchema.safeParse(req.body);
  if (!parseResult.success) {
    return sendOpenAIError(
      res,
      400,
      `Invalid request schema: ${parseResult.error.errors.map((e) => e.message).join(', ')}`
    );
  }

  const { model, messages, stream, tools, tool_choice, response_format } = parseResult.data;
  const behavior = extractBehavior(req.headers, model);
  const streamDelayMs = behavior.streamDelay ?? config.streamDelayMs;
  const chunkStrategy = behavior.chunk ?? config.streamChunkStrategy;

  try {
    const generated = await fakeEngine.generateText({
      model,
      messages: messages as Message[],
      stream,
      tools: tools as ToolDefinition[],
      tool_choice,
      response_format,
      behavior,
    });

    const completionId = `chatcmpl-${Math.random().toString(36).substring(2, 11)}`;
    const created = Math.floor(Date.now() / 1000);

    // Non-streaming response
    if (!stream) {
      if (generated.type === 'tool_call') {
        return res.json({
          id: completionId,
          object: 'chat.completion',
          created,
          model,
          choices: [
            {
              index: 0,
              message: {
                role: 'assistant',
                content: null,
                tool_calls: [generated.toolCall],
              },
              finish_reason: 'tool_calls',
            },
          ],
          usage: {
            prompt_tokens: 25,
            completion_tokens: 15,
            total_tokens: 40,
          },
          system_fingerprint: 'fp_fake_sim_01',
        });
      }

      const promptTokens = Math.ceil(JSON.stringify(messages).length / 4);
      const completionTokens = Math.ceil(generated.content.length / 4);

      return res.json({
        id: completionId,
        object: 'chat.completion',
        created,
        model,
        choices: [
          {
            index: 0,
            message: {
              role: 'assistant',
              content: generated.content,
            },
            finish_reason: 'stop',
          },
        ],
        usage: {
          prompt_tokens: promptTokens,
          completion_tokens: completionTokens,
          total_tokens: promptTokens + completionTokens,
        },
        system_fingerprint: 'fp_fake_sim_01',
      });
    }

    // Streaming mode
    initSSE(res);

    // Stream initial role delta
    writeSSE(res, {
      id: completionId,
      object: 'chat.completion.chunk',
      created,
      model,
      choices: [
        {
          index: 0,
          delta: { role: 'assistant', content: '' },
          finish_reason: null,
        },
      ],
    });

    if (generated.type === 'tool_call') {
      const tool = generated.toolCall;
      const argChunks = [
        tool.function.arguments.slice(0, Math.floor(tool.function.arguments.length / 2)),
        tool.function.arguments.slice(Math.floor(tool.function.arguments.length / 2)),
      ];

      // Stream tool call start with function name
      writeSSE(res, {
        id: completionId,
        object: 'chat.completion.chunk',
        created,
        model,
        choices: [
          {
            index: 0,
            delta: {
              tool_calls: [
                {
                  index: 0,
                  id: tool.id,
                  type: 'function',
                  function: {
                    name: tool.function.name,
                    arguments: '',
                  },
                },
              ],
            },
            finish_reason: null,
          },
        ],
      });

      // Stream arguments deltas
      for (const argChunk of argChunks) {
        writeSSE(res, {
          id: completionId,
          object: 'chat.completion.chunk',
          created,
          model,
          choices: [
            {
              index: 0,
              delta: {
                tool_calls: [
                  {
                    index: 0,
                    function: {
                      arguments: argChunk,
                    },
                  },
                ],
              },
              finish_reason: null,
            },
          ],
        });
      }

      // Finish chunk
      writeSSE(res, {
        id: completionId,
        object: 'chat.completion.chunk',
        created,
        model,
        choices: [
          {
            index: 0,
            delta: {},
            finish_reason: 'tool_calls',
          },
        ],
      });

      writeSSEDone(res);
      return;
    }

    // Stream text content deltas
    await streamText({
      text: generated.content,
      res,
      delayMs: streamDelayMs,
      chunkStrategy,
      onChunk: (chunk) => {
        writeSSE(res, {
          id: completionId,
          object: 'chat.completion.chunk',
          created,
          model,
          choices: [
            {
              index: 0,
              delta: { content: chunk },
              finish_reason: null,
            },
          ],
        });
      },
    });

    // Stream final stop chunk
    writeSSE(res, {
      id: completionId,
      object: 'chat.completion.chunk',
      created,
      model,
      choices: [
        {
          index: 0,
          delta: {},
          finish_reason: 'stop',
        },
      ],
      usage: {
        prompt_tokens: 20,
        completion_tokens: Math.ceil(generated.content.length / 4),
        total_tokens: 20 + Math.ceil(generated.content.length / 4),
      },
    });

    writeSSEDone(res);
  } catch (err) {
    sendError(res, err, 'openai');
  }
}
