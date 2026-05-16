#!/bin/sh
# codex-accounts shim — generated, do not edit by hand.
# codex-accounts shim-v2
# codex-accounts original-symlink: __CODEX_ORIGINAL_SYMLINK__
# Supports `codex @alias`, `codex @`, and CODEX_ACCOUNT=alias.

set -e

ACCOUNTS_DIR="${CODEX_ACCOUNTS_DIR:-$HOME/.codex.accounts}"
ACTIVE_FILE="$ACCOUNTS_DIR/active"
INDEX_FILE="$ACCOUNTS_DIR/accounts.tsv"
REAL_CODEX="__CODEX_REAL_PATH__"

read_active() {
    if [ -r "$ACTIVE_FILE" ]; then
        head -n1 "$ACTIVE_FILE" 2>/dev/null | tr -d '[:space:]' || true
    fi
}

lookup_by_alias() {
    key="$1"
    field="$2"
    if [ -r "$INDEX_FILE" ]; then
        awk -F '\t' -v key="$key" -v field="$field" 'tolower($1) == tolower(key) { print $field; exit }' "$INDEX_FILE"
    fi
}

lookup_by_dir() {
    key="$1"
    field="$2"
    if [ -r "$INDEX_FILE" ]; then
        awk -F '\t' -v key="$key" -v field="$field" '$2 == key { print $field; exit }' "$INDEX_FILE"
    fi
}

print_accounts() {
    active="$(read_active)"
    if [ -r "$INDEX_FILE" ]; then
        awk -F '\t' -v active="$active" '
            /^#/ { next }
            NF >= 2 {
                display = (NF >= 3 && $3 != "") ? $3 : $2
                marker = ($2 == active) ? "  当前" : ""
                printf "%-8s %s%s\n", "@" $1, display, marker
            }
        ' "$INDEX_FILE"
    fi
}

SELECTED=""

case "${1:-}" in
    @)
        print_accounts
        exit 0
        ;;
    @*)
        SELECTED="${1#@}"
        shift
        ;;
esac

if [ -z "$SELECTED" ] && [ "${1:-}" = "--account" ]; then
    if [ -z "${2:-}" ]; then
        echo "账号不存在: @" >&2
        exit 2
    fi
    SELECTED="${2:-}"
    shift 2
fi

if [ -z "$SELECTED" ] && [ "${1:-}" = "-A" ]; then
    if [ -z "${2:-}" ]; then
        echo "账号不存在: @" >&2
        exit 2
    fi
    SELECTED="${2:-}"
    shift 2
fi

if [ -z "$SELECTED" ] && [ -n "${CODEX_ACCOUNT:-}" ]; then
    SELECTED="${CODEX_ACCOUNT#@}"
fi

if [ -n "$SELECTED" ]; then
    ACCOUNT_DIR_NAME="$(lookup_by_alias "$SELECTED" 2)"
    if [ -z "$ACCOUNT_DIR_NAME" ]; then
        ACCOUNT_DIR_NAME="$SELECTED"
    fi
    if [ ! -d "$ACCOUNTS_DIR/$ACCOUNT_DIR_NAME" ]; then
        echo "账号不存在: @$SELECTED" >&2
        exit 2
    fi
    CODEX_HOME="$ACCOUNTS_DIR/$ACCOUNT_DIR_NAME"
    export CODEX_HOME

    ACCOUNT_ALIAS="$(lookup_by_dir "$ACCOUNT_DIR_NAME" 1)"
    ACCOUNT_DISPLAY="$(lookup_by_dir "$ACCOUNT_DIR_NAME" 3)"
    [ -n "$ACCOUNT_ALIAS" ] || ACCOUNT_ALIAS="$SELECTED"
    [ -n "$ACCOUNT_DISPLAY" ] || ACCOUNT_DISPLAY="$ACCOUNT_DIR_NAME"
    if [ "${CODEX_ACCOUNTS_QUIET:-0}" != "1" ]; then
        echo "Codex Accounts: $ACCOUNT_ALIAS · $ACCOUNT_DISPLAY" >&2
        if [ "${CODEX_ACCOUNTS_TITLE:-1}" != "0" ]; then
            printf '\033]0;codex · %s\007' "$ACCOUNT_ALIAS" >&2
        fi
    fi
else
    ACTIVE="$(read_active)"
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
