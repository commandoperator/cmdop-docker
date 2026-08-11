.PHONY: help setup claude codex claude-login codex-login agents-status

# Which Compose service the agent targets below run in.
SERVICE ?= demo

help:
	@echo "Available commands:"
	@echo "  make setup        - create .env from .env.example"
	@echo "  make claude       - start Claude Code with permissions bypassed"
	@echo "  make codex        - start Codex with approvals and sandbox bypassed"
	@echo ""
	@echo "Inside the container:"
	@echo "  make claude-login  - sign in to Claude Code"
	@echo "  make codex-login   - sign in to Codex"
	@echo "  make agents-status - report both CLIs' version and sign-in state"

# Create .env from the example, never overwriting one that already exists.
setup:
	@if [ -f .env ]; then echo "keep    .env (already there)"; \
	else cp .env.example .env; echo "created .env"; fi
	@echo ""
	@echo "Now set CMDOP_ADMIN_PASSWORD (and CMDOP_API_KEY for public mode) in .env"


claude:
	@claude --dangerously-skip-permissions --chrome

codex:
	@codex --dangerously-bypass-approvals-and-sandbox

# Both flows print a URL and wait for a code, which is exactly what you want
# with no browser in the container: sign in on your own machine, paste the code
# back. The token is written to ./agents on the host, so it outlives the image.
claude-login:
	@docker compose exec $(SERVICE) claude auth login

codex-login:
	@docker compose exec $(SERVICE) codex login --device-auth

agents-status:
	@docker compose exec $(SERVICE) sh -lc '\
		claude --version; claude auth status --text || true; \
		codex --version; codex login status || true'
