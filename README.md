# Git Profile Manager (Windows & macOS / Linux)
> A lightweight, powerful CLI utility to manage multiple Git identities and SSH keys instantly.
> **No more commit identity mistakes.**

![macOS](https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-%235391FE.svg?style=for-the-badge&logo=powershell&logoColor=white)
![Git](https://img.shields.io/badge/git-%23F05033.svg?style=for-the-badge&logo=git&logoColor=white)
![GitHub](https://img.shields.io/badge/github-%23121011.svg?style=for-the-badge&logo=github&logoColor=white)

## Features

- **Cross-Platform:** Native Bash support for **macOS / Linux** (`git.sh`) and PowerShell support for **Windows** (`git.ps1`).
- **Instant Switching:** Changes Git identity (`user.name`, `user.email`) and SSH keys immediately for both global and local repositories.
- **SSH Auto-Generation & Commit Signing:** Automatically creates SSH key pairs, configures `~/.ssh/config` (with macOS Keychain support), registers with `ssh-agent`, and syncs SSH commit signing keys.
- **HTTPS Credential Swap (PAT / Keychain / `gh`):** Securely stores per-profile GitHub Personal Access Tokens (`chmod 600` outside `profiles.json`), swaps or clears cached `github.com` HTTPS credentials in `osxkeychain` / Git credential helper on switch, and switches `gh` CLI accounts when installed.
- **Remote HTTPS vs SSH Detection:** Automatically detects whether `origin` uses HTTPS (which bypasses `~/.ssh/config`) or SSH, warns on the status banner, and prompts to convert HTTPS remotes to the profile's SSH alias (`git@github.com-<alias>:...`).
- **IDE Git Auth Sync (VS Code / Cursor / Antigravity):** Detects IDE `settings.json` and helps disable `"github.gitAuthentication": false` so IDE UI Push/Pull uses `git-switch` credentials instead of a separate IDE OAuth session.
- **Smart Clipboard:** Auto-copies public keys (`pbcopy` on macOS, `Set-Clipboard` on Windows) and opens GitHub SSH settings page for seamless key addition.
- **Isolated Identities:** Complete separation between Work, Personal, and any custom profiles.
- **Beautiful UI:** Clean, intuitive interface with color-coded status indicators and box-drawing characters.

## Quick Start

Install globally via npm (works on **macOS, Linux, and Windows**):
```bash
npm install -g @nhatprx/gitswitch
```

Then run inside any project directory:
```bash
gitswitch
```

Or run directly without installing:
```bash
npx @nhatprx/gitswitch
```
