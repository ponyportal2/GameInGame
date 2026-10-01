# Fake AI API Simulator (OpenAI & Anthropic)

A fast, lightweight, protocol-compatible local AI API simulator for frontend/backend development, integration testing, CI/CD pipelines, SDK compatibility verification, streaming UX testing, and error resilience testing.

Simulate **OpenAI** and **Anthropic** endpoints locally with **zero real API costs**, **no rate limits**, and **deterministic outputs**.

---

## ⚡ Features

- **Protocol Compatibility**: Works directly with official `@openai/openai`, `@anthropic-ai/sdk`, `fetch`, Python `requests`, LangChain, and other AI SDKs by simply pointing `baseURL` to `http://localhost:3000/v1`.
- **Streaming & SSE**: High-fidelity Server-Sent Events (SSE) streaming with word, char, sentence, or token chunking, realistic delays, and abort cancellation.
- **Modern OpenAI APIs**:
  - `GET /v1/models` & `GET /v1/models/:model`
  - `POST /v1/chat/completions` (streaming & non-streaming, function/tool calling)
  - `POST /v1/responses` (modern OpenAI Responses API)
  - `POST /v1/images/generations` & `POST /v1/images/edits` (SVG & Base64 PNG)
  - `POST /v1/audio/speech` (generates real playable WAV audio buffers & streamable bytes)
  - `POST /v1/audio/transcriptions` & `POST /v1/audio/translations` (Whisper mock)
  - `POST /v1/embeddings` (deterministic float vectors)
- **Anthropic Claude APIs**:
  - `POST /v1/messages` (non-streaming and Anthropic SSE events: `message_start`, `content_block_start`, `content_block_delta`, `message_delta`, `message_stop`)
  - Tool/Function calling (`tool_use` blocks)
- **Simulation Scenarios & Failure Testing**:
  - Simulate slow latencies, timeouts, 429 rate limits, 500 server errors, tool calls, and invalid JSON using HTTP headers or model names.
- **Deterministic Mode**: Seeded pseudo-random generation produces consistent responses and embeddings across test runs.
- **Zero Heavy Infrastructure**: Built purely in TypeScript with Express, zero heavy databases or message brokers.

---

## 🚀 Quick Start

### 1. Installation

```bash
git clone https://github.com/seyf1elislam/fake_openai_endpoint_ts.git
cd fake_openai_endpoint_ts
npm install
```

### 2. Run the Development Server

```bash
npm run dev
```

The simulator will start on `http://localhost:3000`.

### 3. Run Tests & Typecheck

```bash
npm test          # Run test suite with Vitest
npm run typecheck # Strict TypeScript check
npm run build     # Build production output to dist/
npm start         # Run production server
```

---

## 📡 API Reference & Curl Examples

### 1. OpenAI Chat Completions (`/v1/chat/completions`)

#### Non-Streaming
```bash
curl http://localhost:3000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Explain quantum computing in one sentence."}
    ]
  }'
```

#### Streaming SSE
```bash
curl -N http://localhost:3000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [{"role": "user", "content": "Stream a story."}],
    "stream": true
  }'
```

#### Tool / Function Calling
```bash
curl http://localhost:3000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "fake-gpt-tool",
    "messages": [{"role": "user", "content": "What is the weather in San Francisco?"}],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get current weather",
          "parameters": {
            "type": "object",
            "properties": { "location": { "type": "string" } }
          }
        }
      }
    ]
  }'
```

---

### 2. OpenAI Modern Responses API (`/v1/responses`)

```bash
curl http://localhost:3000/v1/responses \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "input": "Summarize latest developments in artificial intelligence."
  }'
```

---

### 3. Anthropic Messages API (`/v1/messages` or `/messages`)

#### Non-Streaming
```bash
curl http://localhost:3000/v1/messages \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "messages": [{"role": "user", "content": "Hello Claude!"}],
    "max_tokens": 1024
  }'
```

#### Streaming SSE
```bash
curl -N http://localhost:3000/v1/messages \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "messages": [{"role": "user", "content": "Stream response."}],
    "stream": true
  }'
```

---

### 4. Image Generation (`/v1/images/generations`)

```bash
curl http://localhost:3000/v1/images/generations \
  -H "Content-Type: application/json" \
  -d '{
    "model": "dall-e-3",
    "prompt": "A modern cybernetic cityscape in synthwave neon",
    "size": "1024x1024",
    "response_format": "url"
  }'
```

---

### 5. Audio Speech Synthesis (`/v1/audio/speech`)

```bash
curl http://localhost:3000/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{
    "model": "tts-1",
    "input": "Hello! This is genuine synthetic audio generated by the local Fake AI API server.",
    "voice": "alloy",
    "response_format": "wav"
  }' --output speech.wav
```

---

### 6. Embeddings (`/v1/embeddings`)

```bash
curl http://localhost:3000/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{
    "model": "text-embedding-3-small",
    "input": "Semantic search query for vector store"
  }'
```

---

## 🎛️ Simulation Controls & Scenarios

You can dynamically alter the simulator's behavior using **HTTP Headers** or **Model Names**:

| Header / Option | Values | Description |
| :--- | :--- | :--- |
| `x-scenario` | `slow`, `fast`, `error-500`, `error-429`, `tool`, `invalid-json`, `partial` | Triggers a predefined simulation scenario |
| `x-delay` | milliseconds (e.g. `2000`) | Adds artificial non-streaming latency |
| `x-stream-delay` | milliseconds (e.g. `50`) | Controls interval between SSE chunks |
| `x-error` | `400`, `401`, `429`, `500`, `503` | Forces an immediate simulated HTTP error response |
| `x-chunk` | `word`, `char`, `sentence`, `token` | Selects streaming chunking strategy |

#### Example: Testing Client Rate Limit Handling
```bash
curl -i http://localhost:3000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "x-error: 429" \
  -d '{"model": "gpt-4o", "messages": [{"role": "user", "content": "test"}]}'
```

---

## 💻 SDK Usage Examples

### Using Official OpenAI Node.js SDK
```javascript
import OpenAI from 'openai';

const openai = new OpenAI({
  apiKey: 'fake-key',
  baseURL: 'http://localhost:3000/v1',
});

const completion = await openai.chat.completions.create({
  model: 'gpt-4o',
  messages: [{ role: 'user', content: 'Hello!' }],
});
console.log(completion.choices[0].message.content);
```

### Using Official Anthropic Node.js SDK
```javascript
import Anthropic from '@anthropic-ai/sdk';

const anthropic = new Anthropic({
  apiKey: 'fake-key',
  baseURL: 'http://localhost:3000',
});

const message = await anthropic.messages.create({
  model: 'claude-3-5-sonnet-20241022',
  max_tokens: 1024,
  messages: [{ role: 'user', content: 'Hello Claude!' }],
});
console.log(message.content[0].text);
```

---

## ⚙️ Environment Variables

Copy `.env.example` to `.env` to configure:

```ini
PORT=3000
HOST=0.0.0.0
API_KEY=                 # If set, validates Bearer or x-api-key headers
DEFAULT_DELAY_MS=300     # Default non-streaming delay
STREAM_DELAY_MS=30       # Default inter-chunk delay
STREAM_CHUNK_STRATEGY=word
DETERMINISTIC=true       # Seeded reproducible outputs
SEED=42
CORS_ORIGIN=*
```

---

## 🧪 Testing

```bash
# Run unit, integration, and streaming tests
npm test

# Run tests with coverage
npm run test:coverage
```

---

## 📄 License

MIT
