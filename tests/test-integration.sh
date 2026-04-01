#!/usr/bin/env bash
# tests/test-integration.sh — Integration smoke tests (requires Incus)
#
# Uses isolated names so tests never touch production images/instances.
set -euo pipefail

if (( EUID != 0 )); then
    echo "ERROR: Integration tests require root (build uses debootstrap/chroot)." >&2
    echo "Run: sudo bash tests/run.sh --integration" >&2
    exit 1
fi

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${THIS_DIR}/../coding-sandbox"
PASS=0 FAIL=0

# --- Isolation: override all names to avoid touching real instances ---
export CODING_SANDBOX_VM="cs-test-vm"
export CODING_SANDBOX_IMAGE="cs-test/debian-13"
export CODING_SANDBOX_CONTAINER_IMAGE="cs-test/debian-13/container"
export CODING_SANDBOX_BUILDDIR="$(mktemp -d /tmp/cs-test-build.XXXXXX)"
export CODING_SANDBOX_HOME="$(mktemp -d /tmp/cs-test-home.XXXXXX)"

pass() { ((PASS++)) || true; echo "  PASS: $1"; }
fail() { ((FAIL++)) || true; echo "  FAIL: $1 — $2"; }

_wait_container_ready() {
    local name="$1" elapsed=0
    while (( elapsed < 15 )); do
        incus exec "${name}" -- true &>/dev/null && return 0
        sleep 1
        (( elapsed += 1 ))
    done
}

# Cleanup function — print results, then remove test resources on exit
cleanup_test_resources() {
    echo ""
    echo "=== Integration Results: ${PASS} passed, ${FAIL} failed ==="
    echo "=== Integration: Cleanup ==="
    "$SCRIPT" destroy --yes 2>/dev/null || true
    rm -rf "${CODING_SANDBOX_BUILDDIR}" "${CODING_SANDBOX_HOME}" 2>/dev/null || true
}
trap cleanup_test_resources EXIT

# Ensure clean state from any previous failed run
"$SCRIPT" destroy --yes 2>/dev/null || true

# ── Build ─────────────────────────────────────────────────────────────────────
echo "=== Integration: Build ==="

test_build_creates_artifacts() {
    "$SCRIPT" build
    if [[ -f "${CODING_SANDBOX_BUILDDIR}/container.incus.tar.xz" \
       && -f "${CODING_SANDBOX_BUILDDIR}/container.rootfs.squashfs" \
       && -f "${CODING_SANDBOX_BUILDDIR}/vm.incus.tar.xz" \
       && -f "${CODING_SANDBOX_BUILDDIR}/vm.disk.qcow2" \
       && -f "${CODING_SANDBOX_BUILDDIR}/version" ]]; then
        pass "build creates all artifacts"
    else
        fail "build creates all artifacts" "missing files in ${CODING_SANDBOX_BUILDDIR}"
    fi
}
test_build_creates_artifacts

test_build_dir_permissions() {
    local perms
    perms=$(stat -c '%a' "${CODING_SANDBOX_BUILDDIR}")
    if [[ "$perms" == "750" ]]; then
        pass "build directory has 750 permissions (root:incus)"
    else
        fail "build directory has 750 permissions (root:incus)" "got: $perms"
    fi
}
test_build_dir_permissions

test_build_artifact_permissions() {
    local perms
    perms=$(stat -c '%a' "${CODING_SANDBOX_BUILDDIR}/container.incus.tar.xz")
    if [[ "$perms" == "640" ]]; then
        pass "build artifacts have 640 permissions"
    else
        fail "build artifacts have 640 permissions" "got: $perms"
    fi
}
test_build_artifact_permissions

test_build_skip() {
    local out
    out=$("$SCRIPT" build 2>&1)
    if echo "$out" | grep -q "already exist"; then
        pass "build skips existing artifacts"
    else
        fail "build skips existing artifacts" "no skip warning in output"
    fi
}
test_build_skip

# Import images for subsequent tests (build only creates artifacts)
test_import_images() {
    incus image import \
        "${CODING_SANDBOX_BUILDDIR}/container.incus.tar.xz" \
        "${CODING_SANDBOX_BUILDDIR}/container.rootfs.squashfs" \
        --alias "${CODING_SANDBOX_CONTAINER_IMAGE}" 2>/dev/null || true
    incus image import \
        "${CODING_SANDBOX_BUILDDIR}/vm.incus.tar.xz" \
        "${CODING_SANDBOX_BUILDDIR}/vm.disk.qcow2" \
        --alias "${CODING_SANDBOX_IMAGE}" 2>/dev/null || true
    if incus image show "${CODING_SANDBOX_CONTAINER_IMAGE}" &>/dev/null \
        && incus image show "${CODING_SANDBOX_IMAGE}" &>/dev/null; then
        pass "images imported from artifacts"
    else
        fail "images imported from artifacts" "import failed"
    fi
}
test_import_images

