.PHONY: help install setup shortcuts verify test update

help: ## show available targets
	@grep -E '^[a-z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

install: setup shortcuts ## first-time setup on a node: syncthing config + session shortcuts

setup: ## configure syncthing shared folder + device pairing (interactive)
	./setup.sh

shortcuts: ## install cr/cs shell shortcuts + lock library + .stignore
	./install-aliases.sh

verify: ## run the 10-dimension health check against this node
	./verify.sh

test: ## run offline test suite (no syncthing daemon needed)
	bash tests/run.sh

update: ## pull latest and refresh installed shortcuts/lib/stignore
	git pull --ff-only
	./install-aliases.sh
