#!/usr/bin/env bash
# tests/test-unit.sh — Unit tests for coding-sandbox
set -euo pipefail

PASS=0 FAIL=0
THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${THIS_DIR}/../coding-sandbox"

pass() { ((PASS++)) || true; echo "  PASS: $1"; }
fail() { ((FAIL++)) || true; echo "  FAIL: $1 — $2"; }

echo "=== Argument Parsing ==="

test_default_args() {
    local out
    out=$("$SCRIPT" --dry-run 2>&1) || true
    if echo "$out" | grep -q 'cmd=shell mode=container'; then
        pass "no args → shell + container"
    else
        fail "no args → shell + container" "got: $out"
    fi
}

test_vm_flag() {
    local out
    out=$("$SCRIPT" --vm --dry-run 2>&1) || true
    if echo "$out" | grep -q 'cmd=shell mode=vm'; then
        pass "--vm → shell + vm"
    else
        fail "--vm → shell + vm" "got: $out"
    fi
}

test_vm_flag_after_cmd() {
    local out
    out=$("$SCRIPT" shell --vm --dry-run 2>&1) || true
    if echo "$out" | grep -q 'cmd=shell mode=vm'; then
        pass "shell --vm → shell + vm"
    else
        fail "shell --vm → shell + vm" "got: $out"
    fi
}

test_start_implies_vm() {
    local out
    out=$("$SCRIPT" start --dry-run 2>&1) || true
    if echo "$out" | grep -q 'cmd=start mode=vm'; then
        pass "start → vm mode"
    else
        fail "start → vm mode" "got: $out"
    fi
}

test_stop_implies_vm() {
    local out
    out=$("$SCRIPT" stop --dry-run 2>&1) || true
    if echo "$out" | grep -q 'cmd=stop mode=vm'; then
        pass "stop → vm mode"
    else
        fail "stop → vm mode" "got: $out"
    fi
}

test_unknown_option() {
    local out
    out=$("$SCRIPT" --foo 2>&1) && false || true
    if echo "$out" | grep -q 'Unknown option'; then
        pass "unknown option rejected"
    else
        fail "unknown option rejected" "got: $out"
    fi
}

test_extra_positional() {
    local out
    out=$("$SCRIPT" shell extra 2>&1) && false || true
    if echo "$out" | grep -q 'Unexpected argument'; then
        pass "extra positional rejected"
    else
        fail "extra positional rejected" "got: $out"
    fi
}

test_unknown_command() {
    local out
    out=$("$SCRIPT" foobar --dry-run 2>&1) && false || true
    if echo "$out" | grep -q 'Unknown command'; then
        pass "unknown command rejected"
    else
        fail "unknown command rejected" "got: $out"
    fi
}

test_help_flag() {
    local out
    out=$("$SCRIPT" -h --dry-run 2>&1) || true
    if echo "$out" | grep -q 'cmd=help'; then
        pass "-h → help"
    else
        fail "-h → help" "got: $out"
    fi
}

test_default_args
test_vm_flag
test_vm_flag_after_cmd
test_start_implies_vm
test_stop_implies_vm
test_unknown_option
test_extra_positional
test_unknown_command
test_help_flag

echo ""
echo "=== container_name_for_dir ==="

eval "$(sed -n '/^CONTAINER_PREFIX=/p' "$SCRIPT")"
eval "$(sed -n '/^_DIR_SLUG_CACHE=/p' "$SCRIPT")"
eval "$(sed -n '/^_dir_slug()/,/^}$/p' "$SCRIPT")"
eval "$(sed -n '/^container_name_for_dir()/,/^}/p' "$SCRIPT")"
eval "$(sed -n '/^mount_path_for_dir()/,/^}/p' "$SCRIPT")"

test_deterministic_name_format() {
    local name
    name=$(container_name_for_dir)
    if [[ "$name" =~ ^cs-[a-z0-9-]+-[0-9a-f]{6}$ ]]; then
        pass "deterministic name format matches cs-<slug>-<hex6>"
    else
        fail "deterministic name format" "got: $name"
    fi
}

test_deterministic_name_stable() {
    local name1 name2
    name1=$(container_name_for_dir)
    name2=$(container_name_for_dir)
    if [[ "$name1" == "$name2" ]]; then
        pass "same dir produces same name"
    else
        fail "same dir produces same name" "got: $name1 vs $name2"
    fi
}

test_deterministic_name_different_dirs() {
    local name1 name2
    name1=$(cd /tmp && _DIR_SLUG_CACHE="" && container_name_for_dir)
    name2=$(cd /var && _DIR_SLUG_CACHE="" && container_name_for_dir)
    if [[ "$name1" != "$name2" ]]; then
        pass "different dirs produce different names"
    else
        fail "different dirs produce different names" "both: $name1"
    fi
}

test_deterministic_name_format
test_deterministic_name_stable
test_deterministic_name_different_dirs

echo ""
echo "=== mount_path_for_dir ==="

