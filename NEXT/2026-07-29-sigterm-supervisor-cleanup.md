# Verify supervisor cleanup after expected SIGTERM — 2026-07-29

Keep the SIGTERM integration check running through expected supervisor
termination so it can verify child-container cleanup, while rejecting
unexpected supervisor exit statuses (#56).
