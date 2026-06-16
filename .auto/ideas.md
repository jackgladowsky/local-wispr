# Local Wispr rewrite-loop optimization ideas

- Split fixtures into fast/plain, structured, and long buckets so future experiments can optimize routing thresholds with per-bucket metrics.
- Add optional JSONL per-case timing output for experiment analysis when p95 changes are noisy.
- Add a fixture-level `requiredTerminalPunctuation` or regex assertion if prompt changes start producing malformed endings.
- Explore streaming llama-server responses only if it improves perceived latency without complicating insertion semantics.
- Consider a tiny intent/router heuristic before LLM cleanup: plain sentence, command/list/email, and long-form dictation.
- Tried `LOCAL_WISPR_CLEANUP_NUM_PREDICT` sweep after routing: 9 tokens is the smallest passing default; 8 tokens drops `beta feedback` from the email-subject case.
- Tried context sizes 256/384/512/1024/2048 after routing; differences were noise-level, default context was as good or better than smaller contexts.
- Tried llama-server `--parallel 1/2`, continuous batching toggles, thread counts, batch/ubatch, flash attention, mlock, and GPU layer sweeps; no durable win beyond default plus full GPU layers/no explicit thread override.
- Raw direct HTTP benchmark added at `.auto/measure-raw-llama.sh`; it measures request send to full response body over loopback with synthetic repeated and varied cleanup prompts.
- Best retained raw request/server combo so far: compact ChatML prompt with explicit `um/uh/erm/ah` filler removal, `n_predict=38`, `temperature=0`, `cache_prompt=true`, full GPU offload, and llama-server ngram speculative decoding via `--spec-type ngram-mod --spec-ngram-mod-n-min 16 --spec-ngram-mod-n-max 32 --spec-ngram-mod-n-match 12`.
- 2026-06-16 raw direct benchmark result (default run, 60 measured / 8 warmup): repeated/cache-friendly p95 `30.460 ms`, varied cleanup p95 `79.793 ms`, invalid outputs `0`; improved from reference repeated ≈38 ms and varied ≈190 ms.
- 2026-06-15 verification run after README merge prep: `.auto/measure.sh` p95 `41.992 ms`, quality `1.000`, failed cases `0`, llama/local runs `5/15`; `.auto/measure-raw-llama.sh` repeated p95 `30.858 ms`, varied p95 `80.327 ms`, invalid outputs `0`.
