import { Router } from 'express';
import { handleAnthropicMessages } from './messages';

export const anthropicRouter = Router();

// Anthropic routes
anthropicRouter.post('/messages', handleAnthropicMessages);
anthropicRouter.post('/v1/messages', handleAnthropicMessages);
