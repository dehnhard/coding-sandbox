VERSION := $(shell git describe --tags --always 2>/dev/null | sed 's/^v//' || echo dev)
STAGING := build/staging
DEB_FILE := coding-sandbox_$(VERSION)_all.deb

.PHONY: deb test test-integration clean

deb: clean
	@echo "Building .deb package (version: $(VERSION))..."
	mkdir -p $(STAGING)/DEBIAN
	mkdir -p $(STAGING)/usr/bin
	mkdir -p $(STAGING)/usr/share/coding-sandbox/tools
	mkdir -p $(STAGING)/usr/share/bash-completion/completions

	# Copy scripts
	cp coding-sandbox $(STAGING)/usr/bin/
	cp quick-coding-sandbox $(STAGING)/usr/bin/
	chmod 755 $(STAGING)/usr/bin/coding-sandbox
	chmod 755 $(STAGING)/usr/bin/quick-coding-sandbox

	# Copy tools
	cp tools/* $(STAGING)/usr/share/coding-sandbox/tools/
	chmod 755 $(STAGING)/usr/share/coding-sandbox/tools/*

	# Freeze version (use | delimiter to avoid breakage if VERSION contains /)
	sed -i 's|CODING_SANDBOX_VERSION:-dev|CODING_SANDBOX_VERSION:-$(VERSION)|' $(STAGING)/usr/bin/coding-sandbox
	sed -i 's|CODING_SANDBOX_VERSION:-dev|CODING_SANDBOX_VERSION:-$(VERSION)|' $(STAGING)/usr/bin/quick-coding-sandbox

	# Generate DEBIAN/control (Maintainer before Description per Debian policy)
	printf 'Package: coding-sandbox\nVersion: $(VERSION)\nSection: devel\nPriority: optional\nArchitecture: all\nDepends: incus (>= 5.0) | incus-client (>= 5.0)\nRecommends: distrobuilder, debootstrap\nMaintainer: Daniel Dehnhard <daniel@dehnhard.it>\nDescription: Isolated coding environments with AI tools\n Incus-based sandbox for AI-assisted development with\n Claude Code, OpenCode, and Crush on Debian 13.\n' > $(STAGING)/DEBIAN/control

	# Generate bash completion — coding-sandbox
	printf '_coding_sandbox() {\n    local commands="shell claude opencode crush build start stop destroy rebuild update status doctor version help"\n    local cur="$${COMP_WORDS[COMP_CWORD]}"\n    if (( COMP_CWORD == 1 )); then\n        COMPREPLY=($$(compgen -W "$${commands}" -- "$${cur}"))\n    elif [[ "$${COMP_WORDS[1]}" =~ ^(shell|claude|opencode|crush|build|start|stop|destroy|rebuild|update|status)$$ ]]; then\n        COMPREPLY=($$(compgen -W "--vm" -- "$${cur}"))\n    fi\n}\ncomplete -F _coding_sandbox coding-sandbox\n' > $(STAGING)/usr/share/bash-completion/completions/coding-sandbox

	# Generate bash completion — quick-coding-sandbox
	printf '_quick_coding_sandbox() {\n    local commands="shell setup status version help"\n    local cur="$${COMP_WORDS[COMP_CWORD]}"\n    if (( COMP_CWORD == 1 )); then\n        COMPREPLY=($$(compgen -W "$${commands}" -- "$${cur}"))\n    fi\n}\ncomplete -F _quick_coding_sandbox quick-coding-sandbox\n' > $(STAGING)/usr/share/bash-completion/completions/quick-coding-sandbox

	# Build .deb
	dpkg-deb --root-owner-group --build $(STAGING) $(DEB_FILE)
	@echo "Built: $(DEB_FILE)"

test:
	bash tests/run.sh

test-integration:
	bash tests/run.sh --integration

clean:
	rm -rf build/ coding-sandbox_*.deb
