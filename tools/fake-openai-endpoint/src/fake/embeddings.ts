import { EmbeddingOptions } from '../types';

/**
 * Simple Mulberry32 pseudo-random number generator seeded by string hash.
 */
function hashString(str: string): number {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = (hash << 5) - hash + char;
    hash |= 0;
  }
  return hash;
}

function mulberry32(seed: number) {
  return function () {
    let t = (seed += 0x6d2b79f5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Generates deterministic fake embedding vector normalized to unit length.
 */
export function generateEmbeddingVector(text: string, dimensions: number = 1536): number[] {
  const seed = hashString(text);
  const random = mulberry32(seed);

  const vector: number[] = new Array(dimensions);
  let sumSq = 0;

  for (let i = 0; i < dimensions; i++) {
    // Generate numbers in range [-1, 1]
    const val = random() * 2 - 1;
    vector[i] = val;
    sumSq += val * val;
  }

  // Normalize
  const norm = Math.sqrt(sumSq) || 1;
  for (let i = 0; i < dimensions; i++) {
    vector[i] = Math.round((vector[i] / norm) * 1000000) / 1000000;
  }

  return vector;
}

/**
 * Generates embeddings response matching OpenAI format.
 */
export function generateEmbeddings(options: EmbeddingOptions) {
  const inputs = Array.isArray(options.input) ? options.input : [options.input];
  const dimensions = options.dimensions || (options.model.includes('3-large') ? 3072 : 1536);

  const data = inputs.map((text, index) => ({
    object: 'embedding' as const,
    index,
    embedding: generateEmbeddingVector(String(text), dimensions),
  }));

  const totalTokens = inputs.reduce((acc, curr) => acc + Math.ceil(String(curr).length / 4), 0);

  return {
    object: 'list' as const,
    data,
    model: options.model,
    usage: {
      prompt_tokens: totalTokens,
      total_tokens: totalTokens,
    },
  };
}