eval "$(sed -n '/^SHELL_USER=/p' "$SCRIPT")"
eval "$(sed -n '/^CONTAINER_HOME=/p' "$SCRIPT")"

test_mount_path_format() {
    local mpath
    mpath=$(mount_path_for_dir)
    if [[ "$mpath" =~ ^/home/sandbox/[a-z0-9-]+-[0-9a-f]{6}$ ]]; then
        pass "mount path format matches /home/sandbox/<slug>-<hex6>"
    else
        fail "mount path format — got: $mpath"
    fi
}

test_mount_path_matches_container_name() {
    local mpath cname
    mpath=$(mount_path_for_dir)
    cname=$(container_name_for_dir)
    local slug="${cname#cs-}"
    if [[ "$mpath" == "${CONTAINER_HOME}/${slug}" ]]; then
        pass "mount path slug matches container name slug"
    else
        fail "mount path slug matches container name slug — path: $mpath, name: $cname"
    fi
}

test_mount_path_format
test_mount_path_matches_container_name

echo ""
echo "=== Help Text ==="

test_help_no_errors() {
    local out rc=0
    out=$("$SCRIPT" help 2>&1) || rc=$?
    if (( rc == 0 )) && [[ -n "$out" ]]; then
        pass "help renders without errors"
    else
        fail "help renders without errors" "exit=$rc"
    fi
}

test_help_no_errors

test_help_lists_commands() {
    local out
    out=$("$SCRIPT" help 2>&1)
    if echo "$out" | grep -q "shell" \
        && echo "$out" | grep -q "build" \
        && echo "$out" | grep -q "destroy"; then
        pass "help lists all commands"
    else
        fail "help lists all commands" "missing commands in help output"
    fi
}

test_help_lists_env_vars() {
    local out
    out=$("$SCRIPT" help 2>&1)
    if echo "$out" | grep -q "CODING_SANDBOX_VM" \
        && echo "$out" | grep -q "CODING_SANDBOX_IMAGE"; then
        pass "help lists environment variables"
    else
        fail "help lists environment variables" "missing env vars in help output"
    fi
}

test_help_lists_commands
test_help_lists_env_vars

echo ""
echo "=== Version ==="

test_version_command() {
    local out
    out=$("$SCRIPT" version 2>&1) || true
    if [[ -n "$out" ]] && [[ "$out" != *"Unknown"* ]]; then
        pass "version command produces output"
    else
        fail "version command" "got: $out"
    fi
}

test_version_flag() {
    local out
    out=$("$SCRIPT" --version 2>&1) || true
    if [[ -n "$out" ]] && [[ "$out" != *"Unknown"* ]]; then
        pass "--version flag produces output"
    else
        fail "--version flag" "got: $out"
    fi
}

test_version_command
test_version_flag

echo ""
echo "=== Purge Flag ==="

test_purge_flag() {
    local out
    out=$("$SCRIPT" destroy --purge --dry-run 2>&1) || true
    if echo "$out" | grep -q 'cmd=destroy' && echo "$out" | grep -q 'purge=true'; then
        pass "--purge with destroy"
    else
        fail "--purge with destroy" "got: $out"
    fi
}

test_purge_invalid() {
    local out
    out=$("$SCRIPT" shell --purge --dry-run 2>&1) && false || true
    if echo "$out" | grep -qi 'purge.*only.*destroy\|only valid'; then
        pass "--purge rejected without destroy"
    else
        fail "--purge rejected without destroy" "got: $out"
    fi
}

test_purge_with_rebuild() {
    local out
    out=$("$SCRIPT" rebuild --purge --dry-run 2>&1) || true
    if echo "$out" | grep -q 'cmd=rebuild' && echo "$out" | grep -q 'purge=true'; then
        pass "--purge with rebuild"
    else
        fail "--purge with rebuild" "got: $out"
    fi
}

test_purge_flag
test_purge_with_rebuild
test_purge_invalid

echo ""
echo "=== check_deps ==="

test_missing_incus() {
    # In environments without incus (like the sandbox container), verify detection
    if command -v incus &>/dev/null; then
        echo "  SKIP: incus available, cannot test missing incus"
        return
    fi
    local out
    out=$("$SCRIPT" build 2>&1 || true)
    if echo "$out" | grep -q "incus not found"; then
        pass "missing incus detected"
    else
        fail "missing incus detected" "got: $out"
    fi
}

test_missing_incus

echo ""
echo "=== Architecture ==="

test_arch_variable() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  local expected_deb="amd64" ;;
        aarch64) local expected_deb="arm64" ;;
    esac
    if [[ -n "${expected_deb:-}" ]]; then
        pass "known architecture: $arch → $expected_deb"
    else
        pass "unknown architecture: $arch (will use dpkg fallback)"
    fi
}

test_arch_variable

echo ""
echo "=== Tool Selection ==="

