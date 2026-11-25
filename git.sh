#!/usr/bin/env bash
# ==============================================================================
# GIT PROFILE MANAGER - ULTIMATE EDITION (macOS / Linux)
# Version: 2.2
# Author: nhatprx
# Features: SSH Auto-Gen, HTTPS PAT Swap, Remote Sync, IDE Auth Sync
# ==============================================================================

# -------------------------- CONFIGURATION --------------------------
BASE_DIR="$HOME/.git-switch"
PROFILES_FILE="$BASE_DIR/profiles.json"
TOKENS_DIR="$BASE_DIR/tokens"
SSH_DIR="$HOME/.ssh"
SSH_CONFIG_FILE="$SSH_DIR/config"

OS_TYPE="$(uname -s)"

# -------------------------- COLORS --------------------------
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_MAGENTA='\033[0;35m'
C_WHITE='\033[1;37m'
C_GRAY='\033[0;37m'
C_DARKGRAY='\033[0;90m'

# -------------------------- HELPER: UI & BOX DRAWING --------------------------
write_color() {
    local color="$1"
    local text="$2"
    local no_newline="${3:-false}"
    if [ "$no_newline" = "true" ]; then
        printf "%b%s%b" "$color" "$text" "$C_RESET"
    else
        printf "%b%s%b\n" "$color" "$text" "$C_RESET"
    fi
}

repeat_char() {
    local char="$1"
    local count="$2"
    local i=0
    local out=""
    while [ "$i" -lt "$count" ]; do
        out="${out}${char}"
        i=$((i + 1))
    done
    printf "%s" "$out"
}

draw_border_top() {
    local width="${1:-60}"
    local color="${2:-$C_CYAN}"
    local line
    line="$(repeat_char "─" "$width")"
    write_color "$color" "┌${line}┐"
}

draw_border_bottom() {
    local width="${1:-60}"
    local color="${2:-$C_CYAN}"
    local line
    line="$(repeat_char "─" "$width")"
    write_color "$color" "└${line}┘"
}

draw_separator() {
    local width="${1:-60}"
    local color="${2:-$C_CYAN}"
    local line
    line="$(repeat_char "─" "$width")"
    write_color "$color" "├${line}┤"
}

draw_line() {
    local text="$1"
    local width="${2:-60}"
    local border_color="${3:-$C_CYAN}"
    local text_color="${4:-$C_WHITE}"
    local content=" ${text} "
    local len=${#content}
    local pad=$((width - len))
    if [ "$pad" -lt 0 ]; then pad=0; fi
    local spaces
    spaces="$(repeat_char " " "$pad")"
    write_color "$border_color" "│" "true"
    write_color "$text_color" "$content" "true"
    printf "%s" "$spaces"
    write_color "$border_color" "│"
}

draw_sep() {
    write_color "$C_DARKGRAY" " ──────────────────────────────────────────────────────────────────────"
}

draw_header() {
    local title="$1"
    draw_sep
    write_color "$C_CYAN" "   » ${title}"
    draw_sep
}

pause_prompt() {
    printf "\n"
    read -r -p "Press Enter to continue..." _
}

# -------------------------- HELPER: SYSTEM & JSON --------------------------
check_dependencies() {
    if ! command -v git >/dev/null 2>&1; then
        write_color "$C_RED" "  [X] 'git' is not installed. Please install Git (or Xcode Command Line Tools on macOS)."
        exit 1
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        write_color "$C_RED" "  [X] 'python3' is required for JSON profile management. Please install Python 3."
        exit 1
    fi
}

initialize_system() {
    mkdir -p "$BASE_DIR"
    if [ ! -f "$PROFILES_FILE" ]; then
        printf "[]\n" > "$PROFILES_FILE"
    fi

    mkdir -p "$TOKENS_DIR"
    chmod 700 "$TOKENS_DIR" 2>/dev/null || true

    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR" 2>/dev/null || true

    if [ ! -f "$SSH_CONFIG_FILE" ]; then
        touch "$SSH_CONFIG_FILE"
    fi
    chmod 600 "$SSH_CONFIG_FILE" 2>/dev/null || true
}

get_git_current_name() {
    local name
    name="$(git config --global user.name 2>/dev/null || true)"
    if [ -z "$name" ]; then
        printf "Not Set"
    else
        printf "%s" "$name"
    fi
}

get_git_current_email() {
    local email
    email="$(git config --global user.email 2>/dev/null || true)"
    if [ -z "$email" ]; then
        printf "Not Set"
    else
        printf "%s" "$email"
    fi
}

is_inside_git_repo() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

get_git_local_name() {
    if is_inside_git_repo; then
        git config --local user.name 2>/dev/null || true
    fi
}

get_git_local_email() {
    if is_inside_git_repo; then
        git config --local user.email 2>/dev/null || true
    fi
}

is_commit_signing_enabled() {
    local g_sign l_sign
    g_sign="$(git config --global commit.gpgsign 2>/dev/null || true)"
    l_sign=""
    if is_inside_git_repo; then
        l_sign="$(git config --local commit.gpgsign 2>/dev/null || true)"
    fi
    [ "$g_sign" = "true" ] || [ "$l_sign" = "true" ]
}

sync_git_identity() {
    local user_name="$1"
    local user_email="$2"
    local key_path="$3"

    # 1. Global identity
    git config --global user.name "$user_name"
    git config --global user.email "$user_email"

    # 2. Local repo identity (prevents stale .git/config from overriding global)
    if is_inside_git_repo; then
        git config --local user.name "$user_name"
        git config --local user.email "$user_email"
        write_color "$C_GREEN" "   [✔] Synced local repo user.name & user.email (.git/config)."

        local local_ssh_cmd
        local_ssh_cmd="$(git config --local core.sshCommand 2>/dev/null || true)"
        if [ -n "$local_ssh_cmd" ]; then
            write_color "$C_YELLOW" "   [!] Local core.sshCommand is set (${local_ssh_cmd}) and may override ~/.ssh/config."
        fi
    fi

    # 3. Auto-enable & sync SSH commit signing unless user explicitly disabled it (commit.gpgsign = false)
    local pub_key="${key_path}.pub"
    local g_sign l_sign
    g_sign="$(git config --global commit.gpgsign 2>/dev/null || true)"
    l_sign=""
    if is_inside_git_repo; then
        l_sign="$(git config --local commit.gpgsign 2>/dev/null || true)"
    fi

    if [ -n "$key_path" ] && [ -f "$pub_key" ]; then
        if [ "$g_sign" != "false" ] && [ "$l_sign" != "false" ]; then
            git config --global gpg.format ssh
            git config --global user.signingkey "$pub_key"
            git config --global commit.gpgsign true
            if is_inside_git_repo; then
                git config --local gpg.format ssh
                git config --local user.signingkey "$pub_key"
                git config --local commit.gpgsign true
            fi
            write_color "$C_GREEN" "   [✔] SSH Commit Signing active: ${pub_key}"
        fi
    fi
}

fix_unpushed_commits_action() {
    local target_name="$1"
    local target_email="$2"

    if ! is_inside_git_repo; then
        return 0
    fi
    if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
        return 0
    fi

    local has_upstream=false range="" total_unpushed=0
    if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        has_upstream=true
        range="@{u}..HEAD"
        total_unpushed="$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
    else
        range="HEAD --not --remotes"
        total_unpushed="$(git rev-list --count HEAD --not --remotes 2>/dev/null || echo 0)"
    fi

    if [ "$total_unpushed" -eq 0 ]; then
        return 0
    fi

    local signing_on=false
    if is_commit_signing_enabled; then
        signing_on=true
    fi

    local mismatch_count=0 line c_hash c_email c_sig
    while IFS='|' read -r c_hash c_email c_sig; do
        [ -z "$c_hash" ] && continue
        if [ "$c_email" != "$target_email" ]; then
            mismatch_count=$((mismatch_count + 1))
        elif [ "$signing_on" = "true" ] && [ "$c_sig" = "N" ]; then
            mismatch_count=$((mismatch_count + 1))
        fi
    done < <(git log --format="%H|%ae|%G?" $range 2>/dev/null || true)

    if [ "$mismatch_count" -eq 0 ]; then
        return 0
    fi

    printf "\n"
    write_color "$C_YELLOW" "   [!] Found ${mismatch_count} unpushed commit(s) with different author or missing SSH signature."
    local do_fix=""
    read -r -p "   Update author to '${target_name} <${target_email}>' & re-sign before push? [Y/n]: " do_fix
    case "$do_fix" in
        n|N|no|NO)
            write_color "$C_GRAY" "   [INFO] Left unpushed commit(s) unchanged."
            return 0
            ;;
    esac

    local merge_count
    merge_count="$(git rev-list --merges --count $range 2>/dev/null || echo 0)"
    if [ "$merge_count" -gt 0 ]; then
        write_color "$C_YELLOW" "   [!] Unpushed range contains merge commit(s). Skipping auto-rewrite to keep history safe."
        return 0
    fi

    local sign_flag=""
    if [ "$signing_on" = "true" ]; then
        sign_flag="-S"
    fi

    if [ "$total_unpushed" -eq 1 ]; then
        if ! git diff --cached --quiet 2>/dev/null; then
            write_color "$C_YELLOW" "   [!] You have staged changes. Commit or unstage them before amending HEAD."
            return 0
        fi
        if git commit --amend --reset-author --no-edit $sign_flag >/dev/null 2>&1; then
            write_color "$C_GREEN" "   [✔] Updated author & re-signed the unpushed commit!"
        else
            write_color "$C_RED" "   [X] Failed to amend unpushed commit."
        fi
    else
        if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
            write_color "$C_YELLOW" "   [!] Working tree has uncommitted changes. Stash/commit them before rewriting ${total_unpushed} commits."
            return 0
        fi
        local exec_cmd="git commit --amend --reset-author --no-edit"
        [ -n "$sign_flag" ] && exec_cmd="${exec_cmd} ${sign_flag}"

        if [ "$has_upstream" = "true" ]; then
            if git rebase --exec "$exec_cmd" '@{u}' >/dev/null 2>&1; then
                write_color "$C_GREEN" "   [✔] Updated author & re-signed ${total_unpushed} unpushed commit(s)!"
            else
                git rebase --abort >/dev/null 2>&1 || true
                write_color "$C_RED" "   [X] Could not rewrite unpushed commits cleanly (aborted safely)."
            fi
        else
            if git rebase --root --exec "$exec_cmd" >/dev/null 2>&1; then
                write_color "$C_GREEN" "   [✔] Updated author & re-signed ${total_unpushed} unpushed commit(s)!"
            else
                git rebase --abort >/dev/null 2>&1 || true
                write_color "$C_RED" "   [X] Could not rewrite unpushed commits cleanly (aborted safely)."
            fi
        fi
    fi
}

