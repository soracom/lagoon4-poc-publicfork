#!/usr/bin/env bash
# Serialise the memory-hungry builds across worktrees.
#
# The constraint is RAM, not CPU: `yarn build` peaks at ~8.6GB RSS on a host with
# roughly 9-13GB free, so two of them at once will OOM. Several port agents work in
# parallel worktrees, so they need one lock between them rather than one each.
#
#   .devcontainer/with-build-lock.sh yarn build
#
# This is a mutex, not a scheduler. Waiters are served in no particular order.
set -euo pipefail

LOCK_DIR="${BUILD_LOCK_DIR:-/workspaces/lagoon4-poc/.locks}"
mkdir -p "$LOCK_DIR"

exec 9>"$LOCK_DIR/build"
if ! flock -n 9; then
  echo "with-build-lock: another worktree is building, waiting for the lock..." >&2
  flock 9
fi

exec "$@"