test_tools_in_dryrun() {
    local out
    out=$(CODING_SANDBOX_TOOLS="claude-code" "$SCRIPT" build --dry-run 2>&1) || true
    if echo "$out" | grep -q 'tools=claude-code'; then
        pass "CODING_SANDBOX_TOOLS shown in build dry-run"
    else
        fail "CODING_SANDBOX_TOOLS" "got: $out"
    fi
}

test_tools_in_dryrun

echo ""
echo "=== Port Validation ==="

# Source validate_ports from the script
eval "$(sed -n '/^validate_ports()/,/^}/p' "$SCRIPT")"

test_valid_ports() {
    local rc=0
    validate_ports "8080 3000" || rc=$?
    if (( rc == 0 )); then
        pass "valid ports accepted"
    else
        fail "valid ports accepted" "exit=$rc"
    fi
}

test_invalid_port_text() {
    local rc=0
    (validate_ports "abc") 2>/dev/null || rc=$?
    if (( rc != 0 )); then
        pass "non-numeric port rejected"
    else
        fail "non-numeric port rejected" "should have failed"
    fi
}

test_invalid_port_range() {
    local rc=0
    (validate_ports "99999") 2>/dev/null || rc=$?
    if (( rc != 0 )); then
        pass "out-of-range port rejected"
    else
        fail "out-of-range port rejected" "should have failed"
    fi
}

test_empty_ports() {
    local rc=0
    validate_ports "" || rc=$?
    if (( rc == 0 )); then
        pass "empty ports accepted (no-op)"
    else
        fail "empty ports accepted" "exit=$rc"
    fi
}

test_valid_ports
test_invalid_port_text
test_invalid_port_range
test_empty_ports

echo ""
echo "=== Doctor ==="

test_doctor_dryrun() {
    local out
    out=$("$SCRIPT" doctor --dry-run 2>&1) || true
    if echo "$out" | grep -q 'cmd=doctor'; then
        pass "doctor command accepted in dry-run"
    else
        fail "doctor command accepted in dry-run" "got: $out"
    fi
}

test_doctor_output_sections() {
    local out
    out=$("$SCRIPT" doctor 2>&1) || true
    if echo "$out" | grep -q '=== System ===' \
        && echo "$out" | grep -q '=== Dependencies ===' \
        && echo "$out" | grep -q '=== Summary ==='; then
        pass "doctor shows all sections"
    else
        fail "doctor shows all sections" "missing section headers"
    fi
}

test_doctor_dryrun
test_doctor_output_sections

echo ""
echo "=== init_host_home ==="

# Source init_host_home and its dependencies from the script
_REAL_HOME="${HOME}"
eval "$(sed -n '/^HOST_HOME=/p' "$SCRIPT")"
eval "$(sed -n '/^RED=/p;/^CYAN=/p' "$SCRIPT")"
eval "$(grep -E '^(info|die)\(\)' "$SCRIPT")"
eval "$(sed -n '/^init_host_home()/,/^}/p' "$SCRIPT")"

test_host_home_permissions() {
    local tmpdir
    tmpdir=$(mktemp -d)
    rm -rf "$tmpdir"  # init_host_home creates it
    HOST_HOME="$tmpdir" init_host_home
    local perms
    perms=$(stat -c '%a' "$tmpdir")
    if [[ "$perms" == "700" ]]; then
        pass "init_host_home sets 700 permissions"
    else
        fail "init_host_home sets 700 permissions" "got: $perms"
    fi
    rm -rf "$tmpdir"
}

test_host_home_permissions

echo ""
echo "=== Tool Scripts ==="

test_tool_info_output() {
    local tool="$1"
    local script="${THIS_DIR}/../tools/${tool}"
    local out
    out=$(bash "$script" 2>&1)
    local rc=$?

    if (( rc != 0 )); then
        fail "tools/${tool} info exits 0" "exit=$rc"
        return
    fi

    # First line: "<name> — <description>"
    local first_line
    first_line=$(echo "$out" | head -1)
    if [[ "$first_line" == *" — "* ]]; then
        pass "tools/${tool} info format"
    else
        fail "tools/${tool} info format" "got: $first_line"
    fi

    # Second line: "Usage: ..."
    local second_line
    second_line=$(echo "$out" | sed -n '2p')
    if [[ "$second_line" == Usage:* ]]; then
        pass "tools/${tool} usage line"
    else
        fail "tools/${tool} usage line" "got: $second_line"
    fi
}

test_tool_info_output claude-code
test_tool_info_output opencode
test_tool_info_output crush
test_tool_info_output qwen-code

echo ""
echo "=== Tool version-check Interface ==="

test_tool_version_check() {
    local tool="$1"
    local script="${THIS_DIR}/../tools/${tool}"

    # Script must handle "version-check" as second argument
    if grep -q 'version-check' "$script"; then
        pass "tools/${tool} handles version-check"
    else
        fail "tools/${tool} handles version-check" "no version-check handling"
    fi

    # Output must use key=value format
    if grep -q 'installed=' "$script" && grep -q 'latest=' "$script"; then
        pass "tools/${tool} version-check output format"
    else
        fail "tools/${tool} version-check output format" "missing installed=/latest= output"
    fi
}