# ── Status ────────────────────────────────────────────────────────────────────
echo "=== Integration: Status ==="

test_status() {
    local out
    out=$("$SCRIPT" status 2>&1)
    # Status should NOT report missing images when they exist
    if echo "$out" | grep -q "(no image"; then
        fail "status shows images" "status reports missing images"
    else
        pass "status shows images"
    fi
}
test_status

# ── Container ─────────────────────────────────────────────────────────────────
echo "=== Integration: Container ==="

test_container_exec() {
    local container_name="cs-test-container-$$"
    incus init "${CODING_SANDBOX_CONTAINER_IMAGE}" "${container_name}" --ephemeral < /dev/null
    incus start "${container_name}"

    _wait_container_ready "${container_name}"

    local out
    out=$(incus exec "${container_name}" -- echo sandbox-test-ok 2>&1) || true
    if echo "$out" | grep -q "sandbox-test-ok"; then
        pass "container exec works"
    else
        fail "container exec works" "output: $out"
    fi

    incus stop "${container_name}" --force 2>/dev/null || true
    sleep 1
    if ! incus info "${container_name}" &>/dev/null; then
        pass "ephemeral container cleaned up on stop"
    else
        fail "ephemeral container cleaned up on stop" "container still exists"
        incus delete "${container_name}" --force 2>/dev/null || true
    fi
}
test_container_exec

test_container_details() {
    # Test DNS fix, timezone sync, and workspace mount by manually replicating
    # what launch_container() does — piping stdin through $SCRIPT shell doesn't
    # work because intermediate incus exec calls consume stdin.
    local container_name="cs-test-details-$$"
    incus init "${CODING_SANDBOX_CONTAINER_IMAGE}" "${container_name}" --ephemeral < /dev/null
    incus config device add "${container_name}" workspace disk \
        source="$PWD" path="/home/sandbox/workspace" shift=true
    incus start "${container_name}"

    _wait_container_ready "${container_name}"

    # Apply DNS fix (same as launch_container)
    incus exec "${container_name}" -- \
        ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf 2>/dev/null || true

    # Apply timezone sync (same as launch_container)
    local host_tz
    host_tz=$(cat /etc/timezone 2>/dev/null) || true
    if [[ -n "$host_tz" ]]; then
        incus exec "${container_name}" -- \
            ln -sf "/usr/share/zoneinfo/${host_tz}" /etc/localtime 2>/dev/null || true
        incus exec "${container_name}" -- \
            bash -c 'printf "%s\n" "$1" > /etc/timezone' _ "${host_tz}" 2>/dev/null || true
    fi

    # DNS: resolv.conf should be symlinked to systemd-resolved stub
    local out
    out=$(incus exec "${container_name}" -- readlink /etc/resolv.conf 2>&1) || true
    if echo "$out" | grep -q "systemd/resolve"; then
        pass "container DNS fix applied"
    else
        fail "container DNS fix applied" "no systemd-resolved symlink found: $out"
    fi

    # Timezone: should match host timezone
    local container_tz
    container_tz=$(incus exec "${container_name}" -- date +%Z 2>&1) || true
    local host_tz_abbr
    host_tz_abbr=$(date +%Z)
    if [[ "$container_tz" == "$host_tz_abbr" ]]; then
        pass "container timezone synced"
    else
        fail "container timezone synced" "expected $host_tz_abbr, got $container_tz"
    fi

    # Workspace: host PWD should be mounted
    out=$(incus exec "${container_name}" -- \
        test -f /home/sandbox/workspace/coding-sandbox 2>&1 && echo "WORKSPACE_OK") || true
    if echo "$out" | grep -q "WORKSPACE_OK"; then
        pass "container workspace mounted"
    else
        fail "container workspace mounted" "coding-sandbox not found in workspace"
    fi

    incus stop "${container_name}" --force 2>/dev/null || true
}
test_container_details

# ── Security ─────────────────────────────────────────────────────────────────
echo "=== Integration: Security ==="

test_ssh_pubkey_only() {
    local container_name="cs-test-ssh-$$"
    incus init "${CODING_SANDBOX_CONTAINER_IMAGE}" "${container_name}" --ephemeral < /dev/null
    incus start "${container_name}"

    _wait_container_ready "${container_name}"

    local out
    out=$(incus exec "${container_name}" -- \
        grep -r "PasswordAuthentication" /etc/ssh/sshd_config.d/ 2>&1) || true
    if echo "$out" | grep -q "PasswordAuthentication no"; then
        pass "SSH pubkey-only authentication"
    else
        fail "SSH pubkey-only authentication" "got: $out"
    fi

    incus stop "${container_name}" --force 2>/dev/null || true
}
test_ssh_pubkey_only

