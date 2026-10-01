import { AudioSpeechOptions, AudioTranscriptionOptions } from '../types';

/**
 * Creates a valid RIFF/WAVE PCM audio buffer (mono, 16-bit, 22050Hz).
 * Generates a pleasant soft sine wave chirp / audio burst so the returned buffer is real playable audio!
 */
export function generateSyntheticWavBuffer(
  durationSeconds: number = 1.5,
  frequencyHz: number = 440
): Buffer {
  const sampleRate = 22050;
  const numChannels = 1;
  const bitsPerSample = 16;
  const blockAlign = (numChannels * bitsPerSample) / 8;
  const byteRate = sampleRate * blockAlign;
  const totalSamples = Math.floor(sampleRate * durationSeconds);
  const dataSize = totalSamples * blockAlign;
  const buffer = Buffer.alloc(44 + dataSize);

  // RIFF identifier
  buffer.write('RIFF', 0);
  // File size minus 8
  buffer.writeUInt32LE(36 + dataSize, 4);
  // RIFF type
  buffer.write('WAVE', 8);
  // Format chunk marker
  buffer.write('fmt ', 12);
  // Format chunk length (16 for PCM)
  buffer.writeUInt32LE(16, 16);
  // Sample format (1 is PCM)
  buffer.writeUInt16LE(1, 20);
  // Channels
  buffer.writeUInt16LE(numChannels, 22);
  // Sample rate
  buffer.writeUInt32LE(sampleRate, 24);
  // Byte rate
  buffer.writeUInt32LE(byteRate, 28);
  // Block align
  buffer.writeUInt16LE(blockAlign, 32);
  // Bits per sample
  buffer.writeUInt16LE(bitsPerSample, 34);
  // Data chunk header
  buffer.write('data', 36);
  buffer.writeUInt32LE(dataSize, 40);

  // Write sine wave samples
  for (let i = 0; i < totalSamples; i++) {
    const t = i / sampleRate;
    // Apply soft envelope to prevent clicks
    const envelope = Math.sin((Math.PI * i) / totalSamples);
    const sample = Math.sin(2 * Math.PI * frequencyHz * t) * 0.3 * envelope;
    const intSample = Math.max(-32768, Math.min(32767, Math.floor(sample * 32767)));
    buffer.writeInt16LE(intSample, 44 + i * 2);
  }

  return buffer;
}

/**
 * Handles fake audio speech synthesis.
 */
export function generateAudioSpeech(options: AudioSpeechOptions): Buffer {
  const duration = Math.min(5, Math.max(0.5, options.input.length * 0.05));
  return generateSyntheticWavBuffer(duration, 520);
}

/**
 * Handles fake audio transcription.
 */
export function generateTranscription(options: AudioTranscriptionOptions) {
  const format = options.response_format || 'json';
  const simulatedText = options.prompt
    ? `Simulated transcription responding to: "${options.prompt}"`
    : 'This is a simulated audio transcription produced by the local Fake AI API server.';

  if (format === 'text') {
    return simulatedText;
  }

  if (format === 'verbose_json') {
    return {
      task: 'transcribe',
      language: options.language || 'english',
      duration: 3.5,
      text: simulatedText,
      segments: [
        {
          id: 0,
          seek: 0,
          start: 0.0,
          end: 3.5,
          text: simulatedText,
          tokens: [50364, 1234, 5678, 50539],
          temperature: 0.0,
          avg_logprob: -0.25,
          compression_ratio: 1.1,
          no_speech_prob: 0.01,
        },
      ],
    };
  }

  return {
    text: simulatedText,
  };
}