# JSON helpers using built-in python3
profiles_count() {
    python3 - "$PROFILES_FILE" <<'PY'
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8-sig") as f:
        data = json.load(f)
    if isinstance(data, list):
        print(len(data))
    elif data:
        print(1)
    else:
        print(0)
except Exception:
    print(0)
PY
}

profile_exists() {
    local alias_name="$1"
    python3 - "$PROFILES_FILE" "$alias_name" <<'PY'
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8-sig") as f:
        data = json.load(f)
    if not isinstance(data, list):
        data = [data] if data else []
    exists = any(isinstance(p, dict) and p.get("alias") == sys.argv[2] for p in data)
    sys.exit(0 if exists else 1)
except Exception:
    sys.exit(1)
PY
}

profile_get_field() {
    local idx="$1"
    local field="$2"
    python3 - "$PROFILES_FILE" "$idx" "$field" <<'PY'
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8-sig") as f:
        data = json.load(f)
    if not isinstance(data, list):
        data = [data] if data else []
    item = data[int(sys.argv[2])]
    val = item.get(sys.argv[3], "")
    print("" if val is None else val)
except Exception:
    print("")
PY
}

profiles_list_table() {
    python3 - "$PROFILES_FILE" "$TOKENS_DIR" <<'PY'
import json, os, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8-sig") as f:
        data = json.load(f)
    if not isinstance(data, list):
        data = [data] if data else []
    tokens_dir = sys.argv[2]
    for i, p in enumerate(data, 1):
        alias = p.get("alias", "")
        email = p.get("userEmail", "")
        tpath = os.path.join(tokens_dir, f"{alias}.token")
        pat_tag = " [PAT]" if alias and os.path.isfile(tpath) and os.path.getsize(tpath) > 0 else ""
        print(f"     [{i}] {alias:<15} {email}{pat_tag}")
except Exception:
    pass
PY
}

profile_add_json() {
    local alias_name="$1"
    local user_name="$2"
    local user_email="$3"
    local key_path="$4"
    local gh_user="${5:-}"
    local created
    created="$(date '+%Y-%m-%d %H:%M')"
    python3 - "$PROFILES_FILE" "$alias_name" "$user_name" "$user_email" "$key_path" "$gh_user" "$created" <<'PY'
import json, sys
path, alias, uname, uemail, kpath, gh_user, created = sys.argv[1:8]
try:
    with open(path, "r", encoding="utf-8-sig") as f:
        data = json.load(f)
    if not isinstance(data, list):
        data = [data] if data else []
except Exception:
    data = []

entry = {
    "alias": alias,
    "userName": uname,
    "userEmail": uemail,
    "keyPath": kpath,
    "created": created,
}
if gh_user:
    entry["githubUsername"] = gh_user
data.append(entry)

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
}

profile_update_field() {
    local alias_name="$1"
    local field="$2"
    local value="$3"
    python3 - "$PROFILES_FILE" "$alias_name" "$field" "$value" <<'PY'
import json, sys
path, alias, field, value = sys.argv[1:5]
try:
    with open(path, "r", encoding="utf-8-sig") as f:
        data = json.load(f)
    if not isinstance(data, list):
        data = [data] if data else []
except Exception:
    data = []

for p in data:
    if isinstance(p, dict) and p.get("alias") == alias:
        if value:
            p[field] = value
        else:
            p.pop(field, None)
        break

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
}

profile_remove_json() {
    local alias_name="$1"
    python3 - "$PROFILES_FILE" "$alias_name" <<'PY'
import json, sys
path, alias = sys.argv[1:3]
try:
    with open(path, "r", encoding="utf-8-sig") as f:
        data = json.load(f)
    if not isinstance(data, list):
        data = [data] if data else []
except Exception:
    data = []

data = [p for p in data if not (isinstance(p, dict) and p.get("alias") == alias)]

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
}

copy_to_clipboard() {
    local file_path="$1"
    if [ "$OS_TYPE" = "Darwin" ] && command -v pbcopy >/dev/null 2>&1; then
        pbcopy < "$file_path"
        return 0
    elif command -v wl-copy >/dev/null 2>&1; then
        wl-copy < "$file_path"
        return 0
    elif command -v xclip >/dev/null 2>&1; then
        xclip -selection clipboard < "$file_path"
        return 0
    elif command -v xsel >/dev/null 2>&1; then
        xsel --clipboard --input < "$file_path"
        return 0
    fi
    return 1
}

open_target() {
    local target="$1"
    if [ "$OS_TYPE" = "Darwin" ] && command -v open >/dev/null 2>&1; then
        open "$target" >/dev/null 2>&1 &
        return 0
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$target" >/dev/null 2>&1 &
        return 0
    fi
    return 1
}

# -------------------------- SSH LOGIC --------------------------
generate_ssh_key() {
    local email="$1"
    local alias_name="$2"
    local key_path="$SSH_DIR/id_rsa_${alias_name}"

    if [ -f "$key_path" ]; then
        write_color "$C_YELLOW" "  [!] SSH Key already exists for this alias. Using existing key." >&2
        printf "%s" "$key_path"
        return 0
    fi

    write_color "$C_CYAN" "  [INFO] Generating new SSH Key..." >&2

    if ssh-keygen -t rsa -b 4096 -C "$email" -f "$key_path" -N "" >/dev/null 2>&1; then
        chmod 600 "$key_path" 2>/dev/null || true
        chmod 644 "${key_path}.pub" 2>/dev/null || true
        # Add to ssh-agent if available
        if [ "$OS_TYPE" = "Darwin" ]; then
            ssh-add --apple-use-keychain "$key_path" >/dev/null 2>&1 || ssh-add "$key_path" >/dev/null 2>&1 || true
        else
            ssh-add "$key_path" >/dev/null 2>&1 || true
        fi
        write_color "$C_GREEN" "  [✔] SSH Key generated successfully." >&2
        printf "%s" "$key_path"
        return 0
    else
        write_color "$C_RED" "  [X] Failed to generate SSH Key. Ensure OpenSSH is installed." >&2
        return 1
    fi
}