test_account_locked() {
    local container_name="cs-test-account-$$"
    incus init "${CODING_SANDBOX_CONTAINER_IMAGE}" "${container_name}" --ephemeral < /dev/null
    incus start "${container_name}"

    _wait_container_ready "${container_name}"

    local out
    out=$(incus exec "${container_name}" -- passwd -S sandbox 2>&1) || true
    if echo "$out" | grep -q "^sandbox L"; then
        pass "sandbox account is locked"
    else
        fail "sandbox account is locked" "got: $out"
    fi

    incus stop "${container_name}" --force 2>/dev/null || true
}
test_account_locked

test_editor_env() {
    local container_name="cs-test-editor-$$"
    incus init "${CODING_SANDBOX_CONTAINER_IMAGE}" "${container_name}" --ephemeral < /dev/null
    incus start "${container_name}"

    _wait_container_ready "${container_name}"

    local out
    out=$(incus exec "${container_name}" -- \
        su - sandbox -c 'echo $EDITOR' 2>&1) || true
    if [[ "$out" == "nano" ]]; then
        pass "EDITOR=nano set for sandbox user"
    else
        fail "EDITOR=nano set for sandbox user" "got: $out"
    fi

    incus stop "${container_name}" --force 2>/dev/null || true
}
test_editor_env

# ── VM ────────────────────────────────────────────────────────────────────────
echo "=== Integration: VM ==="

test_vm_lifecycle() {
    "$SCRIPT" --vm start
    if incus list --format csv | grep -q "cs-test-vm.*RUNNING"; then
        pass "VM starts"
    else
        fail "VM starts" "VM not running"
    fi

    # Verify timezone was synced by sync_host_settings
    local vm_tz host_tz
    host_tz=$(date +%Z)
    vm_tz=$(incus exec cs-test-vm -- date +%Z 2>/dev/null) || true
    if [[ "$vm_tz" == "$host_tz" ]]; then
        pass "VM timezone synced"
    else
        fail "VM timezone synced" "expected $host_tz, got $vm_tz"
    fi

    "$SCRIPT" --vm stop
    if ! incus list --format csv | grep -q "cs-test-vm.*RUNNING"; then
        pass "VM stops"
    else
        fail "VM stops" "VM still running"
    fi
}
test_vm_lifecycle

# ── Partial build + auto-build dry-run (combined to avoid extra debootstrap) ──
echo "=== Integration: Partial build & auto-build ==="

test_partial_build_and_auto_build() {
    # Delete only the container image, keep VM image
    incus image delete "${CODING_SANDBOX_CONTAINER_IMAGE}" 2>/dev/null || true

    # dry-run should report auto_build=true when container image is missing
    local out
    out=$("$SCRIPT" shell --dry-run 2>&1)
    if echo "$out" | grep -q "auto_build=true"; then
        pass "dry-run detects missing container image"
    else
        fail "dry-run detects missing container image" "got: $out"
    fi

    # VM mode should still report auto_build=false (VM image exists)
    out=$("$SCRIPT" --vm shell --dry-run 2>&1)
    if echo "$out" | grep -q "auto_build=false"; then
        pass "dry-run: VM image still present"
    else
        fail "dry-run: VM image still present" "got: $out"
    fi

    # Re-import the missing container image from existing artifacts
    incus image import \
        "${CODING_SANDBOX_BUILDDIR}/container.incus.tar.xz" \
        "${CODING_SANDBOX_BUILDDIR}/container.rootfs.squashfs" \
        --alias "${CODING_SANDBOX_CONTAINER_IMAGE}" 2>/dev/null || true
    if incus image show "${CODING_SANDBOX_CONTAINER_IMAGE}" &>/dev/null; then
        pass "re-import container image from existing artifacts"
    else
        fail "re-import container image from existing artifacts" "import failed"
    fi
}
test_partial_build_and_auto_build

# ── Destroy ───────────────────────────────────────────────────────────────────
echo "=== Integration: Destroy ==="

test_destroy() {
    "$SCRIPT" destroy --yes || true
    local images
    images=$(incus image list --format csv | grep -c "cs-test" || true)
    if (( images == 0 )); then
        pass "destroy removes all images"
    else
        fail "destroy removes all images" "${images} images remain"
    fi
}
test_destroy

test_destroy_idempotent() {
    local out
    out=$("$SCRIPT" destroy --yes 2>&1)
    # Should warn gracefully with "not found", not crash
    if echo "$out" | grep -q "not found"; then
        pass "destroy is idempotent"
    else
        fail "destroy is idempotent" "unexpected output: $out"
    fi
}
test_destroy_idempotent

# Results are printed by cleanup_test_resources trap
(( FAIL == 0 ))
