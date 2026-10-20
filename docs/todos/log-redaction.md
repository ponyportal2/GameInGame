# Log credential redaction

- [x] Redact JSON credential fields and bare bearer tokens.
- [x] Keep ordinary token counters readable.
- [x] Regress both directions in the core host fixture.

## Change

`AppLogger.redact` covered `Authorization: Bearer`, `api_key=`, JSON
`authorization`/`api_key` fields and `sk-` keys. Provider error bodies and token
refresh responses can also echo `access_token`, `refresh_token`, `id_token`,
`client_secret`, `private_key` or `password` without an Authorization header, and
a bare `Bearer <token>` was only redacted when preceded by `authorization`.

Added JSON and `key=value` rules for those field names, a bare `bearer <token>`
rule, and GitHub `gh[pousr]_` tokens. Deliberately excluded `tokens`,
`max_tokens` and `tokenizer` so compaction diagnostics remain readable.

## Verification (2026-10-20)

- RED: `%TEMP%/gamesmith-verify-*` `host:test` failed two assertions (JSON token
  fields and bare bearer/GitHub tokens) before the change.
- GREEN: `%TEMP%/gamesmith-verify-loUIKK/results.json` — `host:test` passed all
  assertions, including the new negative and positive redaction checks.

Limitations: pattern-based redaction is best effort. Credentials in an
unrecognized shape, or split across log lines, are not covered. No full-suite or
packaged run was performed, and no real-provider calls were used.
