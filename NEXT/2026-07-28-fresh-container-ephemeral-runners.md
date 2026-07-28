# Fresh-container ephemeral runners

- Parse `RUNNER_EPHEMERAL` explicitly and fail invalid values before registration.
- Launch one-job runners as auto-removed containers without a Docker restart
  policy, while preserving clearly labeled persistent mode.
- De-register on completion, crash, and shutdown, and test fresh identity,
  writable-layer marker isolation, restart behavior, and token refresh.
