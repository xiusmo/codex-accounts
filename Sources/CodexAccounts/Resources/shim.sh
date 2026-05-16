#!/bin/sh
# codex-accounts shim — generated, do not edit by hand.
# codex-accounts original-symlink: __CODEX_ORIGINAL_SYMLINK__
# Reads the active account name from ~/.codex.accounts/active,
# exports CODEX_HOME to that account's directory, then execs the real codex.

set -e

ACCOUNTS_DIR="${CODEX_ACCOUNTS_DIR:-$HOME/.codex.accounts}"
ACTIVE_FILE="$ACCOUNTS_DIR/active"
REAL_CODEX="__CODEX_REAL_PATH__"

if [ -r "$ACTIVE_FILE" ]; then
    ACTIVE=$(head -n1 "$ACTIVE_FILE" 2>/dev/null | tr -d '[:space:]' || true)
    if [ -n "$ACTIVE" ] && [ -d "$ACCOUNTS_DIR/$ACTIVE" ]; then
        CODEX_HOME="$ACCOUNTS_DIR/$ACTIVE"
        export CODEX_HOME
    fi
fi

if [ ! -x "$REAL_CODEX" ]; then
    echo "codex-accounts: real codex binary not found at $REAL_CODEX" >&2
    echo "Reinstall the shim from the Codex Accounts app (the install path is baked in)." >&2
    exit 127
fi

exec "$REAL_CODEX" "$@"
