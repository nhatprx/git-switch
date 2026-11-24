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
- **SSH Auto-Generation:** Automatically creates SSH key pairs, configures `~/.ssh/config` (with macOS Keychain support), and registers with `ssh-agent`.
- **Smart Clipboard:** Auto-copies public keys (`pbcopy` on macOS, `Set-Clipboard` on Windows) and opens GitHub SSH settings page for seamless key addition.
- **Remote URL Sync:** Automatically updates repository remote URLs to match the active profile's SSH host alias.
- **Isolated Identities:** Complete separation between Work, Personal, and any custom profiles.
- **Beautiful UI:** Clean, intuitive interface with color-coded status indicators and box-drawing characters.

## Quick Start (Run without installing)

### macOS / Linux
```bash
curl -fsSL https://raw.githubusercontent.com/nhatprx/git-switch/master/install.sh | bash
```
Or run locally after cloning:
```bash
chmod +x git.sh
./git.sh
```

### Windows (PowerShell)
```powershell
iwr -useb https://raw.githubusercontent.com/nhatprx/git-switch/master/install.ps1 | iex
```
**Backup:** Universal Command (If Option 1 fails / For older Windows)  
Use this if you see SSL/TLS errors or Policy restrictions.
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/nhatprx/git-switch/master/install.ps1'))
```
