# Key the image build check concurrency group on the event — 2026-07-29

`.github/workflows/image-build-check.yml` grouped its concurrent runs by `github.ref`
only. Pull requests each have their own ref, but `schedule` and `workflow_dispatch` both
report `refs/heads/main`, so an on-demand arm64 build and the weekly cron shared one group
and `cancel-in-progress` let either kill the other — exactly when someone triggers a manual
run because they want an arm64 answer now. The group now includes `github.event_name`, so
each trigger cancels only its own kind. Fixes #90.
