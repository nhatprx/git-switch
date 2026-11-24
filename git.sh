#!/usr/bin/env bash
# ==============================================================================
# GIT PROFILE MANAGER - ULTIMATE EDITION (macOS / Linux)
# Version: 2.1
# Author: nhatprx
# Features: SSH Auto-Gen, Config Management, Clipboard, Browser Integration
# ==============================================================================

# -------------------------- CONFIGURATION --------------------------
BASE_DIR="$HOME/.git-switch"
PROFILES_FILE="$BASE_DIR/profiles.json"
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
    fi

    # 3. Sync SSH commit signing key if signing is enabled or already configured for SSH
    local pub_key="${key_path}.pub"
    local curr_fmt curr_skey
    curr_fmt="$(git config --global gpg.format 2>/dev/null || true)"
    curr_skey="$(git config --global user.signingkey 2>/dev/null || true)"

    if [ -n "$key_path" ] && [ -f "$pub_key" ]; then
        if is_commit_signing_enabled || [ "$curr_fmt" = "ssh" ] || [ -n "$curr_skey" ]; then
            git config --global gpg.format ssh
            git config --global user.signingkey "$pub_key"
            if is_inside_git_repo; then
                git config --local gpg.format ssh
                git config --local user.signingkey "$pub_key"
            fi
            write_color "$C_GREEN" "   [✔] Updated Git SSH signing key: ${pub_key}"
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
    python3 - "$PROFILES_FILE" <<'PY'
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8-sig") as f:
        data = json.load(f)
    if not isinstance(data, list):
        data = [data] if data else []
    for i, p in enumerate(data, 1):
        alias = p.get("alias", "")
        email = p.get("userEmail", "")
        print(f"     [{i}] {alias:<15} {email}")
except Exception:
    pass
PY
}

profile_add_json() {
    local alias_name="$1"
    local user_name="$2"
    local user_email="$3"
    local key_path="$4"
    local created
    created="$(date '+%Y-%m-%d %H:%M')"
    python3 - "$PROFILES_FILE" "$alias_name" "$user_name" "$user_email" "$key_path" "$created" <<'PY'
import json, sys
path, alias, uname, uemail, kpath, created = sys.argv[1:7]
try:
    with open(path, "r", encoding="utf-8-sig") as f:
        data = json.load(f)
    if not isinstance(data, list):
        data = [data] if data else []
except Exception:
    data = []

data.append({
    "alias": alias,
    "userName": uname,
    "userEmail": uemail,
    "keyPath": kpath,
    "created": created,
})

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

update_repo_url() {
    local alias_name="$1"

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 0
    fi

    local current_url
    current_url="$(git remote get-url origin 2>/dev/null || true)"
    if [ -z "$current_url" ]; then
        return 0
    fi

    printf "\n"
    write_color "$C_CYAN" "  [INFO] Checking Repository URL..."

    local new_url
    new_url="$(python3 - "$current_url" "$alias_name" <<'PY'
import re, sys

url, alias = sys.argv[1], sys.argv[2]
new_host = f"github.com-{alias}"
new_url = ""

patterns = [
    r"^https://github\.com/(.+)$",
    r"^git@github\.com:(.+)$",
    r"^git@github\.com-[^:]+:(.+)$",
]
for pat in patterns:
    m = re.match(pat, url)
    if m:
        new_url = f"git@{new_host}:{m.group(1)}"
        break

print(new_url)
PY
)"

    if [ -n "$new_url" ] && [ "$new_url" != "$current_url" ]; then
        git remote set-url origin "$new_url"
        write_color "$C_GREEN" "  [✔] Updated Remote URL to: ${new_url}"
    else
        write_color "$C_GRAY" "  [INFO] Remote URL is already correct or not hosted on GitHub."
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

    if [ -z "$selected_key" ]; then
        write_color "$C_YELLOW" "  [!] Profile '${selected_alias}' does not have an SSH key recorded."
        return
    fi

    test_github_connection "$selected_alias" || true
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

    local u_name u_email
    read -r -p "   Enter Git User Name (e.g. John Doe): " u_name
    read -r -p "   Enter Git Email     (e.g. john@company.com): " u_email

    if [ -z "$u_name" ] || [ -z "$u_email" ]; then
        write_color "$C_RED" "   [!] Name and Email are required."
        return
    fi

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
    write_color "$C_GRAY" "   2. Click 'New SSH Key'."
    write_color "$C_GRAY" "   3. Paste (${paste_shortcut}) the key into the box."
    write_color "$C_GRAY" "   4. Come back here and press ENTER."

    sleep 2
    open_target "https://github.com/settings/ssh/new" || true

    printf "\n"
    read -r -p "   Press ENTER after you have added the key on GitHub..." _

    # 5. Test Connection
    test_github_connection "$alias_name" || true

    # 6. Save Profile
    profile_add_json "$alias_name" "$u_name" "$u_email" "$key_path"
    printf "\n"
    write_color "$C_GREEN" "   [✔] Profile '${alias_name}' saved successfully!"

    # Auto-set Global Config if currently unset
    local curr_name
    curr_name="$(get_git_current_name)"
    if [ "$curr_name" = "Not Set" ]; then
        sync_git_identity "$u_name" "$u_email" "$key_path"
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

    local selected_alias selected_name selected_email selected_key
    selected_alias="$(profile_get_field "$idx" "alias")"
    selected_name="$(profile_get_field "$idx" "userName")"
    selected_email="$(profile_get_field "$idx" "userEmail")"
    selected_key="$(profile_get_field "$idx" "keyPath")"

    printf "\n"
    write_color "$C_CYAN" "   [INFO] Switching to '${selected_alias}'..."

    # 1. Change Global & Local Config (+ SSH Signing Key if enabled)
    sync_git_identity "$selected_name" "$selected_email" "$selected_key"

    # 2. Update Repo URL (Local Override)
    update_repo_url "$selected_alias"

    # 3. Test SSH
    if [ -n "$selected_key" ]; then
        test_github_connection "$selected_alias" || true
    fi

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

    # 2. Remove from SSH Config
    remove_from_ssh_config "$removed_alias"

    # 3. Remove from JSON
    profile_remove_json "$removed_alias"

    # 4. Check & Clear Global/Local Config and Signing Key
    local curr_name curr_email curr_skey
    curr_name="$(get_git_current_name)"
    curr_email="$(get_git_current_email)"
    if [ "$curr_name" = "$removed_name" ] || [ "$curr_email" = "$removed_email" ]; then
        git config --global --unset user.name 2>/dev/null || true
        git config --global --unset user.email 2>/dev/null || true
        write_color "$C_CYAN" "   [INFO] Current Global Git config cleared because profile was removed."
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

    write_color "$C_WHITE" "   » GIT PROFILE MANAGEMENT SYSTEM [v2.1 - ${os_label}]"
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
