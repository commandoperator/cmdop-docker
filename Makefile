.PHONY: help commit claude codex

help:
	@echo "Available commands:"
	@echo "  make commit - stage, AI commit, and push to main"
	@echo "  make claude - start Claude Code with permissions bypassed"
	@echo "  make codex  - start Codex with approvals and sandbox bypassed"

commit:
	@git add . && orc commit -y && git push origin main

claude:
	@claude --dangerously-skip-permissions --chrome

codex:
	@codex --dangerously-bypass-approvals-and-sandbox