update_ssh_config() {
    local alias_name="$1"
    local key_path="$2"

    # Remove existing entry with the same alias first to avoid duplicates
    remove_from_ssh_config "$alias_name" "quiet"

    {
        printf "\n"
        printf "# Git profile: %s\n" "$alias_name"
        printf "Host github.com-%s\n" "$alias_name"
        printf "    HostName github.com\n"
        printf "    User git\n"
        printf "    IdentityFile %s\n" "$key_path"
        printf "    IdentitiesOnly yes\n"
        if [ "$OS_TYPE" = "Darwin" ]; then
            printf "    AddKeysToAgent yes\n"
            printf "    UseKeychain yes\n"
        fi
    } >> "$SSH_CONFIG_FILE"

    chmod 600 "$SSH_CONFIG_FILE" 2>/dev/null || true
    write_color "$C_GREEN" "  [✔] SSH Config updated (Host: github.com-${alias_name})."
}

remove_from_ssh_config() {
    local alias_name="$1"
    local quiet="${2:-}"

    if [ ! -f "$SSH_CONFIG_FILE" ]; then
        return 0
    fi

    if python3 - "$SSH_CONFIG_FILE" "$alias_name" <<'PY'
import sys

config_path, alias = sys.argv[1], sys.argv[2]
target_header = f"# Git profile: {alias}"

with open(config_path, "r", encoding="utf-8") as f:
    lines = f.readlines()

new_lines = []
skip = False
for line in lines:
    stripped = line.strip()
    if stripped == target_header:
        skip = True
        continue
    if skip:
        if stripped == "":
            skip = False
            continue
        if stripped.startswith("Host ") and stripped != f"Host github.com-{alias}":
            skip = False
            new_lines.append(line)
        elif stripped.startswith("# Git profile:"):
            skip = False
            new_lines.append(line)
        else:
            continue
    else:
        new_lines.append(line)

with open(config_path, "w", encoding="utf-8") as f:
    f.writelines(new_lines)
PY
    then
        chmod 600 "$SSH_CONFIG_FILE" 2>/dev/null || true
        if [ "$quiet" != "quiet" ]; then
            write_color "$C_GREEN" "  [✔] Removed entry from SSH Config."
        fi
    else
        if [ "$quiet" != "quiet" ]; then
            write_color "$C_YELLOW" "  [!] Error cleaning SSH Config."
        fi
    fi
}

# -------------------------- HTTPS CREDENTIAL SWAP --------------------------
token_file_path() {
    local alias_name="$1"
    printf "%s/%s.token" "$TOKENS_DIR" "$alias_name"
}

profile_has_token() {
    local alias_name="$1"
    local tpath
    tpath="$(token_file_path "$alias_name")"
    [ -n "$alias_name" ] && [ -s "$tpath" ]
}

save_profile_token() {
    local alias_name="$1"
    local token="$2"
    if [ -z "$alias_name" ] || [ -z "$token" ]; then
        return 1
    fi
    mkdir -p "$TOKENS_DIR"
    chmod 700 "$TOKENS_DIR" 2>/dev/null || true
    local tpath
    tpath="$(token_file_path "$alias_name")"
    (
        umask 077
        printf "%s" "$token" > "$tpath"
    )
    chmod 600 "$tpath" 2>/dev/null || true
}

load_profile_token() {
    local alias_name="$1"
    local tpath
    tpath="$(token_file_path "$alias_name")"
    if [ -s "$tpath" ]; then
        tr -d '\r\n' < "$tpath"
    fi
}

delete_profile_token() {
    local alias_name="$1"
    local tpath
    tpath="$(token_file_path "$alias_name")"
    if [ -f "$tpath" ]; then
        rm -f "$tpath"
    fi
}

has_osxkeychain_helper() {
    if [ "$OS_TYPE" != "Darwin" ]; then
        return 1
    fi
    local exec_path
    exec_path="$(git --exec-path 2>/dev/null || true)"
    [ -n "$exec_path" ] && [ -x "${exec_path}/git-credential-osxkeychain" ] && return 0
    command -v git-credential-osxkeychain >/dev/null 2>&1
}

has_active_git_credential_helper() {
    local active="" line
    while IFS= read -r line; do
        if [ -z "$line" ]; then
            active=""
        else
            active="$line"
        fi
    done < <(git config --get-all credential.helper 2>/dev/null || true)

    if [ -z "$active" ]; then
        while IFS= read -r line; do
            if [ -z "$line" ]; then
                active=""
            else
                active="$line"
            fi
        done < <(git config --get-all credential.https://github.com.helper 2>/dev/null || true)
    fi

    [ -n "$active" ]
}

clear_github_https_credential() {
    printf "protocol=https\nhost=github.com\n\n" | git credential reject >/dev/null 2>&1 || true
    if ! has_active_git_credential_helper && has_osxkeychain_helper; then
        printf "protocol=https\nhost=github.com\n\n" | git credential-osxkeychain erase >/dev/null 2>&1 || true
    fi
}

apply_github_https_credential() {
    local gh_user="$1"
    local pat="$2"
    if [ -z "$gh_user" ] || [ -z "$pat" ]; then
        return 1
    fi
    if ! has_active_git_credential_helper; then
        return 2
    fi
    clear_github_https_credential
    printf "protocol=https\nhost=github.com\nusername=%s\npassword=%s\n\n" "$gh_user" "$pat" | git credential approve >/dev/null 2>&1
}

sync_https_credentials() {
    local alias_name="$1"
    local gh_user="$2"
    local fallback_user="$3"
    local effective_user="${gh_user:-$fallback_user}"

    if profile_has_token "$alias_name"; then
        local pat rc=0
        pat="$(load_profile_token "$alias_name")"
        if [ -n "$pat" ] && [ -n "$effective_user" ]; then
            apply_github_https_credential "$effective_user" "$pat" || rc=$?
            if [ "$rc" -eq 0 ]; then
                write_color "$C_GREEN" "   [✔] Swapped HTTPS credential for github.com (user: ${effective_user})."
            elif [ "$rc" -eq 2 ]; then
                if [ "$OS_TYPE" = "Darwin" ]; then
                    write_color "$C_YELLOW" "   [!] No Git credential.helper configured. Run: git config --global credential.helper osxkeychain"
                else
                    write_color "$C_YELLOW" "   [!] No Git credential.helper configured. Run: git config --global credential.helper store"
                fi
            else
                write_color "$C_YELLOW" "   [!] Could not write HTTPS credential to Git credential helper."
            fi
        fi
    else
        clear_github_https_credential
        write_color "$C_GRAY" "   [INFO] Cleared cached HTTPS credential for github.com (no PAT saved for '${alias_name}')."
    fi

    # Optional GitHub CLI (gh) sync if installed and githubUsername is set
    if [ -n "$gh_user" ] && command -v gh >/dev/null 2>&1; then
        if gh auth switch --user "$gh_user" >/dev/null 2>&1; then
            write_color "$C_GREEN" "   [✔] Switched GitHub CLI (gh) account to: ${gh_user}"
        fi
    fi
}

test_github_https_connection() {
    local alias_name="$1"
    if ! profile_has_token "$alias_name"; then
        return 1
    fi
    if ! command -v curl >/dev/null 2>&1; then
        write_color "$C_YELLOW" "   [!] 'curl' not found; skipping HTTPS PAT verification."
        return 1
    fi

    local pat
    pat="$(load_profile_token "$alias_name")"
    write_color "$C_CYAN" "   [INFO] Testing HTTPS PAT for '${alias_name}'..."

    local resp login
    resp="$(printf 'header = "Authorization: Bearer %s"\nheader = "Accept: application/vnd.github+json"\nheader = "User-Agent: git-switch"\n' "$pat" | curl -fsS --max-time 10 -K - "https://api.github.com/user" 2>/dev/null || true)"
    login="$(printf "%s" "$resp" | python3 -c 'import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("login", ""))
except Exception:
    print("")
')"
    if [ -n "$login" ]; then
        write_color "$C_GREEN" "   [✔] HTTPS PAT SUCCESS! Authenticated as: ${login}"
        return 0
    else
        write_color "$C_RED" "   [X] HTTPS PAT FAILED (invalid/expired token or network error)."
        return 1
    fi
}

# -------------------------- REMOTE DETECTION & SYNC --------------------------
classify_github_remote() {
    local url="$1"
    python3 - "$url" <<'PY'
import re, sys

url = sys.argv[1].strip()
# Returns: type|repo_path|ssh_alias
m = re.match(r"^https?://(?:[^/@]+@)?github\.com(?::\d+)?/(.+)$", url, re.IGNORECASE)
if m:
    repo_path = m.group(1).rstrip("/")
    print(f"https|{repo_path}|")
    sys.exit(0)

m = re.match(r"^git@github\.com:(.+)$", url, re.IGNORECASE)
if m:
    repo_path = m.group(1).rstrip("/")
    print(f"ssh_default|{repo_path}|")
    sys.exit(0)

m = re.match(r"^ssh://git@github\.com(?::\d+)?/(.+)$", url, re.IGNORECASE)
if m:
    repo_path = m.group(1).rstrip("/")
    print(f"ssh_default|{repo_path}|")
    sys.exit(0)

m = re.match(r"^git@github\.com-([^:/]+):(.+)$", url, re.IGNORECASE)
if m:
    repo_path = m.group(2).rstrip("/")
    print(f"ssh_alias|{repo_path}|{m.group(1)}")
    sys.exit(0)

m = re.match(r"^ssh://git@github\.com-([^:/]+)(?::\d+)?/(.+)$", url, re.IGNORECASE)
if m:
    repo_path = m.group(2).rstrip("/")
    print(f"ssh_alias|{repo_path}|{m.group(1)}")
    sys.exit(0)

print("other||")
PY
}

get_active_profile_alias() {
    local curr_email
    curr_email="$(get_git_current_email)"
    python3 - "$PROFILES_FILE" "$curr_email" <<'PY'
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8-sig") as f:
        data = json.load(f)
    if not isinstance(data, list):
        data = [data] if data else []
    for p in data:
        if isinstance(p, dict) and p.get("userEmail") == sys.argv[2]:
            print(p.get("alias", ""))
            break
except Exception:
    pass
PY
}

update_repo_url() {
    local alias_name="$1"
    local mode="${2:-prompt}"

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 0
    fi

    local current_url
    current_url="$(git remote get-url origin 2>/dev/null || true)"
    if [ -z "$current_url" ]; then
        return 0
    fi

    printf "\n"
    write_color "$C_CYAN" "   [INFO] Checking Repository Remote URL..."

    local info remote_type repo_path current_ssh_alias
    info="$(classify_github_remote "$current_url")"
    IFS='|' read -r remote_type repo_path current_ssh_alias <<< "$info"

    local target_ssh_url="git@github.com-${alias_name}:${repo_path}"

    case "$remote_type" in
        https)
            write_color "$C_YELLOW" "   [!] Detected HTTPS remote: ${current_url}"
            write_color "$C_GRAY" "       SSH keys (~/.ssh/config) are ignored for HTTPS remotes."
            local do_convert="y"
            if [ "$mode" != "auto" ]; then
                read -r -p "   Convert remote to SSH alias (${target_ssh_url})? [Y/n]: " do_convert
            fi
            case "$do_convert" in
                n|N|no|NO)
                    write_color "$C_GRAY" "   [INFO] Keeping HTTPS remote."
                    if ! profile_has_token "$alias_name"; then
                        write_color "$C_YELLOW" "   [!] No HTTPS PAT saved for '${alias_name}'. Add one in Settings -> [5] Manage HTTPS Credentials."
                    fi
                    ;;
                *)
                    git remote set-url origin "$target_ssh_url"
                    write_color "$C_GREEN" "   [✔] Converted HTTPS remote -> SSH alias: ${target_ssh_url}"
                    ;;
            esac
            ;;
        ssh_default|ssh_alias)
            if [ "$target_ssh_url" != "$current_url" ]; then
                git remote set-url origin "$target_ssh_url"
                write_color "$C_GREEN" "   [✔] Updated SSH Remote URL to: ${target_ssh_url}"
            else
                write_color "$C_GRAY" "   [INFO] Remote URL already uses SSH alias: ${current_url}"
            fi
            ;;
        *)
            write_color "$C_GRAY" "   [INFO] Remote URL is not hosted on GitHub (${current_url})."
            ;;
    esac
}

