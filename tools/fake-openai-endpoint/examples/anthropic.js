/**
 * Example demonstrating how to use the Fake AI API server with Anthropic Messages API format.
 *
 * Run with: node examples/anthropic.js
 */

const SERVER_URL = 'http://localhost:3000/v1';

async function main() {
  console.log('--- 1. Anthropic Messages (Non-Streaming) ---');
  const res = await fetch(`${SERVER_URL}/messages`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: 'claude-3-5-sonnet-20241022',
      messages: [{ role: 'user', content: 'Explain quantum computing in simple terms.' }],
      max_tokens: 1024,
    }),
  });

  const data = await res.json();
  console.log('Anthropic Response:');
  console.log('Type:', data.type);
  console.log('Role:', data.role);
  console.log('Content:', data.content[0].text);
  console.log('Stop reason:', data.stop_reason);

  console.log('\n--- 2. Anthropic Messages (Streaming SSE) ---');
  const streamRes = await fetch(`${SERVER_URL}/messages`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: 'claude-3-5-sonnet-20241022',
      messages: [{ role: 'user', content: 'Stream this message chunk by chunk.' }],
      stream: true,
    }),
  });

  const reader = streamRes.body.getReader();
  const decoder = new TextDecoder();
  process.stdout.write('Claude Stream: ');
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    const chunk = decoder.decode(value);
    for (const line of chunk.split('\n')) {
      if (line.startsWith('data: ')) {
        try {
          const parsed = JSON.parse(line.slice(6));
          if (parsed.type === 'content_block_delta' && parsed.delta?.text) {
            process.stdout.write(parsed.delta.text);
          }
        } catch {}
      }
    }
  }
  console.log('\n[Anthropic Stream Completed]');
}

main().catch(console.error);
