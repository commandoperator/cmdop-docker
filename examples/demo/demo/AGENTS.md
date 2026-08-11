# Live site repository

This directory is an isolated Git repository for a live site managed through
Cmdop.

When changing the site:

1. Inspect `git status --short` before editing and preserve unrelated changes.
2. Make only the requested change.
3. Run `npm run check` after changing source or configuration files.
4. Stage only files changed for the request. Never use a broad staging command
   when unrelated changes are present.
5. Run `git diff --cached --check` and review the staged diff.
6. After successful checks, create a local commit named
   `agent: <short description>` and report its hash.

Never commit `.env`, credentials, private keys, generated dependencies, or
build output. Never push, force-push, rewrite history, or change remotes unless
the user explicitly asks for that exact operation. If a check fails, leave the
change uncommitted and explain the failure.
