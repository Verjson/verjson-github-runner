# Add `unzip` to the base runner image — 2026-07-28

Add `unzip` to the base runner image so containerized runners satisfy the
portable `ci` toolchain contract (gh, jq, git, curl, bash, tar, unzip, node,
docker) and no longer break actions that extract zip archives, such as
claude-code-action's setup-bun step (#59).
