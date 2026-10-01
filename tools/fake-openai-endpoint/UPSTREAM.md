# Upstream snapshot

This directory contains the user-supplied snapshot of `seyf1elislam/fake_openai_endpoint_ts`
(commit `d1105bf2573d95b043f5e1d0c5c427aa316d4487`) used as the protocol reference
for GameSmith's OpenAI-compatible integration tests.

GameSmith adds `gamesmith-server.mjs`, a zero-dependency scripted `/v1/chat/completions`
server. It intentionally uses only Node's standard library so the GameSmith acceptance suite
can run offline without `npm install`. The original upstream TypeScript project remains here
for broader API simulation and can still be used with its own npm workflow.
