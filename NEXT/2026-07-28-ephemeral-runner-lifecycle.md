# Make `RUNNER_EPHEMERAL` a tested lifecycle — 2026-07-28

Make `RUNNER_EPHEMERAL` a tested fresh-container lifecycle: `gha` now
supervises one-job `--rm` children, rejects ambiguous booleans and one-shot
credentials, keeps the Docker socket out of isolated jobs by default, and
integration-tests that writable-layer markers cannot cross generations or
survive a signalled controller shutdown (#33).
