.PHONY: help commit claude codex

help:
	@echo "Available commands:"
	@echo "  make commit - stage, AI commit, and push to main"
	@echo "  make claude - start Claude Code with permissions bypassed"
	@echo "  make codex  - start Codex with approvals and sandbox bypassed"

commit:
	@g=$$(git rev-parse --git-dir) || exit 1; \
	if [ -d "$$g/rebase-merge" ] || [ -d "$$g/rebase-apply" ]; then echo "x rebase in progress - resolve, then: git rebase --continue   (abort: git rebase --abort)"; exit 1; fi; \
	if [ -f "$$g/MERGE_HEAD" ]; then echo "x merge in progress - resolve, then: git merge --continue   (abort: git merge --abort)"; exit 1; fi; \
	if [ -f "$$g/CHERRY_PICK_HEAD" ]; then echo "x cherry-pick in progress - resolve, then: git cherry-pick --continue   (abort: git cherry-pick --abort)"; exit 1; fi; \
	if [ -f "$$g/REVERT_HEAD" ]; then echo "x revert in progress - resolve, then: git revert --continue   (abort: git revert --abort)"; exit 1; fi; \
	if [ -n "$$(git ls-files --unmerged)" ]; then echo "x unresolved conflicts:"; git diff --name-only --diff-filter=U | sed 's/^/    /'; echo "  resolve them, then: git add <file>"; exit 1; fi; \
	branch=$$(git symbolic-ref --quiet --short HEAD) || { echo "x detached HEAD at $$(git rev-parse --short HEAD) - commits made here get orphaned"; echo "  keep this work: git switch -c <branch>   |   discard it: git switch main"; exit 1; }; \
	[ "$$branch" = "main" ] || { echo "x on branch '$$branch', not main - push it explicitly yourself"; exit 1; }; \
	git add . ; \
	if ! git diff --cached --quiet; then orc commit -y || exit 1; fi ; \
	git fetch -q origin main ; \
	git merge-base --is-ancestor origin/main HEAD || git rebase origin/main || { echo "x rebase conflicts - resolve them, then: git push origin main"; exit 1; } ; \
	git push origin main

claude:
	@claude --dangerously-skip-permissions --chrome

codex:
	@codex --dangerously-bypass-approvals-and-sandbox
