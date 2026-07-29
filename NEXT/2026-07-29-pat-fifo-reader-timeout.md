# Report PAT FIFO reader timeouts — 2026-07-29

Report a typed, actionable timeout when PAT delivery cannot open its FIFO
because no reader connects before the deadline, while preserving the
underlying system error for diagnosis (#53).