# -------------------------- IDE GIT AUTH SYNC --------------------------
detect_ide_settings_paths() {
    local candidates=""
    if [ "$OS_TYPE" = "Darwin" ]; then
        candidates="VS Code|$HOME/Library/Application Support/Code/User/settings.json
VS Code Insiders|$HOME/Library/Application Support/Code - Insiders/User/settings.json
Cursor|$HOME/Library/Application Support/Cursor/User/settings.json
Antigravity|$HOME/Library/Application Support/Antigravity/User/settings.json
Windsurf|$HOME/Library/Application Support/Windsurf/User/settings.json"
    else
        candidates="VS Code|$HOME/.config/Code/User/settings.json
VS Code Insiders|$HOME/.config/Code - Insiders/User/settings.json
Cursor|$HOME/.config/Cursor/User/settings.json
Antigravity|$HOME/.config/Antigravity/User/settings.json
Windsurf|$HOME/.config/Windsurf/User/settings.json"
    fi

    printf "%s\n" "$candidates" | while IFS='|' read -r ide_name settings_path; do
        [ -z "$settings_path" ] && continue
        local parent_dir
        parent_dir="$(dirname "$settings_path")"
        if [ -f "$settings_path" ] || [ -d "$parent_dir" ]; then
            printf "%s|%s\n" "$ide_name" "$settings_path"
        fi
    done
}

get_ide_git_auth_setting() {
    local settings_path="$1"
    if [ ! -f "$settings_path" ]; then
        printf "unset"
        return 0
    fi
    python3 - "$settings_path" <<'PY'
import json, re, sys

def strip_jsonc(text):
    out = []
    i = 0
    n = len(text)
    in_str = False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            elif c == '"':
                in_str = False
            i += 1
        else:
            if c == '"':
                in_str = True
                out.append(c)
                i += 1
            elif c == "/" and i + 1 < n and text[i + 1] == "/":
                i += 2
                while i < n and text[i] != "\n":
                    i += 1
            elif c == "/" and i + 1 < n and text[i + 1] == "*":
                i += 2
                while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                    i += 1
                i += 2
            else:
                out.append(c)
                i += 1
    cleaned = "".join(out)
    cleaned = re.sub(r",(\s*[}\]])", r"\1", cleaned)
    return cleaned

try:
    with open(sys.argv[1], "r", encoding="utf-8-sig") as f:
        raw = f.read()
    if not raw.strip():
        print("unset")
        sys.exit(0)
    data = json.loads(strip_jsonc(raw))
    if isinstance(data, dict) and "github.gitAuthentication" in data:
        val = data["github.gitAuthentication"]
        print("false" if val is False else "true")
    else:
        print("unset")
except Exception:
    print("error")
PY
}

