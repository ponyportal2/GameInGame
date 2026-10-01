import { Request, Response } from 'express';
import { z } from 'zod';
import { extractBehavior } from '../config';
import { fakeEngine } from '../fake/engine';
import { sendError, sendOpenAIError } from '../utils/errors';

const ImageGenerationSchema = z.object({
  prompt: z.string().min(1, 'prompt is required'),
  model: z.string().optional().default('dall-e-3'),
  n: z.number().optional().default(1),
  size: z.string().optional().default('1024x1024'),
  response_format: z.enum(['url', 'b64_json']).optional().default('url'),
  quality: z.string().optional(),
  style: z.string().optional(),
});

export async function handleImageGenerations(req: Request, res: Response) {
  const parseResult = ImageGenerationSchema.safeParse(req.body);
  if (!parseResult.success) {
    return sendOpenAIError(
      res,
      400,
      `Invalid request schema: ${parseResult.error.errors.map((e) => e.message).join(', ')}`
    );
  }

  const { prompt, model, n, size, response_format } = parseResult.data;
  const behavior = extractBehavior(req.headers, model);

  try {
    const result = await fakeEngine.generateImage({
      prompt,
      model,
      n,
      size,
      response_format,
      behavior,
    });

    return res.json(result);
  } catch (err) {
    sendError(res, err, 'openai');
  }
}

export async function handleImageEdits(req: Request, res: Response) {
  const prompt = req.body.prompt || 'Edited simulated image';
  const model = req.body.model || 'dall-e-2';
  const n = req.body.n ? parseInt(req.body.n, 10) : 1;
  const size = req.body.size || '1024x1024';
  const response_format = req.body.response_format || 'url';
  const behavior = extractBehavior(req.headers, model);

  try {
    const result = await fakeEngine.generateImage({
      prompt,
      model,
      n,
      size,
      response_format,
      behavior,
    });

    return res.json(result);
  } catch (err) {
    sendError(res, err, 'openai');
  }
}
