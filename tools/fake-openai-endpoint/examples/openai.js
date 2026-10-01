/**
 * Example demonstrating how to use the Fake AI API server with standard fetch or OpenAI SDK.
 *
 * Run with: node examples/openai.js
 */

const SERVER_URL = 'http://localhost:3000/v1';

async function main() {
  console.log('--- 1. List Models ---');
  const modelsRes = await fetch(`${SERVER_URL}/models`);
  const models = await modelsRes.json();
  console.log('Available models count:', models.data.length);
  console.log('First 3 models:', models.data.slice(0, 3).map((m) => m.id));

  console.log('\n--- 2. Chat Completions (Non-Streaming) ---');
  const chatRes = await fetch(`${SERVER_URL}/chat/completions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'gpt-4o',
      messages: [{ role: 'user', content: 'What are the main benefits of local AI simulation?' }],
    }),
  });
  const chatData = await chatRes.json();
  console.log('Response content:\n', chatData.choices[0].message.content);

  console.log('\n--- 3. Chat Completions (Streaming SSE) ---');
  const streamRes = await fetch(`${SERVER_URL}/chat/completions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'fake-gpt',
      messages: [{ role: 'user', content: 'Tell me a quick joke.' }],
      stream: true,
    }),
  });

  const reader = streamRes.body.getReader();
  const decoder = new TextDecoder();
  process.stdout.write('Stream chunks: ');
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    const chunk = decoder.decode(value);
    for (const line of chunk.split('\n')) {
      if (line.startsWith('data: ') && !line.includes('[DONE]')) {
        try {
          const parsed = JSON.parse(line.slice(6));
          const content = parsed.choices?.[0]?.delta?.content || '';
          process.stdout.write(content);
        } catch {}
      }
    }
  }
  console.log('\n[Stream Completed]');

  console.log('\n--- 4. Embeddings ---');
  const embedRes = await fetch(`${SERVER_URL}/embeddings`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'text-embedding-3-small',
      input: 'Semantic search query for vector database',
    }),
  });
  const embedData = await embedRes.json();
  console.log('Generated embedding vector length:', embedData.data[0].embedding.length);
  console.log('First 5 dimensions:', embedData.data[0].embedding.slice(0, 5));

  console.log('\n--- 5. Image Generation ---');
  const imgRes = await fetch(`${SERVER_URL}/images/generations`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'dall-e-3',
      prompt: 'A futuristic cybernetic city skyline at sunset',
      n: 1,
    }),
  });
  const imgData = await imgRes.json();
  console.log('Image URL (data URI prefix):', imgData.data[0].url.slice(0, 40) + '...');
}

main().catch(console.error);
