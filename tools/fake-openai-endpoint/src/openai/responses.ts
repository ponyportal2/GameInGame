import { Request, Response } from 'express';
import { z } from 'zod';
import { extractBehavior, config } from '../config';
import { fakeEngine } from '../fake/engine';
import { initSSE, writeSSE, writeSSEDone } from '../streaming/sse';
import { streamText } from '../streaming/stream';
import { sendError, sendOpenAIError } from '../utils/errors';
import { Message } from '../types';

const ResponsesSchema = z.object({
  model: z.string().min(1, 'model is required'),
  input: z.union([z.string(), z.array(z.any())]).optional(),
  instructions: z.string().optional(),
  stream: z.boolean().optional().default(false),
  tools: z.array(z.any()).optional(),
  tool_choice: z.any().optional(),
  temperature: z.number().optional(),
  metadata: z.record(z.unknown()).optional(),
});

export async function handleResponses(req: Request, res: Response) {
  const parseResult = ResponsesSchema.safeParse(req.body);
  if (!parseResult.success) {
    return sendOpenAIError(
      res,
      400,
      `Invalid request schema: ${parseResult.error.errors.map((e) => e.message).join(', ')}`
    );
  }

  const { model, input, instructions, stream, tools } = parseResult.data;
  const behavior = extractBehavior(req.headers, model);
  const streamDelayMs = behavior.streamDelay ?? config.streamDelayMs;
  const chunkStrategy = behavior.chunk ?? config.streamChunkStrategy;

  // Convert input / instructions to messages representation
  const messages: Message[] = [];
  if (instructions) {
    messages.push({ role: 'system', content: instructions });
  }

  if (typeof input === 'string') {
    messages.push({ role: 'user', content: input });
  } else if (Array.isArray(input)) {
    for (const item of input) {
      if (typeof item === 'string') {
        messages.push({ role: 'user', content: item });
      } else if (typeof item === 'object' && item !== null && 'role' in item) {
        messages.push(item as Message);
      } else if (typeof item === 'object' && item !== null && 'content' in item) {
        messages.push({ role: 'user', content: (item as { content: string }).content });
      }
    }
  }

  try {
    const generated = await fakeEngine.generateText({
      model,
      messages,
      prompt: typeof input === 'string' ? input : undefined,
      stream,
      tools,
      behavior,
    });

    const responseId = `resp_${Math.random().toString(36).substring(2, 12)}`;
    const outputItemId = `msg_${Math.random().toString(36).substring(2, 12)}`;
    const createdAt = Math.floor(Date.now() / 1000);

    const fullText =
      generated.type === 'tool_call' ? JSON.stringify(generated.toolCall) : generated.content;
    const inputTokens = Math.ceil(JSON.stringify(messages).length / 4);
    const outputTokens = Math.ceil(fullText.length / 4);

    // Non-streaming response
    if (!stream) {
      return res.json({
        id: responseId,
        object: 'response',
        created_at: createdAt,
        status: 'completed',
        model,
        output: [
          {
            id: outputItemId,
            type: 'message',
            status: 'completed',
            role: 'assistant',
            content: [
              {
                type: 'output_text',
                text: fullText,
              },
            ],
          },
        ],
        usage: {
          input_tokens: inputTokens,
          output_tokens: outputTokens,
          total_tokens: inputTokens + outputTokens,
        },
      });
    }

    // Streaming mode
    initSSE(res);

    // 1. response.created
    writeSSE(
      res,
      {
        response: {
          id: responseId,
          object: 'response',
          created_at: createdAt,
          status: 'in_progress',
          model,
        },
      },
      'response.created'
    );

    // 2. response.output_item.added
    writeSSE(
      res,
      {
        response_id: responseId,
        output_index: 0,
        item: {
          id: outputItemId,
          type: 'message',
          status: 'in_progress',
          role: 'assistant',
          content: [],
        },
      },
      'response.output_item.added'
    );

    // 3. response.content_part.added
    writeSSE(
      res,
      {
        response_id: responseId,
        item_id: outputItemId,
        output_index: 0,
        content_index: 0,
        part: {
          type: 'output_text',
          text: '',
        },
      },
      'response.content_part.added'
    );

    // 4. response.text.delta stream
    await streamText({
      text: fullText,
      res,
      delayMs: streamDelayMs,
      chunkStrategy,
      onChunk: (chunk) => {
        writeSSE(
          res,
          {
            response_id: responseId,
            item_id: outputItemId,
            output_index: 0,
            content_index: 0,
            delta: chunk,
          },
          'response.text.delta'
        );
      },
    });

    // 5. response.text.done
    writeSSE(
      res,
      {
        response_id: responseId,
        item_id: outputItemId,
        output_index: 0,
        content_index: 0,
        text: fullText,
      },
      'response.text.done'
    );

    // 6. response.content_part.done
    writeSSE(
      res,
      {
        response_id: responseId,
        item_id: outputItemId,
        output_index: 0,
        content_index: 0,
        part: {
          type: 'output_text',
          text: fullText,
        },
      },
      'response.content_part.done'
    );

    // 7. response.output_item.done
    writeSSE(
      res,
      {
        response_id: responseId,
        output_index: 0,
        item: {
          id: outputItemId,
          type: 'message',
          status: 'completed',
          role: 'assistant',
          content: [
            {
              type: 'output_text',
              text: fullText,
            },
          ],
        },
      },
      'response.output_item.done'
    );

    // 8. response.completed
    writeSSE(
      res,
      {
        response: {
          id: responseId,
          object: 'response',
          created_at: createdAt,
          status: 'completed',
          model,
          output: [
            {
              id: outputItemId,
              type: 'message',
              status: 'completed',
              role: 'assistant',
              content: [
                {
                  type: 'output_text',
                  text: fullText,
                },
              ],
            },
          ],
          usage: {
            input_tokens: inputTokens,
            output_tokens: outputTokens,
            total_tokens: inputTokens + outputTokens,
          },
        },
      },
      'response.completed'
    );

    writeSSEDone(res);
  } catch (err) {
    sendError(res, err, 'openai');
  }
}
