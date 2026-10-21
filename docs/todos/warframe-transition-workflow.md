# Warframe transition-testing workflow

- [x] Regress the shared instructions through all production harness prompt generators.
- [x] Merge transition preservation, upfront observability, test reuse, natural tuning parameters and helper cleanup into existing rules without growing the prompt.
- [x] Run focused prompt/assembly verification and packaged prompt acceptance; record results.

Scope: instructions and contract coverage only. Keep action waits, runtime APIs, preflight/approval safeguards and the player's Warframe files unchanged. These contracts verify instruction delivery, not real-model compliance or an iteration-time improvement.

Verification (2026-10-20):

- Red: `gamesmith-verify-TsxnVR` failed the new prompt contracts against the old instructions as expected.
- Green: `node tools/testing/verify.mjs --suite affected --changed src/agent/game_prompt.gd,tests/prompt_contract_runner.gd --output summary --reuse %TEMP%/gamesmith-verify-6csO4B/results.json` completed in 47.1 seconds: setup plus three entries passed, 1,367 assertions, zero failures, zero reused entries. Results: `%TEMP%/gamesmith-verify-kY4LsB/results.json`.
- Rebuilt `GameSmith-Windows/GameSmith.pck`. Executed its `res://tests/prompt_contract_runner.gd` in isolated user data: 1,343 assertions passed, zero failed, process exit 0. Logs: `%TEMP%/gamesmith-packaged-prompt-abe36f4e05ac4888a1948326f24e1359/`.
- Prompt size: 2,263 to 2,233 whitespace-delimited words; unchanged 35 bullets.
- Selection correction: the initial automatic affected run (`gamesmith-verify-6csO4B`) included unrelated untracked `Brain.txt` and therefore selected the full suite. Stopped that run after discovering the expansion; it is interrupted evidence, not a completed full-suite pass. Final focused selection explicitly lists the changed inputs.
- No real-provider invocation or Warframe replay; no claim of measured workflow speedup. No CI dispatched. Unrelated user files preserved.
