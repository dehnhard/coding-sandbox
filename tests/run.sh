#!/usr/bin/env bash
# tests/run.sh — Run all tests
set -euo pipefail

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="${THIS_DIR}/.."

echo "=== Shellcheck ==="
if command -v shellcheck &>/dev/null; then
    shellcheck --severity=warning "${REPO_DIR}/coding-sandbox"
    echo "  PASS: shellcheck coding-sandbox"
    shellcheck --severity=warning "${REPO_DIR}/quick-coding-sandbox"
    echo "  PASS: shellcheck quick-coding-sandbox"
    for tool in "${REPO_DIR}"/tools/*; do
        shellcheck --severity=warning "$tool"
        echo "  PASS: shellcheck tools/$(basename "$tool")"
    done
else
    echo "  SKIP: shellcheck not installed"
fi

echo ""
echo "=== Unit Tests (coding-sandbox) ==="
bash "${THIS_DIR}/test-unit.sh"

echo ""
echo "=== Unit Tests (quick-coding-sandbox) ==="
bash "${THIS_DIR}/test-quick-coding-sandbox.sh"

if [[ "${1:-}" == "--integration" ]]; then
    if (( EUID != 0 )); then
        echo ""
        echo "ERROR: Integration tests require root. Run: sudo bash tests/run.sh --integration" >&2
        exit 1
    fi
    echo ""
    echo "=== Integration Tests ==="
    bash "${THIS_DIR}/test-integration.sh"
fi