set_ide_git_auth_setting() {
    local settings_path="$1"
    local desired="${2:-false}"
    python3 - "$settings_path" "$desired" <<'PY'
import json, os, re, sys

path = sys.argv[1]
desired = "false" if sys.argv[2].lower() == "false" else "true"

def mask_comments(text):
    """Replace // and /* */ comments with spaces (preserving newlines and 1:1 indices)."""
    out = list(text)
    i = 0
    n = len(text)
    in_str = False
    while i < n:
        c = text[i]
        if in_str:
            if c == "\\" and i + 1 < n:
                i += 2
                continue
            elif c == '"':
                in_str = False
            i += 1
        else:
            if c == '"':
                in_str = True
                i += 1
            elif c == "/" and i + 1 < n and text[i + 1] == "/":
                out[i] = " "
                out[i + 1] = " "
                i += 2
                while i < n and text[i] != "\n":
                    out[i] = " "
                    i += 1
            elif c == "/" and i + 1 < n and text[i + 1] == "*":
                out[i] = " "
                out[i + 1] = " "
                i += 2
                while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                    if text[i] != "\n":
                        out[i] = " "
                    i += 1
                if i + 1 < n:
                    out[i] = " "
                    out[i + 1] = " "
                    i += 2
                else:
                    if i < n and text[i] != "\n":
                        out[i] = " "
                    i += 1
            else:
                i += 1
    return "".join(out)

def strip_jsonc(text):
    return re.sub(r",(\s*[}\]])", r"\1", mask_comments(text))

def find_root_close_brace_and_top_level_key(masked):
    """Return (root_close_idx, key_val_span_or_None) using comment-masked text."""
    depth = 0
    in_str = False
    root_close = -1
    i = 0
    n = len(masked)
    key_span = None
    key_pat = re.compile(r'"github\.gitAuthentication"\s*:\s*(true|false)')

    while i < n:
        c = masked[i]
        if in_str:
            if c == "\\" and i + 1 < n:
                i += 2
                continue
            elif c == '"':
                in_str = False
            i += 1
        else:
            if c == '"':
                if depth == 1 and key_span is None:
                    m = key_pat.match(masked, i)
                    if m:
                        key_span = (m.start(1), m.end(1))
                        i = m.end()
                        continue
                in_str = True
                i += 1
            elif c == "{":
                depth += 1
                i += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    root_close = i
                    break
                i += 1
            else:
                i += 1
    return root_close, key_span

os.makedirs(os.path.dirname(path), exist_ok=True)
if not os.path.exists(path):
    new_text = f'{{\n  "github.gitAuthentication": {desired}\n}}\n'
    with open(path, "w", encoding="utf-8") as f:
        f.write(new_text)
    sys.exit(0)

with open(path, "r", encoding="utf-8-sig") as f:
    raw = f.read()

if not raw.strip():
    new_text = f'{{\n  "github.gitAuthentication": {desired}\n}}\n'
    with open(path, "w", encoding="utf-8") as f:
        f.write(new_text)
    sys.exit(0)

masked = mask_comments(raw)
root_close, key_span = find_root_close_brace_and_top_level_key(masked)

if key_span is not None:
    new_text = raw[:key_span[0]] + desired + raw[key_span[1]:]
else:
    if root_close == -1:
        sys.exit(1)
    # Find last non-whitespace token in masked before root_close
    j = root_close - 1
    while j >= 0 and masked[j].isspace():
        j -= 1
    if j < 0:
        sys.exit(1)
    needs_comma = masked[j] not in ("{", ",")
    if needs_comma:
        before_brace = raw[:j + 1] + "," + raw[j + 1:root_close]
    else:
        before_brace = raw[:root_close]
    sep = "" if before_brace.endswith("\n") else "\n"
    new_text = f'{before_brace}{sep}  "github.gitAuthentication": {desired}\n{raw[root_close:]}'

# Validate JSONC before writing
try:
    parsed = json.loads(strip_jsonc(new_text))
    if not isinstance(parsed, dict):
        sys.exit(1)
except Exception:
    # Fallback: parse clean dict and dump
    try:
        parsed = json.loads(strip_jsonc(raw))
        if not isinstance(parsed, dict):
            sys.exit(1)
        parsed["github.gitAuthentication"] = (desired == "true")
        new_text = json.dumps(parsed, indent=2, ensure_ascii=False) + "\n"
    except Exception:
        sys.exit(1)

with open(path, "w", encoding="utf-8") as f:
    f.write(new_text)
PY
}

show_ide_sync_hint() {
    local mode="${1:-hint}"
    local ide_lines need_hint=false ide_list=""
    local -a pending_names=()
    local -a pending_paths=()
    local p_idx=0

    ide_lines="$(detect_ide_settings_paths)"
    if [ -n "$ide_lines" ]; then
        while IFS='|' read -r ide_name settings_path; do
            [ -z "$settings_path" ] && continue
            local state
            state="$(get_ide_git_auth_setting "$settings_path")"
            if [ "$state" != "false" ]; then
                need_hint=true
                pending_names[$p_idx]="$ide_name"
                pending_paths[$p_idx]="$settings_path"
                p_idx=$((p_idx + 1))
                if [ -z "$ide_list" ]; then
                    ide_list="$ide_name"
                else
                    ide_list="${ide_list}, ${ide_name}"
                fi
            fi
        done <<< "$ide_lines"
    else
        # Even if no known IDE path detected, show tip when remote is HTTPS
        if is_inside_git_repo; then
            local origin_url info rtype
            origin_url="$(git remote get-url origin 2>/dev/null || true)"
            if [ -n "$origin_url" ]; then
                info="$(classify_github_remote "$origin_url")"
                IFS='|' read -r rtype _ _ <<< "$info"
                if [ "$rtype" = "https" ]; then
                    need_hint=true
                    ide_list="VS Code / Cursor / Antigravity"
                fi
            fi
        fi
    fi

    if [ "$need_hint" = "true" ]; then
        printf "\n"
        write_color "$C_YELLOW" "   [TIP] IDE Sync (${ide_list}):"
        write_color "$C_GRAY" "         IDE GitHub extension uses its own OAuth session for UI Push/Pull."
        if [ "$mode" = "prompt" ] && [ "$p_idx" -gt 0 ]; then
            local do_disable=""
            read -r -p "   Disable \"github.gitAuthentication\" for ${ide_list} now so UI Push uses git-switch? [Y/n]: " do_disable
            case "$do_disable" in
                n|N|no|NO)
                    write_color "$C_GRAY" "   [INFO] Skipped. You can configure this anytime in Settings -> [6] IDE Git Auth Sync."
                    ;;
                *)
                    local k=0
                    while [ "$k" -lt "$p_idx" ]; do
                        if set_ide_git_auth_setting "${pending_paths[$k]}" "false"; then
                            write_color "$C_GREEN" "   [✔] ${pending_names[$k]}: Set \"github.gitAuthentication\": false"
                        else
                            write_color "$C_RED" "   [X] ${pending_names[$k]}: Failed to update ${pending_paths[$k]}"
                        fi
                        k=$((k + 1))
                    done
                    ;;
            esac
        else
            write_color "$C_GRAY" "         Set \"github.gitAuthentication\": false in IDE settings.json to share"
            write_color "$C_GRAY" "         credentials with git-switch (or use Settings -> [6] IDE Git Auth Sync)."
        fi
    fi
}

test_github_connection() {
    local alias_name="$1"
    local host_alias="github.com-${alias_name}"
    printf "\n"
    write_color "$C_CYAN" "   [INFO] Testing connection to ${host_alias}..."

    local output
    output="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T "git@${host_alias}" 2>&1 || true)"

    if printf "%s" "$output" | grep -qi "successfully authenticated"; then
        write_color "$C_GREEN" "   [✔] Connection SUCCESS! You are authenticated."
        return 0
    else
        write_color "$C_RED" "   [X] Connection FAILED."
        write_color "$C_DARKGRAY" "   [DEBUG] ${output}"
        return 1
    fi
}

# -------------------------- FEATURE FUNCTIONS --------------------------
test_connection_action() {
    local count
    count="$(profiles_count)"
    if [ "$count" -eq 0 ]; then
        printf "\n"
        write_color "$C_YELLOW" "  [!] No profiles found."
        return
    fi

    printf "\n"
    draw_border_top 60 "$C_MAGENTA"
    draw_line "TEST GITHUB CONNECTION" 60 "$C_MAGENTA" "$C_WHITE"
    draw_separator 60 "$C_MAGENTA"

    local i=0
    while [ "$i" -lt "$count" ]; do
        local alias_name
        alias_name="$(profile_get_field "$i" "alias")"
        draw_line "  [$((i + 1))] ${alias_name}" 60 "$C_MAGENTA" "$C_WHITE"
        i=$((i + 1))
    done
    draw_border_bottom 60 "$C_MAGENTA"

    local choice
    read -r -p "  Select ID to test (0 to cancel): " choice
    case "$choice" in
        ""|0|*[!0-9]*) return ;;
    esac

    local idx=$((choice - 1))
    if [ "$idx" -lt 0 ] || [ "$idx" -ge "$count" ]; then
        return
    fi

    local selected_alias selected_key
    selected_alias="$(profile_get_field "$idx" "alias")"
    selected_key="$(profile_get_field "$idx" "keyPath")"

    if [ -n "$selected_key" ]; then
        test_github_connection "$selected_alias" || true
    else
        write_color "$C_YELLOW" "  [!] Profile '${selected_alias}' does not have an SSH key recorded."
    fi

    if profile_has_token "$selected_alias"; then
        printf "\n"
        test_github_https_connection "$selected_alias" || true
    fi
}

