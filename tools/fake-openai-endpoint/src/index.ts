import { createApp } from './server/app';
import { config } from './config';
import { logger } from './utils/logger';

const app = createApp();

const server = app.listen(config.port, config.host, () => {
  const baseUrl = `http://${config.host === '0.0.0.0' ? 'localhost' : config.host}:${config.port}`;

  console.log(`
============================================================
       🚀 Fake AI API Simulator (v2.0.0) Running
============================================================
  Base URL:        ${baseUrl}
  OpenAI Base:     ${baseUrl}/v1
  Anthropic Base:  ${baseUrl}/v1

  📡 Key Simulated Endpoints:
    GET  /v1/models
    POST /v1/chat/completions       (stream & non-stream)
    POST /v1/responses              (OpenAI Responses API)
    POST /v1/images/generations     (SVG & Base64 PNG)
    POST /v1/audio/speech           (Procedural WAV & MP3)
    POST /v1/audio/transcriptions   (Whisper transcription)
    POST /v1/embeddings             (Deterministic vectors)
    POST /v1/messages               (Anthropic Claude SSE)
    GET  /health                    (Healthcheck)

  ⚙️ Configuration:
    Default Delay: ${config.defaultDelayMs}ms
    Stream Delay:  ${config.streamDelayMs}ms
    Deterministic: ${config.deterministic} (seed: ${config.seed})
    Auth Required: ${config.apiKey ? 'YES (Key Configured)' : 'NO (Open Access)'}
============================================================
`);
});

// Graceful shutdown handling
function handleShutdown(signal: string) {
  logger.info(`Received ${signal}. Closing server gracefully...`);
  server.close(() => {
    logger.info('Server closed. Process exiting cleanly.');
    process.exit(0);
  });

  // Force close if graceful shutdown takes too long
  setTimeout(() => {
    logger.error('Forcefully terminating after timeout.');
    process.exit(1);
  }, 5000).unref();
}

process.on('SIGINT', () => handleShutdown('SIGINT'));
process.on('SIGTERM', () => handleShutdown('SIGTERM'));

export { app, server };
