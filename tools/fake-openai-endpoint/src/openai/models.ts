import { Request, Response } from 'express';
import { ModelInfo } from '../types';
import { sendOpenAIError } from '../utils/errors';

export const OPENAI_MODELS: ModelInfo[] = [
  {
    id: 'gpt-4o',
    object: 'model',
    created: 1715367049,
    owned_by: 'system',
    capabilities: ['text', 'vision', 'tools', 'streaming'],
  },
  {
    id: 'gpt-4o-mini',
    object: 'model',
    created: 1721235600,
    owned_by: 'system',
    capabilities: ['text', 'vision', 'tools', 'streaming'],
  },
  {
    id: 'gpt-4-turbo',
    object: 'model',
    created: 1712361441,
    owned_by: 'system',
    capabilities: ['text', 'vision', 'tools', 'streaming'],
  },
  {
    id: 'gpt-3.5-turbo',
    object: 'model',
    created: 1677610602,
    owned_by: 'openai',
    capabilities: ['text', 'tools', 'streaming'],
  },
  {
    id: 'o1-preview',
    object: 'model',
    created: 1725800000,
    owned_by: 'system',
    capabilities: ['text', 'reasoning'],
  },
  {
    id: 'o1-mini',
    object: 'model',
    created: 1725800000,
    owned_by: 'system',
    capabilities: ['text', 'reasoning'],
  },
  {
    id: 'dall-e-3',
    object: 'model',
    created: 1698785189,
    owned_by: 'system',
    capabilities: ['image'],
  },
  {
    id: 'tts-1',
    object: 'model',
    created: 1681940951,
    owned_by: 'openai-internal',
    capabilities: ['audio_speech'],
  },
  {
    id: 'tts-1-hd',
    object: 'model',
    created: 1681940951,
    owned_by: 'openai-internal',
    capabilities: ['audio_speech'],
  },
  {
    id: 'whisper-1',
    object: 'model',
    created: 1677532384,
    owned_by: 'openai-internal',
    capabilities: ['audio_transcription'],
  },
  {
    id: 'text-embedding-3-small',
    object: 'model',
    created: 1705948997,
    owned_by: 'system',
    capabilities: ['embeddings'],
  },
  {
    id: 'text-embedding-3-large',
    object: 'model',
    created: 1705948997,
    owned_by: 'system',
    capabilities: ['embeddings'],
  },
  // Simulation & testing models
  {
    id: 'fake-gpt',
    object: 'model',
    created: 1700000000,
    owned_by: 'fake-ai',
    capabilities: ['text', 'streaming', 'tools', 'json'],
  },
  {
    id: 'fake-gpt-slow',
    object: 'model',
    created: 1700000000,
    owned_by: 'fake-ai',
    capabilities: ['text', 'streaming', 'slow_latency'],
  },
  {
    id: 'fake-gpt-fast',
    object: 'model',
    created: 1700000000,
    owned_by: 'fake-ai',
    capabilities: ['text', 'streaming', 'zero_latency'],
  },
  {
    id: 'fake-gpt-tool',
    object: 'model',
    created: 1700000000,
    owned_by: 'fake-ai',
    capabilities: ['tools'],
  },
  {
    id: 'fake-gpt-error',
    object: 'model',
    created: 1700000000,
    owned_by: 'fake-ai',
    capabilities: ['error_simulation'],
  },
];

export function handleListModels(_req: Request, res: Response) {
  return res.json({
    object: 'list',
    data: OPENAI_MODELS,
  });
}

export function handleGetModel(req: Request, res: Response) {
  const modelId = req.params.model;
  const model = OPENAI_MODELS.find((m) => m.id === modelId);

  if (!model) {
    return sendOpenAIError(
      res,
      404,
      `The model '${modelId}' does not exist`,
      'invalid_request_error',
      'model_not_found'
    );
  }

  return res.json(model);
}