add_profile_action() {
    printf "\n"
    draw_header "ADD NEW GIT PROFILE"

    local alias_name=""
    while true; do
        read -r -p "   Enter Profile Alias (e.g. Work, Personal): " alias_name
        if [ "$alias_name" = "0" ]; then return; fi

        local err_msg=""
        if [ -z "$alias_name" ]; then
            err_msg="Alias required."
        elif ! printf "%s" "$alias_name" | grep -Eq '^[a-zA-Z0-9]+$'; then
            err_msg="Alias must be alphanumeric (no spaces/symbols)."
        elif profile_exists "$alias_name"; then
            err_msg="Profile '${alias_name}' already exists."
        fi

        if [ -n "$err_msg" ]; then
            write_color "$C_RED" "   [!] ${err_msg}"
            local retry
            read -r -p "   Press ENTER to retry, or type '0' to back: " retry
            if [ "$retry" = "0" ]; then return; fi
            printf "\n"
        else
            break
        fi
    done

    local u_name u_email gh_user gh_pat
    read -r -p "   Enter Git User Name (e.g. John Doe): " u_name
    read -r -p "   Enter Git Email     (e.g. john@company.com): " u_email

    if [ -z "$u_name" ] || [ -z "$u_email" ]; then
        write_color "$C_RED" "   [!] Name and Email are required."
        return
    fi

    read -r -p "   Enter GitHub Username (optional, for HTTPS/gh sync, Enter to skip): " gh_user
    read -r -s -p "   Enter GitHub HTTPS PAT (optional, hidden, Enter to skip): " gh_pat
    printf "\n"

    # 1. Generate Key
    local key_path
    if ! key_path="$(generate_ssh_key "$u_email" "$alias_name")"; then
        return
    fi

    # 2. Update SSH Config
    update_ssh_config "$alias_name" "$key_path"

    # 3. Clipboard
    local pub_key_path="${key_path}.pub"
    if [ -f "$pub_key_path" ]; then
        if copy_to_clipboard "$pub_key_path"; then
            write_color "$C_GREEN" "   [✔] Public Key copied to CLIPBOARD!"
        else
            write_color "$C_YELLOW" "   [!] Could not auto-copy. Public key path: ${pub_key_path}"
        fi
    fi

    # 4. Instructions & Open Browser
    local paste_shortcut="Ctrl+V"
    if [ "$OS_TYPE" = "Darwin" ]; then
        paste_shortcut="Cmd+V"
    fi

    printf "\n"
    write_color "$C_YELLOW" "   [ACTION REQUIRED]"
    write_color "$C_GRAY" "   1. I will open GitHub SSH settings now."
    write_color "$C_GRAY" "   2. Paste (${paste_shortcut}) and add the key as 'Authentication Key' (for git push)."
    write_color "$C_GRAY" "   3. (For Verified commits) Add the SAME key once more with Key type = 'Signing Key'."
    write_color "$C_GRAY" "   4. Come back here and press ENTER."

    sleep 2
    open_target "https://github.com/settings/ssh/new" || true

    printf "\n"
    read -r -p "   Press ENTER after you have added the key on GitHub..." _

    # 5. Test Connection
    test_github_connection "$alias_name" || true

    # 6. Save Profile (& optional HTTPS PAT)
    profile_add_json "$alias_name" "$u_name" "$u_email" "$key_path" "$gh_user"
    if [ -n "$gh_pat" ]; then
        save_profile_token "$alias_name" "$gh_pat"
        write_color "$C_GREEN" "   [✔] Saved HTTPS PAT securely (chmod 600)."
    fi
    printf "\n"
    write_color "$C_GREEN" "   [✔] Profile '${alias_name}' saved successfully!"

    # Auto-set Global Config if currently unset
    local curr_name
    curr_name="$(get_git_current_name)"
    if [ "$curr_name" = "Not Set" ]; then
        sync_git_identity "$u_name" "$u_email" "$key_path"
        sync_https_credentials "$alias_name" "$gh_user" "$u_name"
        write_color "$C_CYAN" "   [INFO] Auto-set as Global Git Config (was previously unset)."
    fi
}

switch_profile_action() {
    local count
    count="$(profiles_count)"
    if [ "$count" -eq 0 ]; then
        printf "\n"
        write_color "$C_YELLOW" "   [!] No profiles. Add one first."
        return
    fi

    printf "\n"
    draw_header "SWITCH PROFILE"
    write_color "$C_DARKGRAY" "$(printf "     [%s] %-15s %s" "#" "ALIAS" "EMAIL")"
    write_color "$C_WHITE" "$(profiles_list_table)"
    draw_sep

    local choice
    read -r -p "   Choose ID (0 to cancel): " choice
    case "$choice" in
        ""|0|*[!0-9]*) return ;;
    esac

    local idx=$((choice - 1))
    if [ "$idx" -lt 0 ] || [ "$idx" -ge "$count" ]; then
        return
    fi

    local selected_alias selected_name selected_email selected_key selected_gh_user
    selected_alias="$(profile_get_field "$idx" "alias")"
    selected_name="$(profile_get_field "$idx" "userName")"
    selected_email="$(profile_get_field "$idx" "userEmail")"
    selected_key="$(profile_get_field "$idx" "keyPath")"
    selected_gh_user="$(profile_get_field "$idx" "githubUsername")"

    printf "\n"
    write_color "$C_CYAN" "   [INFO] Switching to '${selected_alias}'..."

    # 1. Change Global & Local Config (+ Auto SSH Signing Key)
    sync_git_identity "$selected_name" "$selected_email" "$selected_key"

    # 2. Swap/Clear HTTPS Credential (osxkeychain / Git credential helper / gh CLI)
    sync_https_credentials "$selected_alias" "$selected_gh_user" "$selected_name"

    # 3. Detect & Update Repo Remote URL (HTTPS vs SSH)
    update_repo_url "$selected_alias"

    # 4. Offer to update author & re-sign unpushed local commits
    fix_unpushed_commits_action "$selected_name" "$selected_email"

    # 5. Test SSH
    if [ -n "$selected_key" ]; then
        test_github_connection "$selected_alias" || true
    fi

    # 6. Inline IDE Git Auth Sync (1-press disable if enabled)
    show_ide_sync_hint "prompt"

    printf "\n"
    write_color "$C_GREEN" "   [✔] Switched successfully!"
    write_color "$C_GRAY" "       Global User : ${selected_name}"
    write_color "$C_GRAY" "       Global Email: ${selected_email}"
    if is_inside_git_repo; then
        write_color "$C_GRAY" "       Local Repo  : Synced to ${selected_name} <${selected_email}>"
    fi
}

remove_profile_action() {
    local count
    count="$(profiles_count)"
    if [ "$count" -eq 0 ]; then
        printf "\n"
        write_color "$C_YELLOW" "   [!] No profiles to remove."
        return
    fi

    printf "\n"
    draw_header "REMOVE PROFILE"
    write_color "$C_DARKGRAY" "$(printf "     [%s] %-15s %s" "#" "ALIAS" "EMAIL")"
    write_color "$C_WHITE" "$(profiles_list_table)"
    draw_sep

    local choice
    read -r -p "   Select ID to remove (0 to cancel): " choice
    case "$choice" in
        ""|0|*[!0-9]*) return ;;
    esac

    local idx=$((choice - 1))
    if [ "$idx" -lt 0 ] || [ "$idx" -ge "$count" ]; then
        return
    fi

    local removed_alias removed_name removed_email removed_key
    removed_alias="$(profile_get_field "$idx" "alias")"
    removed_name="$(profile_get_field "$idx" "userName")"
    removed_email="$(profile_get_field "$idx" "userEmail")"
    removed_key="$(profile_get_field "$idx" "keyPath")"

    printf "\n"
    write_color "$C_RED" "   [WARNING] Deleting profile '${removed_alias}'..."
    local confirm
    read -r -p "   Type 'DELETE' to confirm: " confirm
    if [ "$confirm" != "DELETE" ]; then
        return
    fi

    # 1. Remove SSH Keys
    if [ -n "$removed_key" ]; then
        if [ -f "$removed_key" ]; then
            rm -f "$removed_key"
            write_color "$C_GRAY" "   [✔] Private Key deleted."
        fi
        if [ -f "${removed_key}.pub" ]; then
            rm -f "${removed_key}.pub"
            write_color "$C_GRAY" "   [✔] Public Key deleted."
        fi
    fi

    # 2. Remove from SSH Config & Saved HTTPS PAT
    remove_from_ssh_config "$removed_alias"
    if profile_has_token "$removed_alias"; then
        delete_profile_token "$removed_alias"
        write_color "$C_GRAY" "   [✔] Saved HTTPS PAT deleted."
    fi

    # 3. Remove from JSON
    profile_remove_json "$removed_alias"

    # 4. Check & Clear Global/Local Config, Signing Key, and Cached HTTPS Credential
    local curr_name curr_email curr_skey
    curr_name="$(get_git_current_name)"
    curr_email="$(get_git_current_email)"
    if [ "$curr_name" = "$removed_name" ] || [ "$curr_email" = "$removed_email" ]; then
        git config --global --unset user.name 2>/dev/null || true
        git config --global --unset user.email 2>/dev/null || true
        clear_github_https_credential
        write_color "$C_CYAN" "   [INFO] Current Global Git config & cached HTTPS credential cleared because profile was removed."
    fi

    curr_skey="$(git config --global user.signingkey 2>/dev/null || true)"
    if [ -n "$removed_key" ] && [ "$curr_skey" = "${removed_key}.pub" ]; then
        git config --global --unset user.signingkey 2>/dev/null || true
    fi

    if is_inside_git_repo; then
        local local_email local_skey
        local_email="$(get_git_local_email)"
        if [ "$local_email" = "$removed_email" ]; then
            git config --local --unset user.name 2>/dev/null || true
            git config --local --unset user.email 2>/dev/null || true
            write_color "$C_CYAN" "   [INFO] Local repo Git config cleared because profile was removed."
        fi
        local_skey="$(git config --local user.signingkey 2>/dev/null || true)"
        if [ -n "$removed_key" ] && [ "$local_skey" = "${removed_key}.pub" ]; then
            git config --local --unset user.signingkey 2>/dev/null || true
        fi
    fi

    write_color "$C_GREEN" "   [✔] Profile removed successfully."
}

