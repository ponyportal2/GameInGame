import { Request, Response } from 'express';
import { z } from 'zod';
import { extractBehavior } from '../config';
import { fakeEngine } from '../fake/engine';
import { sendError, sendOpenAIError } from '../utils/errors';

const EmbeddingSchema = z.object({
  model: z.string().min(1, 'model is required'),
  input: z.union([
    z.string(),
    z.array(z.string()),
    z.array(z.number()),
    z.array(z.array(z.number())),
  ]),
  dimensions: z.number().optional(),
  user: z.string().optional(),
});

export async function handleEmbeddings(req: Request, res: Response) {
  const parseResult = EmbeddingSchema.safeParse(req.body);
  if (!parseResult.success) {
    return sendOpenAIError(
      res,
      400,
      `Invalid request schema: ${parseResult.error.errors.map((e) => e.message).join(', ')}`
    );
  }

  const { model, input, dimensions } = parseResult.data;
  const behavior = extractBehavior(req.headers, model);

  try {
    const stringInputs = Array.isArray(input)
      ? (input as unknown[]).map((item) => (typeof item === 'string' ? item : JSON.stringify(item)))
      : [String(input)];

    const result = await fakeEngine.generateEmbeddings({
      model,
      input: stringInputs,
      dimensions,
      behavior,
    });

    return res.json(result);
  } catch (err) {
    sendError(res, err, 'openai');
  }
}
