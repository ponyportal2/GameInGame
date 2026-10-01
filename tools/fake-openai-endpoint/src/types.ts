export interface Message {
  role: 'system' | 'user' | 'assistant' | 'tool';
  content?:
    | string
    | null
    | Array<{ type: string; text?: string; image_url?: { url: string }; [key: string]: unknown }>;
  name?: string;
  tool_calls?: ToolCall[];
  tool_call_id?: string;
}

export interface ToolCall {
  id: string;
  type: 'function';
  function: {
    name: string;
    arguments: string;
  };
}

export interface ToolDefinition {
  type: 'function';
  function: {
    name: string;
    description?: string;
    parameters?: Record<string, unknown>;
  };
}

export type ChunkStrategy = 'word' | 'char' | 'sentence' | 'token';

export interface FakeBehavior {
  delay?: number;
  streamDelay?: number;
  error?: number;
  chunk?: ChunkStrategy;
  toolCall?: boolean;
  invalidJson?: boolean;
  partialResponse?: boolean;
}

export interface TextGenerationOptions {
  model: string;
  messages?: Message[];
  prompt?: string;
  stream?: boolean;
  tools?: ToolDefinition[];
  tool_choice?: unknown;
  response_format?: { type: string; json_schema?: unknown };
  behavior?: FakeBehavior;
  signal?: AbortSignal;
}

export interface ImageGenerationOptions {
  model: string;
  prompt: string;
  n?: number;
  size?: string;
  response_format?: 'url' | 'b64_json';
  behavior?: FakeBehavior;
}

export interface AudioSpeechOptions {
  model: string;
  input: string;
  voice?: string;
  response_format?: 'mp3' | 'wav' | 'aac' | 'flac';
  speed?: number;
  stream?: boolean;
  behavior?: FakeBehavior;
  signal?: AbortSignal;
}

export interface AudioTranscriptionOptions {
  model: string;
  file?: { buffer: Buffer; originalname: string; mimetype: string };
  prompt?: string;
  response_format?: 'json' | 'text' | 'verbose_json';
  language?: string;
  behavior?: FakeBehavior;
}

export interface EmbeddingOptions {
  model: string;
  input: string | string[];
  dimensions?: number;
  behavior?: FakeBehavior;
}

export interface ModelInfo {
  id: string;
  object: 'model';
  created: number;
  owned_by: string;
  capabilities: string[];
}