test_tool_version_check claude-code
test_tool_version_check crush
test_tool_version_check opencode
test_tool_version_check qwen-code

echo ""
echo "=== Architecture Handling ==="

test_tool_arch_die() {
    local tool="$1"
    local script="${THIS_DIR}/../tools/${tool}"
    # Tool must exit 1 on unsupported arch, not just warn
    if grep -q 'exit 1' "$script" && grep -q 'uname -m' "$script"; then
        pass "tools/${tool} dies on unsupported architecture"
    else
        fail "tools/${tool} dies on unsupported architecture" "must die, not warn"
    fi
}

test_tool_arch_die claude-code
test_tool_arch_die crush
test_tool_arch_die opencode

test_qwen_arm64_support() {
    local script="${THIS_DIR}/../tools/qwen-code"
    if grep -q 'aarch64\|arm64' "$script"; then
        pass "tools/qwen-code supports arm64"
    else
        fail "tools/qwen-code supports arm64" "no arm64/aarch64 handling"
    fi
}
test_qwen_arm64_support

echo ""
echo "=== Build/Import Separation ==="

test_no_incus_wrapper() {
    if grep -q '^_incus()' "$SCRIPT"; then
        fail "no _incus wrapper" "_incus() function still exists"
    elif grep -q '_incus ' "$SCRIPT"; then
        fail "no _incus calls" "_incus calls still exist"
    else
        pass "no _incus wrapper or calls"
    fi
}

test_no_incus_wrapper

test_no_incus_import_in_build() {
    local build_body
    build_body=$(sed -n '/^cmd_build()/,/^cmd_create_vm()/p' "$SCRIPT")
    if echo "$build_body" | grep -q 'incus image import'; then
        fail "no incus import in build" "cmd_build still calls incus image import"
    else
        pass "no incus import in build"
    fi
}

test_build_renames_artifacts() {
    local build_body
    build_body=$(sed -n '/^cmd_build()/,/^cmd_create_vm()/p' "$SCRIPT")
    if echo "$build_body" | grep -q 'container\.incus\.tar\.xz' \
        && echo "$build_body" | grep -q 'container\.rootfs\.squashfs' \
        && echo "$build_body" | grep -q 'vm\.incus\.tar\.xz' \
        && echo "$build_body" | grep -q 'vm\.disk\.qcow2'; then
        pass "build uses new artifact names"
    else
        fail "build uses new artifact names" "missing artifact renames"
    fi
}

test_build_writes_version_file() {
    local build_body
    build_body=$(sed -n '/^cmd_build()/,/^cmd_create_vm()/p' "$SCRIPT")
    if echo "$build_body" | grep -q '"${BUILD_DIR}/version"'; then
        pass "build writes version file"
    else
        fail "build writes version file" "no version file write in cmd_build"
    fi
}

test_no_incus_import_in_build
test_build_renames_artifacts
test_build_writes_version_file

test_ensure_functions_exist() {
    if grep -q 'image_artifacts_exist()' "$SCRIPT" \
        && grep -q 'vm_artifacts_exist()' "$SCRIPT" \
        && grep -q 'ensure_container_image()' "$SCRIPT" \
        && grep -q 'ensure_vm_image()' "$SCRIPT"; then
        pass "ensure functions defined"
    else
        fail "ensure functions defined" "missing ensure_*_image or *_artifacts_exist"
    fi
}

test_run_as_user_helper_exists() {
    if grep -q '^_run_as_user()' "$SCRIPT"; then
        pass "_run_as_user helper defined"
    else
        fail "_run_as_user helper defined" "missing _run_as_user function"
    fi
}

test_ensure_uses_run_as_user() {
    local ensure_body
    ensure_body=$(sed -n '/^ensure_container_image()/,/^}/p' "$SCRIPT")
    if echo "$ensure_body" | grep -q '_run_as_user'; then
        pass "ensure_container_image uses _run_as_user"
    else
        fail "ensure_container_image uses _run_as_user" "no _run_as_user call"
    fi
}

test_ensure_vm_uses_run_as_user() {
    local ensure_body
    ensure_body=$(sed -n '/^ensure_vm_image()/,/^}/p' "$SCRIPT")
    if echo "$ensure_body" | grep -q '_run_as_user'; then
        pass "ensure_vm_image uses _run_as_user"
    else
        fail "ensure_vm_image uses _run_as_user" "no _run_as_user call"
    fi
}

test_ensure_functions_exist
test_run_as_user_helper_exists
test_ensure_uses_run_as_user
test_ensure_vm_uses_run_as_user

