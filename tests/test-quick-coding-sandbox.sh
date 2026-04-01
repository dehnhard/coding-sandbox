#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

die() { echo "ERROR: $*" >&2; exit 1; }

# Test 1: Help output
output=$(./quick-coding-sandbox help)
echo "$output" | grep -q "quick-coding-sandbox" || die "Help missing title"

# Test 2: Status output
output=$(./quick-coding-sandbox status)
echo "$output" | grep -q "Quick Coding Sandbox" || die "Status missing title"
echo "$output" | grep -q "Config:" || die "Status missing config"
echo "$output" | grep -q "Tools:" || die "Status missing tools"

# Test 3: Unknown command
output=$(./quick-coding-sandbox nonexistent 2>&1) || true
echo "$output" | grep -q "Unknown command:" || die "Should reject unknown command"

# Test 4: useradd uses --no-create-home
SCRIPT="./quick-coding-sandbox"
out=$(grep -c '\-\-no-create-home' "${SCRIPT}") || true
if [[ "$out" -ge 1 ]]; then
    echo "PASS: useradd uses --no-create-home"
else
    echo "FAIL: useradd should use --no-create-home"; exit 1
fi

# Test 5: setup does not use read -n 1
SCRIPT="./quick-coding-sandbox"
out=$(grep -c 'read.*-n 1' "${SCRIPT}") || true
if [[ "$out" -eq 0 ]]; then
    echo "PASS: setup does not use read -n 1"
else
    echo "FAIL: setup should not use read -n 1"; exit 1
fi

# Test 6: setup calls version-check for installed tools
if grep -q 'version-check' "${SCRIPT}"; then
    echo "PASS: setup uses version-check"
else
    echo "FAIL: setup should call version-check"; exit 1
fi

# Test 7: version cache file is written
if grep -q 'version-cache' "${SCRIPT}"; then
    echo "PASS: setup writes version cache"
else
    echo "FAIL: setup should write version-cache"; exit 1
fi

# Test 8: welcome banner reads version cache
if grep -q 'version-cache' "${SCRIPT}" && grep -q 'cached_versions' "${SCRIPT}"; then
    echo "PASS: banner uses version cache"
else
    echo "FAIL: banner should read version-cache for display"; exit 1
fi

echo "All tests passed!"
