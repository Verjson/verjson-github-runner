- Ignore agent-tooling residue (`.claude/worktrees/`, `.tokensave/`, local
  settings, headroom markers, and an uninvited project-level `AGENTS.md`) so it
  can never be committed and never dirties `git status`, matching the org
  convention adopted in Verjson/.github (#82).
