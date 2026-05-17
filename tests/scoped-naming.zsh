#!/usr/bin/env zsh
set -eu

ROOT="${0:A:h:h}"
source "$ROOT/runtime/shell/xmux.zsh"

fail() {
  print -ru2 -- "FAIL: $*"
  exit 1
}

expect_eq() {
  local got="$1" want="$2" label="$3"
  [[ "$got" == "$want" ]] || fail "$label: got '$got', want '$want'"
}

resolve_for() {
  XMUX_PROJECT_DIR="$1"
  XMUX_STATE_DIR="$XMUX_PROJECT_DIR/.codex/xmux"
  _xmux_resolve_start_name "$2"
}

resolve_for "$ROOT/.codex/agent-runs/scoped-naming/test" dev
expect_eq "$_XMUX_RESOLVED_RAW_NAME" "dev" "raw name"
expect_eq "$_XMUX_RESOLVED_DISPLAY_NAME" "test/dev" "display name for test"
first_internal="$_XMUX_RESOLVED_SESSION_NAME"

resolve_for "$ROOT/.codex/agent-runs/scoped-naming/test-1" dev
expect_eq "$_XMUX_RESOLVED_DISPLAY_NAME" "test-1/dev" "display name for test-1"
second_internal="$_XMUX_RESOLVED_SESSION_NAME"

[[ "$first_internal" != "$second_internal" ]] || fail "internal names should differ across projects"

for invalid in "a--b" "a/b" "a:b" "a b"; do
  if _xmux_validate_session_name "$invalid" 2>/dev/null; then
    fail "invalid display name accepted: $invalid"
  fi
done

resolve_for "$ROOT/.codex/agent-runs/scoped-naming/my-long-project-name" pane.name_1
expect_eq "$_XMUX_RESOLVED_RAW_NAME" "pane.name_1" "raw name with dot and underscore"
[[ "$_XMUX_RESOLVED_DISPLAY_NAME" == my-long-proj/pane.name_1 ]] || fail "project slug should be capped in display name"

print -r -- "scoped naming tests passed"
