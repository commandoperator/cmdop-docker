# Agent commits and GitHub

The demo needs no Git setup. On first startup, the entrypoint creates an
isolated repository for `/workspace/demo`, records a baseline snapshot, and
stores the metadata in the `demo_git` volume. The parent `cmdop-docker`
repository, its `.env`, and its credentials are not exposed through that Git
repository.

`demo/AGENTS.md` is loaded by Cmdop from the project root. It tells the agent to:

1. preserve pre-existing and unrelated changes;
2. run `npm run check` after source changes;
3. stage only files changed for the request;
4. review and validate the staged diff;
5. create a local `agent: ...` commit after successful work;
6. never push unless the user explicitly requests it.

Inspect what the agent sees and what it committed:

```bash
docker compose exec demo cmdop instructions --show-content
docker compose exec demo git status --short
docker compose exec demo git log --oneline --decorate -10
```

This is deliberately a local-first demo. A newcomer can start editing without
creating a GitHub repository, choosing a remote, or providing GitHub access.

## Optional GitHub publishing

Later, attach a dedicated repository without rebuilding the image:

```bash
docker compose exec demo git remote add origin \
  git@github.com:YOUR_ORG/YOUR_SITE.git
docker compose exec demo git remote -v
```

Use a repository-scoped GitHub App credential or deploy key when a push is
actually required. Do not mount a personal `~/.ssh` directory or broad access
token into this live-editing container. Adding `origin` does not change the
policy: the agent pushes only after an explicit request.

For a real site, replace the demo bind mount with that site's checkout while
keeping the same isolation rules. Store runtime secrets outside the checkout.