test_shell_calls_ensure() {
    local shell_body
    shell_body=$(sed -n '/^cmd_shell()/,/^}/p' "$SCRIPT")
    if echo "$shell_body" | grep -q 'ensure_container_image\|ensure_vm_image'; then
        pass "cmd_shell calls ensure functions"
    else
        fail "cmd_shell calls ensure functions" "no ensure call in cmd_shell"
    fi
}

test_shell_calls_ensure

test_no_tool_shortcuts_in_dispatch() {
    local out
    out=$(grep -c "cmd_tool" "$SCRIPT") || true
    if [[ "$out" -eq 0 ]]; then
        pass "no cmd_tool dispatch (tool shortcuts removed)"
    else
        fail "no cmd_tool dispatch (tool shortcuts removed)" "found $out occurrences"
    fi
}
test_no_tool_shortcuts_in_dispatch

test_help_has_vm_section() {
    if "$SCRIPT" help 2>&1 | grep -q 'Commands only for VM'; then
        pass "help shows VM-only section"
    else
        fail "help shows VM-only section" "section not found"
    fi
}
test_help_has_vm_section

test_rebuild_calls_ensure() {
    local rebuild_body
    rebuild_body=$(sed -n '/^cmd_rebuild()/,/^}/p' "$SCRIPT")
    if echo "$rebuild_body" | grep -q 'ensure_container_image' \
        && echo "$rebuild_body" | grep -q 'ensure_vm_image'; then
        pass "cmd_rebuild calls ensure functions"
    else
        fail "cmd_rebuild calls ensure functions" "missing ensure calls"
    fi
}

test_rebuild_calls_ensure

test_rebuild_requires_root() {
    local rebuild_body
    rebuild_body=$(sed -n '/^cmd_rebuild()/,/^}/p' "$SCRIPT")
    if echo "$rebuild_body" | grep -q 'id -u.*-ne 0\|EUID.*-ne 0'; then
        pass "cmd_rebuild requires root"
    else
        fail "cmd_rebuild requires root" "no root check found"
    fi
}
test_rebuild_requires_root

test_doctor_shows_artifacts_section() {
    local out
    out=$("$SCRIPT" doctor 2>&1) || true
    if echo "$out" | grep -q 'Build Artifacts\|Artifacts'; then
        pass "doctor shows artifacts section"
    else
        fail "doctor shows artifacts section" "no artifacts section in doctor output"
    fi
}

test_doctor_shows_artifacts_section

test_destroy_does_not_delete_artifacts() {
    local destroy_body
    destroy_body=$(sed -n '/^cmd_destroy()/,/^}/p' "$SCRIPT")
    if echo "$destroy_body" | grep -q '_purge' \
        && echo "$destroy_body" | grep -q 'BUILD_DIR'; then
        pass "destroy only purges artifacts with --purge"
    else
        fail "destroy only purges artifacts with --purge" "missing _purge guard or BUILD_DIR reference"
    fi
}

test_destroy_does_not_delete_artifacts

echo ""
echo "=== Container Fallback ==="

test_fallback_recreates_container() {
    local launch_body
    launch_body=$(sed -n '/^launch_container()/,/^[a-z_]*() {/p' "$SCRIPT")
    # Fallback must delete before re-init (not modify in place)
    if echo "$launch_body" | grep -q 'incus delete.*force' \
        && echo "$launch_body" | grep -A5 'incus delete.*force' | grep -q 'incus init'; then
        pass "fallback deletes then recreates container"
    else
        fail "fallback deletes then recreates container" "expected delete + init pattern"
    fi
}

test_fallback_no_device_set() {
    # The fallback block (after incus delete --force) must not use 'device set' — it should
    # recreate the container from scratch. (Root-user path before start may use 'device set'.)
    local launch_body fallback_body
    launch_body=$(sed -n '/^launch_container()/,/^[a-z_]*() {/p' "$SCRIPT")
    fallback_body=$(echo "$launch_body" | sed -n '/incus delete --force/,$p')
    if echo "$fallback_body" | grep -q 'incus config device set'; then
        fail "no device set in fallback" "found 'incus config device set' in fallback — should recreate instead"
    else
        pass "no device set in fallback"
    fi
}

test_fallback_recreates_container
test_fallback_no_device_set

echo ""
echo "=== Update Command ==="

test_update_rejects_container_mode() {
    # Verify container update code is gone AND die guard is present
    local update_body
    update_body=$(sed -n '/^cmd_update()/,/^[a-z_]*() {/p' "$SCRIPT")
    if echo "$update_body" | grep -q 'ephemeral\|cs-update'; then
        fail "update rejects container mode" "container update code still present"
    elif ! echo "$update_body" | grep -q 'die.*VM'; then
        fail "update rejects container mode" "missing die guard for non-VM mode"
    else
        pass "update rejects container mode"
    fi
}

test_update_rejects_container_mode

echo ""
echo "=== Dynamic Tool Discovery ==="

