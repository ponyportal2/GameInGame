import { Request, Response } from 'express';
import { z } from 'zod';
import { extractBehavior, config } from '../config';
import { fakeEngine } from '../fake/engine';
import { streamBytes } from '../streaming/stream';
import { sendError, sendOpenAIError } from '../utils/errors';

const SpeechSchema = z.object({
  model: z.string().optional().default('tts-1'),
  input: z.string().min(1, 'input is required'),
  voice: z.string().optional().default('alloy'),
  response_format: z.enum(['mp3', 'wav', 'aac', 'flac', 'opus']).optional().default('mp3'),
  speed: z.number().optional().default(1.0),
});

export async function handleAudioSpeech(req: Request, res: Response) {
  const parseResult = SpeechSchema.safeParse(req.body);
  if (!parseResult.success) {
    return sendOpenAIError(
      res,
      400,
      `Invalid request schema: ${parseResult.error.errors.map((e) => e.message).join(', ')}`
    );
  }

  const { model, input, voice, response_format, speed } = parseResult.data;
  const behavior = extractBehavior(req.headers, model);
  const isStreaming = req.query.stream === 'true' || behavior.streamDelay !== undefined;

  try {
    const audioBuffer = await fakeEngine.generateSpeech({
      model,
      input,
      voice,
      response_format: response_format as 'mp3' | 'wav' | 'aac' | 'flac',
      speed,
      stream: isStreaming,
      behavior,
    });

    const contentType = response_format === 'wav' ? 'audio/wav' : 'audio/mpeg';
    const headers: Record<string, string | number> = {
      'Content-Type': contentType,
      'Cache-Control': 'no-cache',
    };

    if (isStreaming) {
      headers['Transfer-Encoding'] = 'chunked';
    } else {
      headers['Content-Length'] = audioBuffer.length;
    }

    res.writeHead(200, headers);

    if (isStreaming) {
      const streamDelayMs = behavior.streamDelay ?? config.streamDelayMs;
      await streamBytes({
        buffer: audioBuffer,
        res,
        chunkSize: 2048,
        delayMs: streamDelayMs,
      });
      res.end();
    } else {
      res.end(audioBuffer);
    }
  } catch (err) {
    sendError(res, err, 'openai');
  }
}

export async function handleAudioTranscriptions(req: Request, res: Response) {
  const model = req.body.model || 'whisper-1';
  const prompt = req.body.prompt;
  const response_format = req.body.response_format || 'json';
  const language = req.body.language;
  const behavior = extractBehavior(req.headers, model);

  try {
    const file = req.file
      ? {
          buffer: req.file.buffer,
          originalname: req.file.originalname,
          mimetype: req.file.mimetype,
        }
      : undefined;

    const result = await fakeEngine.transcribeAudio({
      model,
      file,
      prompt,
      response_format,
      language,
      behavior,
    });

    if (response_format === 'text') {
      res.setHeader('Content-Type', 'text/plain');
      return res.send(result);
    }

    return res.json(result);
  } catch (err) {
    sendError(res, err, 'openai');
  }
}

export async function handleAudioTranslations(req: Request, res: Response) {
  const model = req.body.model || 'whisper-1';
  const prompt = req.body.prompt || 'Translated audio stream';
  const response_format = req.body.response_format || 'json';
  const behavior = extractBehavior(req.headers, model);

  try {
    const result = await fakeEngine.transcribeAudio({
      model,
      prompt,
      response_format,
      language: 'en',
      behavior,
    });

    if (response_format === 'text') {
      res.setHeader('Content-Type', 'text/plain');
      return res.send(result);
    }

    return res.json(result);
  } catch (err) {
    sendError(res, err, 'openai');
  }
}
