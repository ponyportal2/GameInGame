import { Router } from 'express';
import multer from 'multer';
import { handleListModels, handleGetModel } from './models';
import { handleChatCompletions } from './chat';
import { handleResponses } from './responses';
import { handleImageGenerations, handleImageEdits } from './images';
import { handleAudioSpeech, handleAudioTranscriptions, handleAudioTranslations } from './audio';
import { handleEmbeddings } from './embeddings';

const upload = multer({ storage: multer.memoryStorage() });

export const openaiRouter = Router();

// Models
openaiRouter.get('/models', handleListModels);
openaiRouter.get('/models/:model', handleGetModel);

// Chat & Responses
openaiRouter.post('/chat/completions', handleChatCompletions);
openaiRouter.post('/responses', handleResponses);

// Images
openaiRouter.post('/images/generations', handleImageGenerations);
openaiRouter.post('/images/edits', upload.single('image'), handleImageEdits);

// Audio
openaiRouter.post('/audio/speech', handleAudioSpeech);
openaiRouter.post('/audio/transcriptions', upload.single('file'), handleAudioTranscriptions);
openaiRouter.post('/audio/translations', upload.single('file'), handleAudioTranslations);

// Embeddings
openaiRouter.post('/embeddings', handleEmbeddings);