test_dynamic_tool_default() {
    # When CODING_SANDBOX_TOOLS is unset, build --dry-run should show discovered tools
    local out
    out=$(CODING_SANDBOX_TOOLS="" "$SCRIPT" build --dry-run 2>&1) || true
    # Should list tools found in tools/ directory
    if echo "$out" | grep -q 'claude-code' && echo "$out" | grep -q 'opencode'; then
        pass "dynamic tool discovery finds tools"
    else
        fail "dynamic tool discovery finds tools" "got: $out"
    fi
}

test_no_hardcoded_tool_default() {
    # The CODING_SANDBOX_TOOLS line should NOT have a hardcoded default list
    if grep -q 'CODING_SANDBOX_TOOLS=.*claude-code opencode crush' "$SCRIPT"; then
        fail "no hardcoded tool default" "found hardcoded tool list"
    else
        pass "no hardcoded tool default"
    fi
}

test_dynamic_tool_default
test_no_hardcoded_tool_default

echo ""
echo "=== Pre-flight Checks ==="

test_kvm_check_in_check_deps() {
    local deps_body
    deps_body=$(sed -n '/^check_deps()/,/^}/p' "$SCRIPT")
    if echo "$deps_body" | grep -q '/dev/kvm'; then
        pass "check_deps checks /dev/kvm for VM mode"
    else
        fail "check_deps checks /dev/kvm for VM mode" "no /dev/kvm check"
    fi
}

test_pwd_fs_check_in_launch_container() {
    local launch_body
    launch_body=$(sed -n '/^launch_container()/,/^[a-z_]*() {/p' "$SCRIPT")
    if echo "$launch_body" | grep -q 'stat -f'; then
        pass "launch_container checks PWD filesystem type"
    else
        fail "launch_container checks PWD filesystem type" "no stat -f check"
    fi
}

test_pwd_fs_check_in_quick_sandbox() {
    local qscript="${THIS_DIR}/../quick-coding-sandbox"
    local shell_body
    shell_body=$(sed -n '/^cmd_shell()/,/^[a-z_]*() {/p' "$qscript")
    if echo "$shell_body" | grep -q 'stat -f'; then
        pass "quick-sandbox cmd_shell checks PWD filesystem type"
    else
        fail "quick-sandbox cmd_shell checks PWD filesystem type" "no stat -f check"
    fi
}

test_kvm_check_in_check_deps
test_pwd_fs_check_in_launch_container
test_pwd_fs_check_in_quick_sandbox

echo ""
echo "=== Cleanup ==="

test_cleanup_trap_has_rmdir() {
    local out
    out=$(grep -c 'rmdir.*HOST_HOME\|rmdir.*QUICK_CSB_HOME\|rmdir.*dir_slug' "$SCRIPT") || true
    if [[ "$out" -ge 1 ]]; then
        pass "cleanup trap includes rmdir for mount path"
    else
        fail "cleanup trap includes rmdir for mount path" "rmdir not found in cleanup"
    fi
}
test_cleanup_trap_has_rmdir

test_safe_rm_rootfs_defined() {
    if grep -q '^_safe_rm_rootfs()' "$SCRIPT"; then
        pass "_safe_rm_rootfs function defined"
    else
        fail "_safe_rm_rootfs function defined" "function not found"
    fi
}
test_safe_rm_rootfs_defined

test_safe_rm_rootfs_uses_mountpoint() {
    # _safe_rm_rootfs must use mountpoint -q (not rmdir) to verify bind-mounts are gone
    local func
    func=$(sed -n '/^_safe_rm_rootfs()/,/^}/p' "$SCRIPT")
    if echo "$func" | grep -q 'mountpoint -q'; then
        pass "_safe_rm_rootfs uses mountpoint -q for verification"
    else
        fail "_safe_rm_rootfs uses mountpoint -q for verification" "mountpoint -q not found"
    fi
}
test_safe_rm_rootfs_uses_mountpoint

test_safe_rm_rootfs_used_in_build() {
    # Build cleanup and failure paths must use _safe_rm_rootfs, not raw rm -rf on rootfs
    local cmd_build
    cmd_build=$(sed -n '/^cmd_build()/,/^cmd_[a-z]/p' "$SCRIPT")
    local uses
    uses=$(echo "$cmd_build" | grep -c '_safe_rm_rootfs') || true
    if [[ "$uses" -ge 2 ]]; then
        pass "cmd_build uses _safe_rm_rootfs for rootfs removal ($uses sites)"
    else
        fail "cmd_build uses _safe_rm_rootfs for rootfs removal" "found only $uses uses, expected >=2"
    fi
}
test_safe_rm_rootfs_used_in_build

test_no_raw_rmrf_rootfs_in_build() {
    # No raw 'rm -rf "${rootfs}"' or 'rm -rf "${_build_rootfs}"' in cmd_build
    local cmd_build
    cmd_build=$(sed -n '/^cmd_build()/,/^cmd_[a-z]/p' "$SCRIPT")
    local raw_rm
    raw_rm=$(echo "$cmd_build" | grep -cE 'rm -rf "\$\{(rootfs|_build_rootfs)\}"') || true
    if [[ "$raw_rm" -eq 0 ]]; then
        pass "no raw rm -rf on rootfs in cmd_build"
    else
        fail "no raw rm -rf on rootfs in cmd_build" "found $raw_rm raw rm -rf calls"
    fi
}
test_no_raw_rmrf_rootfs_in_build