toggle_ssh_signing() {
    if is_commit_signing_enabled; then
        git config --global commit.gpgsign false
        if is_inside_git_repo; then
            git config --local --unset commit.gpgsign 2>/dev/null || true
        fi
        write_color "$C_YELLOW" "   [✔] SSH Commit Signing disabled (commit.gpgsign = false)."
    else
        git config --global gpg.format ssh
        git config --global commit.gpgsign true
        # Try to match active email to a saved profile key
        local curr_email matched_key
        curr_email="$(get_git_current_email)"
        matched_key="$(python3 - "$PROFILES_FILE" "$curr_email" <<'PY'
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8-sig") as f:
        data = json.load(f)
    if not isinstance(data, list):
        data = [data] if data else []
    for p in data:
        if isinstance(p, dict) and p.get("userEmail") == sys.argv[2] and p.get("keyPath"):
            print(p["keyPath"])
            break
except Exception:
    pass
PY
)"
        if [ -n "$matched_key" ] && [ -f "${matched_key}.pub" ]; then
            git config --global user.signingkey "${matched_key}.pub"
            if is_inside_git_repo; then
                git config --local gpg.format ssh
                git config --local user.signingkey "${matched_key}.pub"
            fi
            write_color "$C_GREEN" "   [✔] SSH Commit Signing enabled with key: ${matched_key}.pub"
        else
            write_color "$C_GREEN" "   [✔] SSH Commit Signing enabled (switch a profile to assign signing key)."
        fi
        write_color "$C_GRAY" "   [TIP] Add your .pub key on GitHub as Key type = 'Signing Key' for Verified badge."
    fi
}

manage_https_credentials_action() {
    printf "\n"
    draw_header "MANAGE HTTPS CREDENTIALS (PAT)"

    local count
    count="$(profiles_count)"
    if [ "$count" -eq 0 ]; then
        write_color "$C_YELLOW" "   [!] No profiles found. Add a profile first."
        return
    fi

    write_color "$C_DARKGRAY" "$(printf "     [%s] %-15s %-22s %s" "#" "ALIAS" "GITHUB USER" "PAT STATUS")"
    local i=0
    while [ "$i" -lt "$count" ]; do
        local p_alias p_gh p_status
        p_alias="$(profile_get_field "$i" "alias")"
        p_gh="$(profile_get_field "$i" "githubUsername")"
        [ -z "$p_gh" ] && p_gh="(not set)"
        if profile_has_token "$p_alias"; then
            p_status="Configured"
        else
            p_status="Not Set"
        fi
        printf "     [%d] %-15s %-22s %s\n" "$((i + 1))" "$p_alias" "$p_gh" "$p_status"
        i=$((i + 1))
    done
    printf "\n"
    printf "     [C] Clear cached github.com HTTPS credential now\n"
    printf "     [0] Back\n"
    draw_sep

    local choice
    read -r -p "   Select profile ID (or C/0): " choice
    case "$choice" in
        0|"") return ;;
        c|C)
            clear_github_https_credential
            write_color "$C_GREEN" "   [✔] Cleared cached github.com HTTPS credential from Git credential helper."
            return
            ;;
        *[!0-9]*) return ;;
    esac

    local idx=$((choice - 1))
    if [ "$idx" -lt 0 ] || [ "$idx" -ge "$count" ]; then
        return
    fi

    local sel_alias sel_name sel_email sel_gh
    sel_alias="$(profile_get_field "$idx" "alias")"
    sel_name="$(profile_get_field "$idx" "userName")"
    sel_email="$(profile_get_field "$idx" "userEmail")"
    sel_gh="$(profile_get_field "$idx" "githubUsername")"

    printf "\n"
    write_color "$C_CYAN" "   Profile: ${sel_alias} <${sel_email}>"
    printf "     [1] Set / Update GitHub Username & HTTPS PAT\n"
    printf "     [2] Remove saved HTTPS PAT\n"
    printf "     [3] Test saved HTTPS PAT\n"
    printf "     [0] Back\n"
    draw_sep

    local sub
    read -r -p "   Choose: " sub
    case "$sub" in
        1)
            local new_gh new_pat
            read -r -p "   GitHub Username [${sel_gh:-$sel_name}]: " new_gh
            if [ -z "$new_gh" ]; then
                new_gh="${sel_gh:-$sel_name}"
            fi
            read -r -s -p "   GitHub PAT (hidden, Enter to keep existing): " new_pat
            printf "\n"

            profile_update_field "$sel_alias" "githubUsername" "$new_gh"
            if [ -n "$new_pat" ]; then
                save_profile_token "$sel_alias" "$new_pat"
                write_color "$C_GREEN" "   [✔] Saved HTTPS PAT securely for '${sel_alias}' (chmod 600)."
            else
                write_color "$C_GREEN" "   [✔] Updated GitHub Username to '${new_gh}'."
            fi

            local curr_email
            curr_email="$(get_git_current_email)"
            if [ "$curr_email" = "$sel_email" ]; then
                sync_https_credentials "$sel_alias" "$new_gh" "$sel_name"
            fi
            ;;
        2)
            delete_profile_token "$sel_alias"
            write_color "$C_YELLOW" "   [✔] Removed saved HTTPS PAT for '${sel_alias}'."
            local curr_email
            curr_email="$(get_git_current_email)"
            if [ "$curr_email" = "$sel_email" ]; then
                clear_github_https_credential
                write_color "$C_GRAY" "   [INFO] Also cleared active cached github.com HTTPS credential."
            fi
            ;;
        3)
            if profile_has_token "$sel_alias"; then
                test_github_https_connection "$sel_alias" || true
            else
                write_color "$C_YELLOW" "   [!] No HTTPS PAT saved for '${sel_alias}'."
            fi
            ;;
    esac
}

