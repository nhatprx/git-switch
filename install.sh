#!/usr/bin/env bash
# install.sh - Git Switch Installer (macOS / Linux)
set -e

SCRIPT_URL="https://raw.githubusercontent.com/nhatprx/git-switch/master/git.sh"
TMP_SCRIPT="$(mktemp "${TMPDIR:-/tmp}/git-switch.XXXXXX.sh")"

cleanup() {
    rm -f "$TMP_SCRIPT"
}
trap cleanup EXIT

if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$SCRIPT_URL" -o "$TMP_SCRIPT"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$TMP_SCRIPT" "$SCRIPT_URL"
else
    echo "Error: curl or wget is required to download git-switch." >&2
    exit 1
fi

chmod +x "$TMP_SCRIPT"

# Attach /dev/tty so interactive prompts work even when piped via `curl ... | bash`
if [ -r /dev/tty ]; then
    bash "$TMP_SCRIPT" < /dev/tty
else
    bash "$TMP_SCRIPT"
fi