test_safe_umount_rootfs_defined() {
    if grep -q '^_safe_umount_rootfs()' "$SCRIPT"; then
        pass "_safe_umount_rootfs function defined"
    else
        fail "_safe_umount_rootfs function defined" "function not found"
    fi
}
test_safe_umount_rootfs_defined

test_cleanup_trap_preserves_rootfs() {
    # Build failure cleanup must unmount (not delete) rootfs to preserve debootstrap cache
    local cleanup
    cleanup=$(sed -n '/^cmd_build()/,/^cmd_[a-z]/p' "$SCRIPT" | sed -n '/cleanup()/,/^    }/p')
    if echo "$cleanup" | grep -q '_safe_umount_rootfs'; then
        pass "cleanup trap uses _safe_umount_rootfs (preserves cache)"
    else
        fail "cleanup trap uses _safe_umount_rootfs (preserves cache)" "cleanup deletes rootfs on failure"
    fi
    if echo "$cleanup" | grep -q '_safe_rm_rootfs'; then
        fail "cleanup trap must not use _safe_rm_rootfs" "would destroy debootstrap cache on every failure"
    else
        pass "cleanup trap does not use _safe_rm_rootfs"
    fi
}
test_cleanup_trap_preserves_rootfs

test_mount_chroot_creates_dirs() {
    # _mount_chroot must mkdir -p mount targets before mounting
    local func
    func=$(sed -n '/_mount_chroot()/,/^    }/p' "$SCRIPT")
    if echo "$func" | grep -q 'mkdir -p'; then
        pass "_mount_chroot creates mount-point directories"
    else
        fail "_mount_chroot creates mount-point directories" "mkdir -p not found"
    fi
}
test_mount_chroot_creates_dirs

test_build_uses_mount_namespace() {
    local build_fn
    build_fn=$(sed -n '/^cmd_build()/,/^cmd_[a-z]/p' "$SCRIPT")
    if echo "$build_fn" | grep -q 'unshare -m'; then
        pass "cmd_build uses mount namespace isolation"
    else
        fail "cmd_build uses mount namespace isolation" "unshare -m not found"
    fi
}
test_build_uses_mount_namespace

test_build_makes_rprivate() {
    local build_fn
    build_fn=$(sed -n '/^cmd_build()/,/^cmd_[a-z]/p' "$SCRIPT")
    if echo "$build_fn" | grep -q 'make-rprivate /'; then
        pass "cmd_build sets recursive private mount propagation"
    else
        fail "cmd_build sets recursive private mount propagation" "mount --make-rprivate / not found"
    fi
}
test_build_makes_rprivate

test_mount_chroot_no_make_private() {
    local func
    func=$(sed -n '/_mount_chroot()/,/^    }/p' "$SCRIPT")
    if echo "$func" | grep -q 'make-private'; then
        fail "no --make-private in _mount_chroot (namespace handles it)" "found --make-private"
    else
        pass "no --make-private in _mount_chroot (namespace handles it)"
    fi
}
test_mount_chroot_no_make_private

test_sync_no_generic_message() {
    local out
    out=$(grep -c '"Syncing host settings to VM..."' "$SCRIPT") || true
    if [[ "$out" -eq 0 ]]; then
        pass "no generic sync message in sync_host_settings"
    else
        fail "no generic sync message in sync_host_settings" "found $out occurrences"
    fi
}
test_sync_no_generic_message

test_doctor_storage_pool_handles_error() {
    local out
    out=$(grep -c 'cannot query\|restricted project' "$SCRIPT") || true
    if [[ "$out" -ge 1 ]]; then
        pass "doctor handles storage pool query error"
    else
        fail "doctor handles storage pool query error" "no error handling found"
    fi
}
test_doctor_storage_pool_handles_error

test_no_apt_install_suggestion() {
    local out
    out=$(grep -c 'sudo apt install apt-cacher-ng' "$SCRIPT") || true
    if [[ "$out" -eq 0 ]]; then
        pass "no 'sudo apt install apt-cacher-ng' in script"
    else
        fail "no 'sudo apt install apt-cacher-ng' in script" "found $out occurrences"
    fi
}
test_no_apt_install_suggestion

test_no_proxy_prompt() {
    local out
    out=$(grep -c 'Continue without APT proxy' "$SCRIPT") || true
    if [[ "$out" -eq 0 ]]; then
        pass "no APT proxy confirmation prompt"
    else
        fail "no APT proxy confirmation prompt" "found $out occurrences"
    fi
}
test_no_proxy_prompt

