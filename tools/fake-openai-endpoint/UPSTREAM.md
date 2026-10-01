# Upstream snapshot

This directory contains the user-supplied snapshot of `seyf1elislam/fake_openai_endpoint_ts`
(commit `d1105bf2573d95b043f5e1d0c5c427aa316d4487`) retained as OpenAI-compatible
protocol/testing reference material.

GameSmith adds `pi-server.mjs`, a zero-dependency deterministic streaming
`/v1/chat/completions` server used by the real-Pi acceptance suite. It uses only
Node's standard library, so GameSmith's scripted workflow needs no `npm install`.
The original upstream TypeScript project remains available here for broader API
simulation with its own npm workflow.