ide_git_auth_sync_action() {
    printf "\n"
    draw_header "IDE GIT AUTH SYNC (github.gitAuthentication)"

    write_color "$C_GRAY" "   VS Code / Cursor / Antigravity use their own GitHub OAuth session for UI Push."
    write_color "$C_GRAY" "   Setting \"github.gitAuthentication\": false makes IDE Push use git-switch."
    printf "\n"

    local ide_lines
    ide_lines="$(detect_ide_settings_paths)"
    if [ -z "$ide_lines" ]; then
        write_color "$C_YELLOW" "   [!] No supported IDE settings directory detected automatically."
        write_color "$C_GRAY" "       Manually add this to your IDE settings.json:"
        write_color "$C_WHITE" "         \"github.gitAuthentication\": false"
        return
    fi

    local idx=0
    local -a ide_names=()
    local -a ide_paths=()

    while IFS='|' read -r ide_name settings_path; do
        [ -z "$settings_path" ] && continue
        ide_names[$idx]="$ide_name"
        ide_paths[$idx]="$settings_path"
        idx=$((idx + 1))
        local state label
        state="$(get_ide_git_auth_setting "$settings_path")"
        case "$state" in
            false) label="OFF (Synced with git-switch)" ;;
            true)  label="ON  (Uses IDE OAuth)" ;;
            unset) label="ON  (Default - Uses IDE OAuth)" ;;
            *)     label="UNKNOWN (Could not parse settings.json)" ;;
        esac
        printf "     [%d] %-18s %s\n" "$idx" "$ide_name" "$label"
    done <<< "$ide_lines"

    printf "\n"
    printf "     [A] Disable github.gitAuthentication for ALL detected IDEs (Recommended)\n"
    printf "     [0] Back\n"
    draw_sep

    local opt
    read -r -p "   Select IDE # to toggle, A for all, or 0 to back: " opt
    case "$opt" in
        0|"")
            return
            ;;
        a|A)
            local n=0
            while [ "$n" -lt "$idx" ]; do
                local iname ipath
                iname="${ide_names[$n]}"
                ipath="${ide_paths[$n]}"
                if set_ide_git_auth_setting "$ipath" "false"; then
                    write_color "$C_GREEN" "   [✔] ${iname}: Set \"github.gitAuthentication\": false"
                else
                    write_color "$C_RED" "   [X] ${iname}: Failed to update ${ipath}"
                fi
                n=$((n + 1))
            done
            ;;
        *[!0-9]*)
            ;;
        *)
            if [ "$opt" -ge 1 ] && [ "$opt" -le "$idx" ]; then
                local sel_i=$((opt - 1))
                local iname ipath cur_state next_val
                iname="${ide_names[$sel_i]}"
                ipath="${ide_paths[$sel_i]}"
                cur_state="$(get_ide_git_auth_setting "$ipath")"
                if [ "$cur_state" = "false" ]; then
                    next_val="true"
                else
                    next_val="false"
                fi
                if set_ide_git_auth_setting "$ipath" "$next_val"; then
                    write_color "$C_GREEN" "   [✔] ${iname}: Set \"github.gitAuthentication\": ${next_val}"
                else
                    write_color "$C_RED" "   [X] ${iname}: Failed to update ${ipath}"
                fi
            fi
            ;;
    esac
}

show_settings_action() {
    printf "\n"
    draw_header "SETTINGS & TOOLS"

    local sign_state="OFF"
    if is_commit_signing_enabled; then
        sign_state="ON"
    fi

    printf "     [1] Open profiles.json (View/Edit DB)\n"
    printf "     [2] Backup Profiles (Create snapshot)\n"
    printf "     [3] Open .ssh folder (View Keys)\n"
    printf "     [4] Toggle SSH Commit Signing (Currently: %s)\n" "$sign_state"
    printf "     [5] Manage HTTPS Credentials (PAT / Keychain)\n"
    printf "     [6] IDE Git Auth Sync (github.gitAuthentication)\n"
    printf "     [0] Back\n"

    draw_sep

    local opt
    read -r -p "   Choose: " opt
    case "$opt" in
        1)
            open_target "$PROFILES_FILE" || write_color "$C_GRAY" "   Path: ${PROFILES_FILE}"
            ;;
        2)
            local bak
            bak="${BASE_DIR}/backup_$(date '+%Y%m%d_%H%M').json"
            cp "$PROFILES_FILE" "$bak"
            write_color "$C_GREEN" "   [✔] Backup created: ${bak}"
            ;;
        3)
            open_target "$SSH_DIR" || write_color "$C_GRAY" "   Path: ${SSH_DIR}"
            ;;
        4)
            toggle_ssh_signing
            ;;
        5)
            manage_https_credentials_action
            ;;
        6)
            ide_git_auth_sync_action
            ;;
    esac
}

# -------------------------- MAIN UI --------------------------
show_banner() {
    printf "%b" "$C_MAGENTA"
    cat <<'EOF'
      ██████  ██ ████████     ███████ ██     ██ ██ ████████  ██████  ██   ██
     ██       ██    ██        ██      ██     ██ ██    ██    ██       ██   ██
     ██   ███ ██    ██        ███████ ██  █  ██ ██    ██    ██       ███████
     ██    ██ ██    ██             ██ ██ ███ ██ ██    ██    ██       ██   ██
      ██████  ██    ██        ███████  ███ ███  ██    ██     ██████  ██   ██
EOF
    printf "%b" "$C_RESET"
    draw_sep

    local curr_name curr_email os_label
    curr_name="$(get_git_current_name)"
    curr_email="$(get_git_current_email)"
    if [ "$OS_TYPE" = "Darwin" ]; then
        os_label="macOS"
    else
        os_label="$OS_TYPE"
    fi

    write_color "$C_WHITE" "   » GIT PROFILE MANAGEMENT SYSTEM [v2.3 - ${os_label}]"
    draw_sep

    if [ "$(id -u)" -eq 0 ]; then
        write_color "$C_GREEN" "   [✔] STATUS: Running as root"
    else
        write_color "$C_GREEN" "   [✔] STATUS: Running as $(whoami) (${os_label})"
    fi

    write_color "$C_CYAN" "   [●] CURRENT: " "true"
    write_color "$C_WHITE" "${curr_name} " "true"
    write_color "$C_DARKGRAY" "<${curr_email}>"

    if is_inside_git_repo; then
        local local_name local_email
        local_name="$(get_git_local_name)"
        local_email="$(get_git_local_email)"
        if [ -n "$local_email" ] && [ "$local_email" != "$curr_email" ]; then
            write_color "$C_YELLOW" "   [!] LOCAL OVERRIDE: ${local_name:-$curr_name} <${local_email}> (Switch to sync)"
        fi

        local origin_url
        origin_url="$(git remote get-url origin 2>/dev/null || true)"
        if [ -n "$origin_url" ]; then
            local rinfo rtype rpath ralias active_alias
            rinfo="$(classify_github_remote "$origin_url")"
            IFS='|' read -r rtype rpath ralias <<< "$rinfo"
            case "$rtype" in
                https)
                    write_color "$C_YELLOW" "   [!] REMOTE (HTTPS): ${origin_url} (SSH config ignored; switch to convert/PAT)"
                    ;;
                ssh_default)
                    write_color "$C_YELLOW" "   [!] REMOTE (SSH): ${origin_url} (No profile alias; switch to bind)"
                    ;;
                ssh_alias)
                    active_alias="$(get_active_profile_alias)"
                    if [ -n "$active_alias" ] && [ "$ralias" != "$active_alias" ]; then
                        write_color "$C_YELLOW" "   [!] REMOTE (SSH): github.com-${ralias} != active '${active_alias}' (Switch to sync)"
                    else
                        write_color "$C_GREEN" "   [✔] REMOTE (SSH): ${origin_url}"
                    fi
                    ;;
            esac
        fi
    fi

    if is_commit_signing_enabled; then
        local skey
        skey="$(git config --get user.signingkey 2>/dev/null || true)"
        if [ -n "$skey" ]; then
            write_color "$C_GREEN" "   [✔] SSH SIGNING: ON ($(basename "$skey"))"
        else
            write_color "$C_YELLOW" "   [!] SSH SIGNING: ON (no signing key set)"
        fi
    fi
    draw_sep
}

show_menu() {
    printf "\n"
    write_color "$C_GRAY" "   SELECT AN OPTION:"
    printf "\n"
    printf "     [1] Add New Profile\n"
    printf "     [2] Switch Profile\n"
    printf "     [3] Remove Profile\n"
    printf "     [4] Settings\n"
    printf "     [5] Test Connection\n"
    printf "     [0] Exit Program\n"
    printf "\n"
    draw_sep
}

# ================= MAIN EXECUTION LOOP =================
main() {
    check_dependencies
    initialize_system

    local running=true
    while [ "$running" = "true" ]; do
        clear
        show_banner
        show_menu
        local selection=""
        read -r -p "  Choose an option (0-5): " selection || break

        case "$selection" in
            1) add_profile_action; pause_prompt ;;
            2) switch_profile_action; pause_prompt ;;
            3) remove_profile_action; pause_prompt ;;
            4) show_settings_action; pause_prompt ;;
            5) test_connection_action; pause_prompt ;;
            0) running=false; printf "\n"; write_color "$C_MAGENTA" "  Goodbye! 👋" ;;
            *) write_color "$C_RED" "  Invalid option."; sleep 0.5 ;;
        esac
    done
}

# Only run main when executed directly (allows sourcing for tests)
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