test_version_check_in_shell() {
    # _check_image_version function should exist
    if grep -q '_check_image_version' "$SCRIPT"; then
        pass "version check helper exists"
    else
        fail "version check helper exists" "_check_image_version not found"
    fi
}
test_version_check_in_shell

test_update_runs_tool_scripts() {
    if grep -A 30 'cmd_update()' "$SCRIPT" | grep -q 'TOOLS_DIR\|tool_script'; then
        pass "cmd_update references tool scripts"
    else
        fail "cmd_update references tool scripts" "no tool script reference in cmd_update"
    fi
}
test_update_runs_tool_scripts

test_uid_mapping_error_shows_commands() {
    # The die message should contain actual admin commands, not just "see README"
    if grep -A 10 'UID mapping not available' "$SCRIPT" | grep -q 'incus project set'; then
        pass "UID mapping error shows admin commands"
    else
        fail "UID mapping error shows admin commands" "missing concrete admin commands"
    fi
}
test_uid_mapping_error_shows_commands

test_root_detection_in_launch() {
    # Script should check for root user (UID 0) in launch_container
    if grep -A 50 'launch_container()' "$SCRIPT" | grep -q 'id -u.*-eq 0\|UID.*0'; then
        pass "launch_container handles root user"
    else
        fail "launch_container handles root user" "no root detection found"
    fi
}
test_root_detection_in_launch

test_build_offers_workaround() {
    if grep -A 100 'cmd_build()' "$SCRIPT" | grep -q '_maybe_configure_uid_mapping\|restricted.*workaround\|restricted.containers.lowlevel'; then
        pass "cmd_build checks for UID mapping workaround"
    else
        fail "cmd_build checks for UID mapping workaround" "no workaround check in cmd_build"
    fi
}
test_build_offers_workaround

echo ""
echo "=== Download Verification ==="

test_claude_code_sha256() {
    local script="${THIS_DIR}/../tools/claude-code"
    if grep -q 'sha256sum' "$script" && grep -q 'manifest.json' "$script"; then
        pass "tools/claude-code verifies SHA256 via manifest"
    else
        fail "tools/claude-code verifies SHA256 via manifest" "missing sha256sum or manifest.json"
    fi
}
test_claude_code_sha256

test_qwen_code_gpg() {
    local script="${THIS_DIR}/../tools/qwen-code"
    if grep -q 'gpg.*verify\|gpg --verify' "$script" && grep -q 'SHASUMS256' "$script"; then
        pass "tools/qwen-code verifies GPG signature"
    else
        fail "tools/qwen-code verifies GPG signature" "missing gpg verify or SHASUMS256"
    fi
}
test_qwen_code_gpg

test_crush_sha256() {
    local script="${THIS_DIR}/../tools/crush"
    if grep -q 'checksums.txt' "$script" && grep -q 'sha256sum' "$script"; then
        pass "tools/crush verifies SHA256 via checksums.txt"
    else
        fail "tools/crush verifies SHA256 via checksums.txt" "missing checksums.txt or sha256sum"
    fi
}
test_crush_sha256

test_opencode_aur_sha() {
    local script="${THIS_DIR}/../tools/opencode"
    if grep -q 'aur.archlinux.org' "$script" && grep -q 'sha256sum' "$script"; then
        pass "tools/opencode verifies AUR SHA256"
    else
        fail "tools/opencode verifies AUR SHA256" "missing AUR or sha256sum"
    fi
}
test_opencode_aur_sha

echo ""
echo "=== Verification Dependencies ==="

test_check_deps_gpg() {
    local deps_body
    deps_body=$(sed -n '/^check_deps()/,/^}/p' "$SCRIPT")
    if echo "$deps_body" | grep -q 'gpg'; then
        pass "check_deps checks for gpg"
    else
        fail "check_deps checks for gpg" "missing gpg check"
    fi
}
test_check_deps_gpg

echo ""
echo "=== Uninstaller Generation ==="

test_tool_uninstaller() {
    local tool="$1"
    local script="${THIS_DIR}/../tools/${tool}"
    if grep -q 'lib/uninstallers' "$script" && grep -q 'chmod +x.*uninstaller\|chmod +x "\$uninstaller"' "$script"; then
        pass "tools/${tool} generates uninstaller"
    else
        fail "tools/${tool} generates uninstaller" "missing uninstaller generation"
    fi
}
test_tool_uninstaller claude-code
test_tool_uninstaller crush
test_tool_uninstaller opencode
test_tool_uninstaller qwen-code

echo ""
echo "=== cmd_update Uninstaller ==="

test_update_uses_uninstaller() {
    if grep -A 30 'cmd_update()' "$SCRIPT" | grep -q 'uninstall'; then
        pass "cmd_update calls uninstaller before reinstall"
    else
        fail "cmd_update calls uninstaller before reinstall" "no uninstaller call in cmd_update"
    fi
}
test_update_uses_uninstaller

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
(( FAIL == 0 ))
