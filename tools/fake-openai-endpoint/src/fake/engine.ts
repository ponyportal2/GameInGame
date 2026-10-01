import { config } from '../config';
import {
  TextGenerationOptions,
  ImageGenerationOptions,
  AudioSpeechOptions,
  AudioTranscriptionOptions,
  EmbeddingOptions,
} from '../types';
import { APIError } from '../utils/errors';
import { delay } from '../streaming/stream';
import { generateText, generateToolCall } from './text';
import { generateImages } from './image';
import { generateAudioSpeech, generateTranscription } from './audio';
import { generateEmbeddings } from './embeddings';

export const fakeEngine = {
  /**
   * Generates text or tool calls with behavior delay and error simulation.
   */
  async generateText(options: TextGenerationOptions) {
    const behavior = options.behavior || {};

    if (behavior.error) {
      throw new APIError(
        behavior.error,
        `Simulated error status ${behavior.error} triggered by scenario/header`,
        behavior.error === 429 ? 'rate_limit_error' : 'server_error'
      );
    }

    const waitMs = behavior.delay ?? config.defaultDelayMs;
    if (waitMs > 0 && !options.stream) {
      await delay(waitMs, options.signal);
    }

    const shouldToolCall =
      behavior.toolCall ||
      (options.tools &&
        options.tools.length > 0 &&
        options.tool_choice &&
        options.tool_choice !== 'none');

    if (shouldToolCall) {
      return {
        type: 'tool_call' as const,
        toolCall: generateToolCall(options),
      };
    }

    return {
      type: 'text' as const,
      content: generateText(options),
    };
  },

  /**
   * Generates mock images.
   */
  async generateImage(options: ImageGenerationOptions) {
    const behavior = options.behavior || {};
    if (behavior.error) {
      throw new APIError(behavior.error, `Simulated image generation error: ${behavior.error}`);
    }

    const waitMs = behavior.delay ?? config.defaultDelayMs;
    if (waitMs > 0) {
      await delay(waitMs);
    }

    return generateImages(options);
  },

  /**
   * Synthesizes fake speech.
   */
  async generateSpeech(options: AudioSpeechOptions) {
    const behavior = options.behavior || {};
    if (behavior.error) {
      throw new APIError(behavior.error, `Simulated speech synthesis error: ${behavior.error}`);
    }

    const waitMs = behavior.delay ?? config.defaultDelayMs;
    if (waitMs > 0 && !options.stream) {
      await delay(waitMs, options.signal);
    }

    return generateAudioSpeech(options);
  },

  /**
   * Transcribes audio.
   */
  async transcribeAudio(options: AudioTranscriptionOptions) {
    const behavior = options.behavior || {};
    if (behavior.error) {
      throw new APIError(behavior.error, `Simulated transcription error: ${behavior.error}`);
    }

    const waitMs = behavior.delay ?? config.defaultDelayMs;
    if (waitMs > 0) {
      await delay(waitMs);
    }

    return generateTranscription(options);
  },

  /**
   * Generates deterministic embeddings.
   */
  async generateEmbeddings(options: EmbeddingOptions) {
    const behavior = options.behavior || {};
    if (behavior.error) {
      throw new APIError(behavior.error, `Simulated embeddings error: ${behavior.error}`);
    }

    const waitMs = behavior.delay ?? config.defaultDelayMs;
    if (waitMs > 0) {
      await delay(waitMs);
    }

    return generateEmbeddings(options);
  },
};
