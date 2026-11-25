# ==============================================================================
# GIT PROFILE MANAGER - ULTIMATE EDITION (NATIVE POWERSHELL)
# Version: 2.2 (Cross-Platform PowerShell)
# Author: nhatprx
# Features: SSH Auto-Gen, HTTPS PAT Swap, Remote Sync, IDE Auth Sync
# ==============================================================================

# -------------------------- CONFIGURATION --------------------------
$IsWinOS = ($env:OS -eq "Windows_NT") -or ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
$HomeDir = if ($IsWinOS -and $env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$BaseDir = Join-Path $HomeDir ".git-switch"
$ProfilesFile = Join-Path $BaseDir "profiles.json"
$TokensDir = Join-Path $BaseDir "tokens"
$SSHDir = Join-Path $HomeDir ".ssh"
$SSHConfigFile = Join-Path $SSHDir "config"

function Wait-KeyPress {
    Read-Host "Press Enter to continue..." | Out-Null
}

function Open-Target {
    param([string]$Target)
    if ($IsWinOS) {
        Start-Process $Target
    } elseif ($IsMacOS) {
        & open $Target
    } else {
        & xdg-open $Target
    }
}

function Copy-TextToClipboard {
    param([string]$Text)
    if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
        Set-Clipboard -Value $Text
    } elseif ($IsMacOS -and (Get-Command pbcopy -ErrorAction SilentlyContinue)) {
        $Text | & pbcopy
    } else {
        throw "No clipboard utility available."
    }
}


# -------------------------- HELPER: UI & BOX DRAWING --------------------------
# -------------------------- HELPER: UI & BOX DRAWING --------------------------
function Write-Color {
    param([string]$Text, [ConsoleColor]$Color = "White", [switch]$NoNewLine)
    if ($NoNewLine) { Write-Host $Text -ForegroundColor $Color -NoNewline }
    else { Write-Host $Text -ForegroundColor $Color }
}

# Đổi sang nét đơn (┌ ─ ┐) giống JDK-Switch để không bị lỗi ?????
function Draw-Border-Top {
    param([int]$Width = 60, [ConsoleColor]$Color = "Cyan")
    Write-Color ("┌" + ("─" * $Width) + "┐") -Color $Color
}

function Draw-Border-Bottom {
    param([int]$Width = 60, [ConsoleColor]$Color = "Cyan")
    Write-Color ("└" + ("─" * $Width) + "┘") -Color $Color
}

function Draw-Line {
    param([string]$Text, [int]$Width = 60, [ConsoleColor]$Color = "Cyan", [ConsoleColor]$TextColor = "White")
    $Content = " $Text "
    $PadRight = $Width - $Content.Length
    if ($PadRight -lt 0) { $PadRight = 0 }
    Write-Color "│" -Color $Color -NoNewLine
    Write-Color $Content -Color $TextColor -NoNewLine
    Write-Color (" " * $PadRight) -NoNewLine
    Write-Color "│" -Color $Color
}

function Draw-Separator {
    param([int]$Width = 60, [ConsoleColor]$Color = "Cyan")
    Write-Color ("├" + ("─" * $Width) + "┤") -Color $Color
}

function Draw-Sep {
    Write-Host " ──────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
}

function Draw-Header {
    param([string]$Title)
    Draw-Sep
    Write-Host "   » $Title" -ForegroundColor Cyan
    Draw-Sep
}

# -------------------------- CORE LOGIC (PORTED FROM PYTHON) --------------------------


function Initialize-System {
    # Logic tạo file config an toàn kiểu JDK-Switch
    if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null }
    
    # Tạo file json rỗng chuẩn UTF8 (có BOM hoặc không BOM tùy PowerShell tự quyết)
    if (-not (Test-Path $ProfilesFile)) { 
        @() | ConvertTo-Json | Set-Content $ProfilesFile -Encoding UTF8 
    }
    if (-not (Test-Path $TokensDir)) { New-Item -ItemType Directory -Path $TokensDir -Force | Out-Null }

    if (-not (Test-Path $SSHDir)) { New-Item -ItemType Directory -Path $SSHDir -Force | Out-Null }
    if (-not (Test-Path $SSHConfigFile)) { New-Item -ItemType File -Path $SSHConfigFile -Force | Out-Null }
}

function Load-Profiles {
    Initialize-System
    try {
        $Content = Get-Content $ProfilesFile -Raw -Encoding UTF8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($Content)) { return @() }
        $Data = $Content | ConvertFrom-Json
        if ($Data -is [System.Array]) { return $Data }
        if ($null -eq $Data) { return @() }
        return @($Data)
    } catch {
        return @()
    }
}

function Save-Profiles($Data) {
    if ($Data -isnot [System.Array]) { $Data = @($Data) }
    $Data | ConvertTo-Json -Depth 5 | Set-Content $ProfilesFile -Encoding UTF8
}

function Get-Git-Current {
    try {
        $Name = git config --global user.name
        $Email = git config --global user.email
        if (-not $Name) { $Name = "Not Set" }
        if (-not $Email) { $Email = "Not Set" }
        return @{ Name = $Name; Email = $Email }
    } catch {
        return @{ Name = "Git Not Found"; Email = "Check Install" }
    }
}

function Test-InsideGitRepo {
    $res = git rev-parse --is-inside-work-tree 2>$null
    return ($LASTEXITCODE -eq 0 -and $res -eq "true")
}

function Test-CommitSigningEnabled {
    $gSign = git config --global commit.gpgsign 2>$null
    $lSign = if (Test-InsideGitRepo) { git config --local commit.gpgsign 2>$null } else { $null }
    return ($gSign -eq "true" -or $lSign -eq "true")
}

function Sync-Git-Identity {
    param([string]$UserName, [string]$UserEmail, [string]$KeyPath)

    # 1. Global identity
    git config --global user.name "$UserName"
    git config --global user.email "$UserEmail"

    # 2. Local repo identity (prevents stale .git/config from overriding global)
    $inRepo = Test-InsideGitRepo
    if ($inRepo) {
        git config --local user.name "$UserName"
        git config --local user.email "$UserEmail"
        Write-Color "   [✔] Synced local repo user.name & user.email (.git/config)." -Color Green

        $localSshCmd = git config --local core.sshCommand 2>$null
        if (-not [string]::IsNullOrWhiteSpace($localSshCmd)) {
            Write-Color "   [!] Local core.sshCommand is set ($localSshCmd) and may override ~/.ssh/config." -Color Yellow
        }
    }

    # 3. Auto-enable & sync SSH commit signing unless user explicitly disabled it (commit.gpgsign = false)
    if ($KeyPath -and (Test-Path "$KeyPath.pub")) {
        $pubKey = "$KeyPath.pub"
        $gSign = git config --global commit.gpgsign 2>$null
        $lSign = if ($inRepo) { git config --local commit.gpgsign 2>$null } else { $null }
        if ($gSign -ne "false" -and $lSign -ne "false") {
            git config --global gpg.format ssh
            git config --global user.signingkey "$pubKey"
            git config --global commit.gpgsign true
            if ($inRepo) {
                git config --local gpg.format ssh
                git config --local user.signingkey "$pubKey"
                git config --local commit.gpgsign true
            }
            Write-Color "   [✔] SSH Commit Signing active: $pubKey" -Color Green
        }
    }
}

function Invoke-FixUnpushedCommits {
    param([string]$TargetName, [string]$TargetEmail)

    if (-not (Test-InsideGitRepo)) { return }
    git rev-parse --verify HEAD 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { return }

    $hasUpstream = $false
    $rangeArgs = @()
    $totalUnpushed = 0

    git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $hasUpstream = $true
        $rangeArgs = @('@{u}..HEAD')
        $totalUnpushed = [int](git rev-list --count '@{u}..HEAD' 2>$null)
    } else {
        $rangeArgs = @('HEAD', '--not', '--remotes')
        $totalUnpushed = [int](git rev-list --count HEAD --not --remotes 2>$null)
    }

    if ($totalUnpushed -le 0) { return }

    $signingOn = Test-CommitSigningEnabled
    $mismatchCount = 0
    $logLines = @(git log --format="%H|%ae|%G?" @rangeArgs 2>$null)
    foreach ($line in $logLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split '\|', 3
        if ($parts.Count -lt 3) { continue }
        if ($parts[1] -ne $TargetEmail) {
            $mismatchCount++
        } elseif ($signingOn -and $parts[2] -eq "N") {
            $mismatchCount++
        }
    }

    if ($mismatchCount -eq 0) { return }

    Write-Color "`n   [!] Found $mismatchCount unpushed commit(s) with different author or missing SSH signature." -Color Yellow
    $doFix = Read-Host "   Update author to '$TargetName <$TargetEmail>' & re-sign before push? [Y/n]"
    if ($doFix -match '^(n|no)$') {
        Write-Color "   [INFO] Left unpushed commit(s) unchanged." -Color Gray
        return
    }

    $mergeCount = [int](git rev-list --merges --count @rangeArgs 2>$null)
    if ($mergeCount -gt 0) {
        Write-Color "   [!] Unpushed range contains merge commit(s). Skipping auto-rewrite to keep history safe." -Color Yellow
        return
    }

    if ($totalUnpushed -eq 1) {
        git diff --cached --quiet 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Color "   [!] You have staged changes. Commit or unstage them before amending HEAD." -Color Yellow
            return
        }
        $amendArgs = @("commit", "--amend", "--reset-author", "--no-edit")
        if ($signingOn) { $amendArgs += "-S" }
        & git @amendArgs 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Color "   [✔] Updated author & re-signed the unpushed commit!" -Color Green
        } else {
            Write-Color "   [X] Failed to amend unpushed commit." -Color Red
        }
    } else {
        $dirty = git status --porcelain 2>$null
        if (-not [string]::IsNullOrWhiteSpace(($dirty | Out-String))) {
            Write-Color "   [!] Working tree has uncommitted changes. Stash/commit them before rewriting $totalUnpushed commits." -Color Yellow
            return
        }
        $execCmd = if ($signingOn) { "git commit --amend --reset-author --no-edit -S" } else { "git commit --amend --reset-author --no-edit" }
        if ($hasUpstream) {
            & git rebase --exec "$execCmd" '@{u}' 2>$null | Out-Null
        } else {
            & git rebase --root --exec "$execCmd" 2>$null | Out-Null
        }
        if ($LASTEXITCODE -eq 0) {
            Write-Color "   [✔] Updated author & re-signed $totalUnpushed unpushed commit(s)!" -Color Green
        } else {
            git rebase --abort 2>$null | Out-Null
            Write-Color "   [X] Could not rewrite unpushed commits cleanly (aborted safely)." -Color Red
        }
    }
}

# --- SSH LOGIC ---

function Generate-SSH-Key {
    param($Email, $Alias)
    
    $KeyPath = Join-Path $SSHDir "id_rsa_$Alias"
    
    if (Test-Path $KeyPath) {
        Write-Color "  [!] SSH Key already exists for this alias. Using existing key." -Color Yellow
        return $KeyPath
    }

    Write-Color "  [INFO] Generating new SSH Key..." -Color Cyan
    
    # Gọi ssh-keygen, passphase rỗng (-N "") để tự động hóa
    try {
        if ($IsWinOS) {
            # FIX: Dùng '""' (bao quanh bởi nháy đơn) để Windows PowerShell truyền đúng chuỗi rỗng cho ssh-keygen
            & ssh-keygen -t rsa -b 4096 -C "$Email" -f "$KeyPath" -N '""' | Out-Null
        } else {
            & ssh-keygen -t rsa -b 4096 -C "$Email" -f "$KeyPath" -N "" | Out-Null
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Color "  [✔] SSH Key generated successfully." -Color Green
            return $KeyPath
        } else {
            throw "ssh-keygen failed."
        }
    } catch {
        Write-Color "  [X] Failed to generate SSH Key. Ensure OpenSSH is installed." -Color Red
        return $null
    }
}

function Update-SSH-Config {
    param($Alias, $KeyPath)
    
    # Định dạng block config giống logic Python
    # Host ảo sẽ là: github.com-<alias>
    $ConfigBlock = @"

# Git profile: $Alias
Host github.com-$Alias
    HostName github.com
    User git
    IdentityFile $KeyPath
    IdentitiesOnly yes
"@
    
    try {
        Add-Content -Path $SSHConfigFile -Value $ConfigBlock -Encoding UTF8
        Write-Color "  [✔] SSH Config updated (Host: github.com-$Alias)." -Color Green
    } catch {
        Write-Color "  [X] Failed to update .ssh/config." -Color Red
    }
}

function Remove-From-SSH-Config {
    param($Alias)
    
    if (-not (Test-Path $SSHConfigFile)) { return }
    
    try {
        # Đọc toàn bộ dòng
        $Lines = Get-Content $SSHConfigFile -Encoding UTF8
        $NewLines = @()
        $Skip = $false
        
        foreach ($Line in $Lines) {
            # Tìm dòng bắt đầu comment profile
            if ($Line -match "# Git profile: $Alias") {
                $Skip = $true
                continue
            }
            
            # Nếu đang skip mà gặp dòng trống (hết block) hoặc block mới -> dừng skip
            if ($Skip -and ($Line.Trim() -eq "" -or $Line -match "^Host ")) {
                 # Nếu gặp Host khác ngay lập tức thì giữ lại, nếu dòng trống thì bỏ qua 1 dòng trống
                 if ($Line -match "^Host ") { $Skip = $false }
            }
            
            # Logic đơn giản hóa: Block kết thúc bằng dòng trống hoặc Host tiếp theo
            # Logic Python: Remove lines until next empty line or next header
            if ($Skip) {
                if ([string]::IsNullOrWhiteSpace($Line)) { $Skip = $false }
            } else {
                $NewLines += $Line
            }
        }
        
        $NewLines | Set-Content $SSHConfigFile -Encoding UTF8
        Write-Color "  [✔] Removed entry from SSH Config." -Color Green
    } catch {
        Write-Color "  [!] Error cleaning SSH Config." -Color Yellow
    }
}

# --- HTTPS CREDENTIAL SWAP ---

function Get-TokenFilePath {
    param([string]$Alias)
    return (Join-Path $TokensDir "$Alias.token")
}

function Test-ProfileHasToken {
    param([string]$Alias)
    if ([string]::IsNullOrWhiteSpace($Alias)) { return $false }
    $path = Get-TokenFilePath -Alias $Alias
    return ((Test-Path $path) -and ((Get-Item $path).Length -gt 0))
}

function Save-ProfileToken {
    param([string]$Alias, [string]$Token)
    if ([string]::IsNullOrWhiteSpace($Alias) -or [string]::IsNullOrWhiteSpace($Token)) { return }
    if (-not (Test-Path $TokensDir)) { New-Item -ItemType Directory -Path $TokensDir -Force | Out-Null }
    $path = Get-TokenFilePath -Alias $Alias
    [System.IO.File]::WriteAllText($path, $Token.Trim(), [System.Text.UTF8Encoding]::new($false))
    if (-not $IsWinOS) {
        & chmod 700 $TokensDir 2>$null
        & chmod 600 $path 2>$null
    }
}

function Get-ProfileToken {
    param([string]$Alias)
    $path = Get-TokenFilePath -Alias $Alias
    if (Test-Path $path) {
        return (Get-Content $path -Raw -Encoding UTF8).Trim()
    }
    return $null
}

function Remove-ProfileToken {
    param([string]$Alias)
    $path = Get-TokenFilePath -Alias $Alias
    if (Test-Path $path) { Remove-Item $path -Force -ErrorAction SilentlyContinue }
}

function Test-ActiveGitCredentialHelper {
    $active = ""
    foreach ($line in @(git config --get-all credential.helper 2>$null)) {
        if ([string]::IsNullOrWhiteSpace($line)) { $active = "" } else { $active = $line }
    }
    if ([string]::IsNullOrWhiteSpace($active)) {
        foreach ($line in @(git config --get-all credential.https://github.com.helper 2>$null)) {
            if ([string]::IsNullOrWhiteSpace($line)) { $active = "" } else { $active = $line }
        }
    }
    return (-not [string]::IsNullOrWhiteSpace($active))
}

function Clear-GitHubHttpsCredential {
    $payload = "protocol=https`nhost=github.com`n`n"
    try { $payload | & git credential reject 2>$null | Out-Null } catch {}
}

function Set-GitHubHttpsCredential {
    param([string]$GitHubUser, [string]$Token)
    if ([string]::IsNullOrWhiteSpace($GitHubUser) -or [string]::IsNullOrWhiteSpace($Token)) { return "error" }
    if (-not (Test-ActiveGitCredentialHelper)) { return "no_helper" }
    Clear-GitHubHttpsCredential
    $payload = "protocol=https`nhost=github.com`nusername=$GitHubUser`npassword=$Token`n`n"
    try {
        $payload | & git credential approve 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return "ok" }
        return "error"
    } catch {
        return "error"
    }
}

function Sync-HttpsCredentials {
    param([string]$Alias, [string]$GitHubUser, [string]$FallbackUser)
    $effectiveUser = if (-not [string]::IsNullOrWhiteSpace($GitHubUser)) { $GitHubUser } else { $FallbackUser }

    if (Test-ProfileHasToken -Alias $Alias) {
        $pat = Get-ProfileToken -Alias $Alias
        if ($pat -and $effectiveUser) {
            $res = Set-GitHubHttpsCredential -GitHubUser $effectiveUser -Token $pat
            if ($res -eq "ok") {
                Write-Color "   [✔] Swapped HTTPS credential for github.com (user: $effectiveUser)." -Color Green
            } elseif ($res -eq "no_helper") {
                $hintHelper = if ($IsWinOS) { "manager" } elseif ($IsMacOS) { "osxkeychain" } else { "store" }
                Write-Color "   [!] No Git credential.helper configured. Run: git config --global credential.helper $hintHelper" -Color Yellow
            } else {
                Write-Color "   [!] Could not write HTTPS credential to Git credential helper." -Color Yellow
            }
        }
    } else {
        Clear-GitHubHttpsCredential
        Write-Color "   [INFO] Cleared cached HTTPS credential for github.com (no PAT saved for '$Alias')." -Color Gray
    }

    if (-not [string]::IsNullOrWhiteSpace($GitHubUser) -and (Get-Command gh -ErrorAction SilentlyContinue)) {
        try {
            & gh auth switch --user $GitHubUser 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Color "   [✔] Switched GitHub CLI (gh) account to: $GitHubUser" -Color Green
            }
        } catch {}
    }
}

function Test-GitHubHttpsConnection {
    param([string]$Alias)
    if (-not (Test-ProfileHasToken -Alias $Alias)) { return $false }
    $pat = Get-ProfileToken -Alias $Alias
    Write-Color "   [INFO] Testing HTTPS PAT for '$Alias'..." -Color Cyan
    try {
        if ($IsWinOS) {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        }
        $headers = @{
            Authorization = "Bearer $pat"
            Accept        = "application/vnd.github+json"
            "User-Agent"  = "git-switch"
        }
        $resp = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -TimeoutSec 10 -ErrorAction Stop
        if ($resp.login) {
            Write-Color "   [✔] HTTPS PAT SUCCESS! Authenticated as: $($resp.login)" -Color Green
            return $true
        }
    } catch {}
    Write-Color "   [X] HTTPS PAT FAILED (invalid/expired token or network error)." -Color Red
    return $false
}

# --- REMOTE DETECTION & SYNC ---

function Get-GitHubRemoteInfo {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return @{ Type = "other"; RepoPath = ""; SshAlias = "" } }
    $u = $Url.Trim()
    if ($u -match "^https?://(?:[^/@]+@)?github\.com(?::\d+)?/(.+)$") {
        return @{ Type = "https"; RepoPath = $Matches[1].TrimEnd('/'); SshAlias = "" }
    }
    if ($u -match "^git@github\.com:(.+)$") {
        return @{ Type = "ssh_default"; RepoPath = $Matches[1].TrimEnd('/'); SshAlias = "" }
    }
    if ($u -match "^ssh://git@github\.com(?::\d+)?/(.+)$") {
        return @{ Type = "ssh_default"; RepoPath = $Matches[1].TrimEnd('/'); SshAlias = "" }
    }
    if ($u -match "^git@github\.com-([^:/]+):(.+)$") {
        return @{ Type = "ssh_alias"; RepoPath = $Matches[2].TrimEnd('/'); SshAlias = $Matches[1] }
    }
    if ($u -match "^ssh://git@github\.com-([^:/]+)(?::\d+)?/(.+)$") {
        return @{ Type = "ssh_alias"; RepoPath = $Matches[2].TrimEnd('/'); SshAlias = $Matches[1] }
    }
    return @{ Type = "other"; RepoPath = ""; SshAlias = "" }
}

function Update-Repo-Url {
    param([string]$Alias, [string]$Mode = "prompt")
    if (-not (Test-InsideGitRepo)) { return }

    $CurrentUrl = git remote get-url origin 2>$null
    if (-not $CurrentUrl) { return }

    Write-Color "`n   [INFO] Checking Repository Remote URL..." -Color Cyan

    $info = Get-GitHubRemoteInfo -Url $CurrentUrl
    $targetSshUrl = "git@github.com-$Alias`:$($info.RepoPath)"

    switch ($info.Type) {
        "https" {
            Write-Color "   [!] Detected HTTPS remote: $CurrentUrl" -Color Yellow
            Write-Color "       SSH keys (~/.ssh/config) are ignored for HTTPS remotes." -Color Gray
            $doConvert = "y"
            if ($Mode -ne "auto") {
                $doConvert = Read-Host "   Convert remote to SSH alias ($targetSshUrl)? [Y/n]"
            }
            if ($doConvert -match "^(n|no)$") {
                Write-Color "   [INFO] Keeping HTTPS remote." -Color Gray
                if (-not (Test-ProfileHasToken -Alias $Alias)) {
                    Write-Color "   [!] No HTTPS PAT saved for '$Alias'. Add one in Settings -> [5] Manage HTTPS Credentials." -Color Yellow
                }
            } else {
                git remote set-url origin $targetSshUrl
                Write-Color "   [✔] Converted HTTPS remote -> SSH alias: $targetSshUrl" -Color Green
            }
        }
        { $_ -in @("ssh_default", "ssh_alias") } {
            if ($targetSshUrl -ne $CurrentUrl) {
                git remote set-url origin $targetSshUrl
                Write-Color "   [✔] Updated SSH Remote URL to: $targetSshUrl" -Color Green
            } else {
                Write-Color "   [INFO] Remote URL already uses SSH alias: $CurrentUrl" -Color Gray
            }
        }
        default {
            Write-Color "   [INFO] Remote URL is not hosted on GitHub ($CurrentUrl)." -Color Gray
        }
    }
}

# --- IDE GIT AUTH SYNC ---

function Get-IdeSettingsPaths {
    $candidates = @()
    if ($IsWinOS -and $env:APPDATA) {
        $candidates = @(
            @{ Name = "VS Code";          Path = Join-Path $env:APPDATA "Code\User\settings.json" }
            @{ Name = "VS Code Insiders"; Path = Join-Path $env:APPDATA "Code - Insiders\User\settings.json" }
            @{ Name = "Cursor";           Path = Join-Path $env:APPDATA "Cursor\User\settings.json" }
            @{ Name = "Antigravity";      Path = Join-Path $env:APPDATA "Antigravity\User\settings.json" }
            @{ Name = "Windsurf";         Path = Join-Path $env:APPDATA "Windsurf\User\settings.json" }
        )
    } elseif ($IsMacOS) {
        $appSup = Join-Path $HomeDir "Library/Application Support"
        $candidates = @(
            @{ Name = "VS Code";          Path = Join-Path $appSup "Code/User/settings.json" }
            @{ Name = "VS Code Insiders"; Path = Join-Path $appSup "Code - Insiders/User/settings.json" }
            @{ Name = "Cursor";           Path = Join-Path $appSup "Cursor/User/settings.json" }
            @{ Name = "Antigravity";      Path = Join-Path $appSup "Antigravity/User/settings.json" }
            @{ Name = "Windsurf";         Path = Join-Path $appSup "Windsurf/User/settings.json" }
        )
    } else {
        $cfg = Join-Path $HomeDir ".config"
        $candidates = @(
            @{ Name = "VS Code";          Path = Join-Path $cfg "Code/User/settings.json" }
            @{ Name = "VS Code Insiders"; Path = Join-Path $cfg "Code - Insiders/User/settings.json" }
            @{ Name = "Cursor";           Path = Join-Path $cfg "Cursor/User/settings.json" }
            @{ Name = "Antigravity";      Path = Join-Path $cfg "Antigravity/User/settings.json" }
            @{ Name = "Windsurf";         Path = Join-Path $cfg "Windsurf/User/settings.json" }
        )
    }

    $found = @()
    foreach ($c in $candidates) {
        $parent = Split-Path $c.Path -Parent
        if ((Test-Path $c.Path) -or (Test-Path $parent)) {
            $found += $c
        }
    }
    return $found
}

function ConvertTo-JsoncMasked {
    param([string]$Text)
    $chars = $Text.ToCharArray()
    $n = $chars.Length
    $i = 0
    $inStr = $false
    while ($i -lt $n) {
        $c = $chars[$i]
        if ($inStr) {
            if ($c -eq '\' -and ($i + 1) -lt $n) {
                $i += 2
                continue
            } elseif ($c -eq '"') {
                $inStr = $false
            }
            $i++
        } else {
            if ($c -eq '"') {
                $inStr = $true
                $i++
            } elseif ($c -eq '/' -and ($i + 1) -lt $n -and $chars[$i + 1] -eq '/') {
                $chars[$i] = ' '
                $chars[$i + 1] = ' '
                $i += 2
                while ($i -lt $n -and $chars[$i] -ne "`n" -and $chars[$i] -ne "`r") {
                    $chars[$i] = ' '
                    $i++
                }
            } elseif ($c -eq '/' -and ($i + 1) -lt $n -and $chars[$i + 1] -eq '*') {
                $chars[$i] = ' '
                $chars[$i + 1] = ' '
                $i += 2
                while (($i + 1) -lt $n -and -not ($chars[$i] -eq '*' -and $chars[$i + 1] -eq '/')) {
                    if ($chars[$i] -ne "`n" -and $chars[$i] -ne "`r") { $chars[$i] = ' ' }
                    $i++
                }
                if (($i + 1) -lt $n) {
                    $chars[$i] = ' '
                    $chars[$i + 1] = ' '
                    $i += 2
                } else {
                    if ($i -lt $n -and $chars[$i] -ne "`n" -and $chars[$i] -ne "`r") { $chars[$i] = ' ' }
                    $i++
                }
            } else {
                $i++
            }
        }
    }
    return (-join $chars)
}

function Find-IdeJsoncRootAndKey {
    param([string]$Masked)
    $depth = 0
    $inStr = $false
    $rootClose = -1
    $keyValStart = -1
    $keyValLen = 0
    $keyValText = $null
    $n = $Masked.Length
    $i = 0
    $keyRegex = [regex]'\G"github\.gitAuthentication"\s*:\s*(true|false)'

    while ($i -lt $n) {
        $c = $Masked[$i]
        if ($inStr) {
            if ($c -eq '\' -and ($i + 1) -lt $n) {
                $i += 2
                continue
            } elseif ($c -eq '"') {
                $inStr = $false
            }
            $i++
        } else {
            if ($c -eq '"') {
                if ($depth -eq 1 -and $keyValStart -lt 0) {
                    $m = $keyRegex.Match($Masked, $i)
                    if ($m.Success) {
                        $keyValStart = $m.Groups[1].Index
                        $keyValLen = $m.Groups[1].Length
                        $keyValText = $m.Groups[1].Value.ToLower()
                        $i = $m.Index + $m.Length
                        continue
                    }
                }
                $inStr = $true
                $i++
            } elseif ($c -eq '{') {
                $depth++
                $i++
            } elseif ($c -eq '}') {
                $depth--
                if ($depth -eq 0) {
                    $rootClose = $i
                    break
                }
                $i++
            } else {
                $i++
            }
        }
    }

    return @{
        RootClose   = $rootClose
        KeyValStart = $keyValStart
        KeyValLen   = $keyValLen
        KeyValText  = $keyValText
    }
}

function Get-IdeGitAuthSetting {
    param([string]$SettingsPath)
    if (-not (Test-Path $SettingsPath)) { return "unset" }
    try {
        $raw = Get-Content $SettingsPath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return "unset" }
        $masked = ConvertTo-JsoncMasked -Text $raw
        $scan = Find-IdeJsoncRootAndKey -Masked $masked
        if ($scan.RootClose -lt 0) { return "error" }
        if ($scan.KeyValText) { return $scan.KeyValText }
        return "unset"
    } catch {
        return "error"
    }
}

function Set-IdeGitAuthSetting {
    param([string]$SettingsPath, [string]$Desired = "false")
    $val = if ($Desired.ToLower() -eq "false") { "false" } else { "true" }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    try {
        $parent = Split-Path $SettingsPath -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        if (-not (Test-Path $SettingsPath)) {
            [System.IO.File]::WriteAllText($SettingsPath, "{`n  `"github.gitAuthentication`": $val`n}`n", $utf8NoBom)
            return $true
        }
        $raw = Get-Content $SettingsPath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            [System.IO.File]::WriteAllText($SettingsPath, "{`n  `"github.gitAuthentication`": $val`n}`n", $utf8NoBom)
            return $true
        }
        $masked = ConvertTo-JsoncMasked -Text $raw
        $scan = Find-IdeJsoncRootAndKey -Masked $masked
        if ($scan.KeyValStart -ge 0) {
            $updated = $raw.Substring(0, $scan.KeyValStart) + $val + $raw.Substring($scan.KeyValStart + $scan.KeyValLen)
        } else {
            $rootClose = $scan.RootClose
            if ($rootClose -lt 0) { return $false }
            $j = $rootClose - 1
            while ($j -ge 0 -and [char]::IsWhiteSpace($masked[$j])) { $j-- }
            if ($j -lt 0) { return $false }
            $needsComma = ($masked[$j] -ne '{') -and ($masked[$j] -ne ',')
            if ($needsComma) {
                $beforeBrace = $raw.Substring(0, $j + 1) + "," + $raw.Substring($j + 1, $rootClose - ($j + 1))
            } else {
                $beforeBrace = $raw.Substring(0, $rootClose)
            }
            $sep = if ($beforeBrace.EndsWith("`n")) { "" } else { "`n" }
            $updated = "$beforeBrace$sep  `"github.gitAuthentication`": $val`n$($raw.Substring($rootClose))"
        }
        [System.IO.File]::WriteAllText($SettingsPath, $updated, $utf8NoBom)
        return $true
    } catch {
        return $false
    }
}

function Show-IdeSyncHint {
    param([string]$Mode = "hint")

    $ides = @(Get-IdeSettingsPaths)
    $needHint = $false
    $pendingIdes = @()
    $ideNames = @()
    foreach ($ide in $ides) {
        $st = Get-IdeGitAuthSetting -SettingsPath $ide.Path
        if ($st -ne "false") {
            $needHint = $true
            $pendingIdes += $ide
            $ideNames += $ide.Name
        }
    }
    if (-not $needHint -and $ides.Count -eq 0 -and (Test-InsideGitRepo)) {
        $originUrl = git remote get-url origin 2>$null
        if ($originUrl) {
            $info = Get-GitHubRemoteInfo -Url $originUrl
            if ($info.Type -eq "https") {
                $needHint = $true
                $ideNames = @("VS Code", "Cursor", "Antigravity")
            }
        }
    }
    if ($needHint) {
        $list = $ideNames -join ", "
        Write-Color "`n   [TIP] IDE Sync ($list):" -Color Yellow
        Write-Color "         IDE GitHub extension uses its own OAuth session for UI Push/Pull." -Color Gray
        if ($Mode -eq "prompt" -and $pendingIdes.Count -gt 0) {
            $doDisable = Read-Host "   Disable `"github.gitAuthentication`" for $list now so UI Push uses git-switch? [Y/n]"
            if ($doDisable -match '^(n|no)$') {
                Write-Color "   [INFO] Skipped. You can configure this anytime in Settings -> [6] IDE Git Auth Sync." -Color Gray
            } else {
                foreach ($ide in $pendingIdes) {
                    if (Set-IdeGitAuthSetting -SettingsPath $ide.Path -DesiredValue $false) {
                        Write-Color "   [✔] $($ide.Name): Set `"github.gitAuthentication`": false" -Color Green
                    } else {
                        Write-Color "   [X] $($ide.Name): Failed to update $($ide.Path)" -Color Red
                    }
                }
            }
        } else {
            Write-Color "         Set `"github.gitAuthentication`": false in IDE settings.json to share" -Color Gray
            Write-Color "         credentials with git-switch (or use Settings -> [6] IDE Git Auth Sync)." -Color Gray
        }
    }
}

# -------------------------- FEATURE FUNCTIONS --------------------------
function Test-Connection-Action {
    $Profiles = @(Load-Profiles)
    if ($Profiles.Count -eq 0) { Write-Color "`n  [!] No profiles found." "Yellow"; return }

    Write-Host "`n"
    Draw-Border-Top 60 "Magenta"
    Draw-Line "TEST GITHUB CONNECTION" 60 "Magenta" "White"
    Draw-Separator 60 "Magenta"
    
    for ($i = 0; $i -lt $Profiles.Count; $i++) {
        $Text = "  [$($i+1)] $($Profiles[$i].alias)"
        Draw-Line $Text 60 "Magenta" "White"
    }
    Draw-Border-Bottom 60 "Magenta"

    $Choice = Read-Host "  Select ID to test (0 to cancel)"
    if ($Choice -eq "0" -or -not ($Choice -as [int])) { return }
    $Idx = [int]$Choice - 1
    if ($Idx -lt 0 -or $Idx -ge $Profiles.Count) { return }

    $Selected = $Profiles[$Idx]

    if ($Selected.keyPath) {
        $null = Test-GitHub-Connection -Alias $Selected.alias
    } else {
        Write-Color "  [!] Profile '$($Selected.alias)' does not have an SSH key recorded." "Yellow"
    }

    if (Test-ProfileHasToken -Alias $Selected.alias) {
        Write-Host ""
        $null = Test-GitHubHttpsConnection -Alias $Selected.alias
    }
}

function Test-GitHub-Connection {
    param($Alias)
    $HostAlias = "github.com-$Alias"
    Write-Color "`n   [INFO] Testing connection to $HostAlias..." -Color Cyan
    
    $OutputStr = ""
    try {
        # FIX: Thêm pipe | ForEach-Object { "$_" }
        # Tác dụng: Biến mọi ErrorRecord thành String thuần túy ngay lập tức
        # Giúp chặn hoàn toàn dòng lỗi đỏ "NativeCommandError"
        $Output = & ssh -T "git@$HostAlias" 2>&1 | ForEach-Object { "$_" }
        $OutputStr = $Output | Out-String
    } catch {
        $OutputStr = $_.Exception.Message
    }

    if ($OutputStr -match "successfully authenticated") {
        Write-Color "   [✔] Connection SUCCESS! You are authenticated." -Color Green
        return $true
    } else {
        Write-Color "   [X] Connection FAILED." -Color Red
        # Clean bớt dòng chữ thừa nếu có
        $CleanErr = $OutputStr -replace "ssh.exe : ", ""
        Write-Color "   [DEBUG] $CleanErr" -Color DarkGray
        return $false
    }
}

function Add-Profile-Action {
    Write-Host "`n"
    Draw-Header "ADD NEW GIT PROFILE"
    
    $Alias = $null
    
    # --- VÒNG LẶP NHẬP ALIAS (RETRY LOOP) ---
    while ($true) {
        $Alias = Read-Host "   Enter Profile Alias (e.g. Work, Personal)"
        if ($Alias -eq "0") { return }

        $ErrorMsg = $null
        
        if ([string]::IsNullOrWhiteSpace($Alias)) {
            $ErrorMsg = "Alias required."
        }
        elseif ($Alias -notmatch "^[a-zA-Z0-9]+$") {
            $ErrorMsg = "Alias must be alphanumeric (no spaces/symbols)."
        }
        else {
            $Profiles = @(Load-Profiles)
            if ($Profiles | Where-Object { $_.alias -eq $Alias }) {
                $ErrorMsg = "Profile '$Alias' already exists."
            }
        }

        if ($ErrorMsg) {
            Write-Color "   [!] $ErrorMsg" "Red"
            $Retry = Read-Host "   Press ENTER to retry, or type '0' to back"
            if ($Retry -eq "0") { return }
            Write-Host ""
        } else {
            break
        }
    }
    # ---------------------------------------

    $UName = Read-Host "   Enter Git User Name (e.g. John Doe)"
    $UEmail = Read-Host "   Enter Git Email     (e.g. john@company.com)"

    if ([string]::IsNullOrWhiteSpace($UName) -or [string]::IsNullOrWhiteSpace($UEmail)) { 
        Write-Color "   [!] Name and Email are required." "Red"; return 
    }

    $GhUser = Read-Host "   Enter GitHub Username (optional, for HTTPS/gh sync, Enter to skip)"
    $SecPat = Read-Host "   Enter GitHub HTTPS PAT (optional, hidden, Enter to skip)" -AsSecureString
    $GhPat = if ($SecPat -and $SecPat.Length -gt 0) { [System.Net.NetworkCredential]::new("", $SecPat).Password } else { "" }

    # 1. Generate Key
    $KeyPath = Generate-SSH-Key -Email $UEmail -Alias $Alias
    if (-not $KeyPath) { return }

    # 2. Update SSH Config
    Update-SSH-Config -Alias $Alias -KeyPath $KeyPath

    # 3. Clipboard
    $PubKeyPath = "$KeyPath.pub"
    if (Test-Path $PubKeyPath) {
        $PubKeyContent = Get-Content $PubKeyPath -Raw
        try {
            Copy-TextToClipboard -Text $PubKeyContent
            Write-Color "   [✔] Public Key copied to CLIPBOARD!" -Color Green
        } catch {
            Write-Color "   [!] Could not auto-copy. Please open .pub file manually." -Color Yellow
        }
    }

    # 4. Hướng dẫn & Mở Browser
    $PasteKey = if ($IsMacOS) { "Cmd+V" } else { "Ctrl+V" }
    Write-Host "`n   [ACTION REQUIRED]" -ForegroundColor Yellow
    Write-Host "   1. I will open GitHub SSH settings now." -ForegroundColor Gray
    Write-Host "   2. Paste ($PasteKey) and add the key as 'Authentication Key' (for git push)." -ForegroundColor Gray
    Write-Host "   3. (For Verified commits) Add the SAME key once more with Key type = 'Signing Key'." -ForegroundColor Gray
    Write-Host "   4. Come back here and press ENTER." -ForegroundColor Gray
    
    Start-Sleep -Seconds 2
    Open-Target "https://github.com/settings/ssh/new"
    
    Read-Host "`n   Press ENTER after you have added the key on GitHub..."

    # 5. Test Connection
    $null = Test-GitHub-Connection -Alias $Alias

    # 6. Save Profile (& optional HTTPS PAT)
    $NewProfile = [PSCustomObject]@{
        alias = $Alias
        userName = $UName
        userEmail = $UEmail
        keyPath = $KeyPath
        githubUsername = $GhUser
        created = (Get-Date).ToString("yyyy-MM-dd HH:mm")
    }
    $Profiles += $NewProfile
    Save-Profiles $Profiles
    if (-not [string]::IsNullOrWhiteSpace($GhPat)) {
        Save-ProfileToken -Alias $Alias -Token $GhPat
        Write-Color "   [✔] Saved HTTPS PAT securely." -Color Green
    }
    Write-Color "`n   [✔] Profile '$Alias' saved successfully!" -Color Green

    # ==========================================================================
    # LOGIC MỚI: Tự động set Global Config nếu hiện tại đang là "Not Set"
    # ==========================================================================
    $Curr = Get-Git-Current
    if ($Curr.Name -eq "Not Set" -or $Curr.Name -eq $null) {
        Sync-Git-Identity -UserName $UName -UserEmail $UEmail -KeyPath $KeyPath
        Sync-HttpsCredentials -Alias $Alias -GitHubUser $GhUser -FallbackUser $UName
        Write-Color "   [INFO] Auto-set as Global Git Config (was previously unset)." -Color Cyan
    }
}

function Switch-Profile-Action {
    $Profiles = @(Load-Profiles)
    if ($Profiles.Count -eq 0) { Write-Color "`n   [!] No profiles. Add one first." "Yellow"; return }

    Write-Host "`n"
    Draw-Header "SWITCH PROFILE"
    
    # Header cột (Màu tối để làm nền)
    $Format = "     [{0}] {1,-15} {2}"
    Write-Host ($Format -f "#", "ALIAS", "EMAIL") -ForegroundColor DarkGray
    
    # Danh sách Profile
    for ($i = 0; $i -lt $Profiles.Count; $i++) {
        $patTag = if (Test-ProfileHasToken -Alias $Profiles[$i].alias) { " [PAT]" } else { "" }
        Write-Host ($Format -f ($i+1), $Profiles[$i].alias, "$($Profiles[$i].userEmail)$patTag") -ForegroundColor White
    }
    Draw-Sep

    $Choice = Read-Host "   Choose ID (0 to cancel)"
    
    # Validate Input
    if ($Choice -eq "0" -or -not ($Choice -as [int])) { return }
    $Idx = [int]$Choice - 1
    if ($Idx -lt 0 -or $Idx -ge $Profiles.Count) { return }

    $Selected = $Profiles[$Idx]
    
    Write-Color "`n   [INFO] Switching to '$($Selected.alias)'..." -Color Cyan
    
    # 1. Change Global & Local Config (+ Auto SSH Signing Key)
    Sync-Git-Identity -UserName $Selected.userName -UserEmail $Selected.userEmail -KeyPath $Selected.keyPath

    # 2. Swap/Clear HTTPS Credential (Git credential helper / gh CLI)
    Sync-HttpsCredentials -Alias $Selected.alias -GitHubUser $Selected.githubUsername -FallbackUser $Selected.userName
    
    # 3. Detect & Update Repo Remote URL (HTTPS vs SSH)
    Update-Repo-Url -Alias $Selected.alias

    # 4. Offer to update author & re-sign unpushed local commits
    Invoke-FixUnpushedCommits -TargetName $Selected.userName -TargetEmail $Selected.userEmail

    # 5. Test SSH (Để đảm bảo key hoạt động tốt)
    if ($Selected.keyPath) {
        $null = Test-GitHub-Connection -Alias $Selected.alias
    }

    # 6. Inline IDE Git Auth Sync (1-press disable if enabled)
    Show-IdeSyncHint -Mode "prompt"

    Write-Color "`n   [✔] Switched successfully!" -Color Green
    Write-Color "       Global User : $($Selected.userName)" -Color Gray
    Write-Color "       Global Email: $($Selected.userEmail)" -Color Gray
    if (Test-InsideGitRepo) {
        Write-Color "       Local Repo  : Synced to $($Selected.userName) <$($Selected.userEmail)>" -Color Gray
    }
}

function Remove-Profile-Action {
    $Profiles = @(Load-Profiles)
    if ($Profiles.Count -eq 0) { Write-Color "`n   [!] No profiles to remove." "Yellow"; return }

    Write-Host "`n"
    Draw-Header "REMOVE PROFILE"
    
    # Hiển thị danh sách rõ ràng (Có cả Email)
    $Format = "     [{0}] {1,-15} {2}"
    Write-Host ($Format -f "#", "ALIAS", "EMAIL") -ForegroundColor DarkGray
    
    for ($i = 0; $i -lt $Profiles.Count; $i++) {
        $patTag = if (Test-ProfileHasToken -Alias $Profiles[$i].alias) { " [PAT]" } else { "" }
        Write-Host ($Format -f ($i+1), $Profiles[$i].alias, "$($Profiles[$i].userEmail)$patTag") -ForegroundColor White
    }
    Draw-Sep

    $Choice = Read-Host "   Select ID to remove (0 to cancel)"
    
    # Validate Input
    if ($Choice -eq "0" -or -not ($Choice -as [int])) { return }
    $Idx = [int]$Choice - 1
    if ($Idx -lt 0 -or $Idx -ge $Profiles.Count) { return }

    $Removed = $Profiles[$Idx]
    
    Write-Color "`n   [WARNING] Deleting profile '$($Removed.alias)'..." "Red"
    $Confirm = Read-Host "   Type 'DELETE' to confirm"
    if ($Confirm -ne "DELETE") { return }

    # 1. Remove SSH Keys
    if ($Removed.keyPath) {
        if (Test-Path $Removed.keyPath) { Remove-Item $Removed.keyPath -Force; Write-Color "   [✔] Private Key deleted." "Gray" }
        if (Test-Path "$($Removed.keyPath).pub") { Remove-Item "$($Removed.keyPath).pub" -Force; Write-Color "   [✔] Public Key deleted." "Gray" }
    }

    # 2. Remove from SSH Config & Saved HTTPS PAT
    Remove-From-SSH-Config -Alias $Removed.alias
    if (Test-ProfileHasToken -Alias $Removed.alias) {
        Remove-ProfileToken -Alias $Removed.alias
        Write-Color "   [✔] Saved HTTPS PAT deleted." "Gray"
    }

    # 3. Remove from JSON
    $NewProfiles = @($Profiles | Where-Object { $_.alias -ne $Removed.alias })
    
    if ($NewProfiles.Count -eq 0) {
        "[]" | Set-Content $ProfilesFile -Encoding UTF8
    } else {
        Save-Profiles $NewProfiles
    }

    # 4. Check & Clear Global/Local Config, Signing Key, and Cached HTTPS Credential
    $Curr = Get-Git-Current
    if ($Curr.Name -eq $Removed.userName -or $Curr.Email -eq $Removed.userEmail) {
        git config --global --unset user.name 2>$null
        git config --global --unset user.email 2>$null
        Clear-GitHubHttpsCredential
        Write-Color "   [INFO] Current Global Git config & cached HTTPS credential cleared because profile was removed." "Cyan"
    }
    $currSKey = git config --global user.signingkey 2>$null
    if ($Removed.keyPath -and $currSKey -eq "$($Removed.keyPath).pub") {
        git config --global --unset user.signingkey 2>$null
    }
    if (Test-InsideGitRepo) {
        $localEmail = git config --local user.email 2>$null
        if ($localEmail -eq $Removed.userEmail) {
            git config --local --unset user.name 2>$null
            git config --local --unset user.email 2>$null
            Write-Color "   [INFO] Local repo Git config cleared because profile was removed." "Cyan"
        }
        $localSKey = git config --local user.signingkey 2>$null
        if ($Removed.keyPath -and $localSKey -eq "$($Removed.keyPath).pub") {
            git config --local --unset user.signingkey 2>$null
        }
    }

    Write-Color "   [✔] Profile removed successfully." "Green"
}

function Toggle-SSH-Signing {
    if (Test-CommitSigningEnabled) {
        git config --global commit.gpgsign false
        if (Test-InsideGitRepo) { git config --local --unset commit.gpgsign 2>$null }
        Write-Color "   [✔] SSH Commit Signing disabled (commit.gpgsign = false)." "Yellow"
    } else {
        git config --global gpg.format ssh
        git config --global commit.gpgsign true
        $Curr = Get-Git-Current
        $Profiles = @(Load-Profiles)
        $Matched = $Profiles | Where-Object { $_.userEmail -eq $Curr.Email -and $_.keyPath } | Select-Object -First 1
        if ($Matched -and (Test-Path "$($Matched.keyPath).pub")) {
            $pubKey = "$($Matched.keyPath).pub"
            git config --global user.signingkey "$pubKey"
            if (Test-InsideGitRepo) {
                git config --local gpg.format ssh
                git config --local user.signingkey "$pubKey"
            }
            Write-Color "   [✔] SSH Commit Signing enabled with key: $pubKey" "Green"
        } else {
            Write-Color "   [✔] SSH Commit Signing enabled (switch a profile to assign signing key)." "Green"
        }
        Write-Color "   [TIP] Add your .pub key on GitHub as Key type = 'Signing Key' for Verified badge." "Gray"
    }
}

function Manage-HttpsCredentials-Action {
    Write-Host "`n"
    Draw-Header "MANAGE HTTPS CREDENTIALS (PAT)"

    $Profiles = @(Load-Profiles)
    if ($Profiles.Count -eq 0) { Write-Color "   [!] No profiles found. Add a profile first." "Yellow"; return }

    $Format = "     [{0}] {1,-15} {2,-22} {3}"
    Write-Host ($Format -f "#", "ALIAS", "GITHUB USER", "PAT STATUS") -ForegroundColor DarkGray
    for ($i = 0; $i -lt $Profiles.Count; $i++) {
        $p = $Profiles[$i]
        $gh = if ($p.githubUsername) { $p.githubUsername } else { "(not set)" }
        $st = if (Test-ProfileHasToken -Alias $p.alias) { "Configured" } else { "Not Set" }
        Write-Host ($Format -f ($i + 1), $p.alias, $gh, $st) -ForegroundColor White
    }
    Write-Host ""
    Write-Host "     [C] Clear cached github.com HTTPS credential now"
    Write-Host "     [0] Back"
    Draw-Sep

    $Choice = Read-Host "   Select profile ID (or C/0)"
    if ([string]::IsNullOrWhiteSpace($Choice) -or $Choice -eq "0") { return }
    if ($Choice -match "^c$") {
        Clear-GitHubHttpsCredential
        Write-Color "   [✔] Cleared cached github.com HTTPS credential from Git credential helper." "Green"
        return
    }
    if (-not ($Choice -as [int])) { return }
    $Idx = [int]$Choice - 1
    if ($Idx -lt 0 -or $Idx -ge $Profiles.Count) { return }

    $Sel = $Profiles[$Idx]
    Write-Color "`n   Profile: $($Sel.alias) <$($Sel.userEmail)>" "Cyan"
    Write-Host "     [1] Set / Update GitHub Username & HTTPS PAT"
    Write-Host "     [2] Remove saved HTTPS PAT"
    Write-Host "     [3] Test saved HTTPS PAT"
    Write-Host "     [0] Back"
    Draw-Sep

    $Sub = Read-Host "   Choose"
    switch ($Sub) {
        "1" {
            $defaultGh = if ($Sel.githubUsername) { $Sel.githubUsername } else { $Sel.userName }
            $newGh = Read-Host "   GitHub Username [$defaultGh]"
            if ([string]::IsNullOrWhiteSpace($newGh)) { $newGh = $defaultGh }
            $secPat = Read-Host "   GitHub PAT (hidden, Enter to keep existing)" -AsSecureString
            $newPat = if ($secPat -and $secPat.Length -gt 0) { [System.Net.NetworkCredential]::new("", $secPat).Password } else { "" }

            if ($Sel.PSObject.Properties["githubUsername"]) {
                $Sel.githubUsername = $newGh
            } else {
                $Sel | Add-Member -NotePropertyName "githubUsername" -NotePropertyValue $newGh
            }
            Save-Profiles $Profiles

            if (-not [string]::IsNullOrWhiteSpace($newPat)) {
                Save-ProfileToken -Alias $Sel.alias -Token $newPat
                Write-Color "   [✔] Saved HTTPS PAT securely for '$($Sel.alias)'." "Green"
            } else {
                Write-Color "   [✔] Updated GitHub Username to '$newGh'." "Green"
            }

            $Curr = Get-Git-Current
            if ($Curr.Email -eq $Sel.userEmail) {
                Sync-HttpsCredentials -Alias $Sel.alias -GitHubUser $newGh -FallbackUser $Sel.userName
            }
        }
        "2" {
            Remove-ProfileToken -Alias $Sel.alias
            Write-Color "   [✔] Removed saved HTTPS PAT for '$($Sel.alias)'." "Yellow"
            $Curr = Get-Git-Current
            if ($Curr.Email -eq $Sel.userEmail) {
                Clear-GitHubHttpsCredential
                Write-Color "   [INFO] Also cleared active cached github.com HTTPS credential." "Gray"
            }
        }
        "3" {
            if (Test-ProfileHasToken -Alias $Sel.alias) {
                $null = Test-GitHubHttpsConnection -Alias $Sel.alias
            } else {
                Write-Color "   [!] No HTTPS PAT saved for '$($Sel.alias)'." "Yellow"
            }
        }
    }
}

function Sync-IdeGitAuth-Action {
    Write-Host "`n"
    Draw-Header "IDE GIT AUTH SYNC (github.gitAuthentication)"

    Write-Color "   VS Code / Cursor / Antigravity use their own GitHub OAuth session for UI Push." "Gray"
    Write-Color "   Setting `"github.gitAuthentication`": false makes IDE Push use git-switch." "Gray"
    Write-Host ""

    $ides = @(Get-IdeSettingsPaths)
    if ($ides.Count -eq 0) {
        Write-Color "   [!] No supported IDE settings directory detected automatically." "Yellow"
        Write-Color "       Manually add this to your IDE settings.json:" "Gray"
        Write-Color "         `"github.gitAuthentication`": false" "White"
        return
    }

    for ($i = 0; $i -lt $ides.Count; $i++) {
        $st = Get-IdeGitAuthSetting -SettingsPath $ides[$i].Path
        $label = switch ($st) {
            "false" { "OFF (Synced with git-switch)" }
            "true"  { "ON  (Uses IDE OAuth)" }
            "unset" { "ON  (Default - Uses IDE OAuth)" }
            default { "UNKNOWN (Could not parse settings.json)" }
        }
        Write-Host ("     [{0}] {1,-18} {2}" -f ($i + 1), $ides[$i].Name, $label)
    }
    Write-Host ""
    Write-Host "     [A] Disable github.gitAuthentication for ALL detected IDEs (Recommended)"
    Write-Host "     [0] Back"
    Draw-Sep

    $Opt = Read-Host "   Select IDE # to toggle, A for all, or 0 to back"
    if ([string]::IsNullOrWhiteSpace($Opt) -or $Opt -eq "0") { return }
    if ($Opt -match "^a$") {
        foreach ($ide in $ides) {
            if (Set-IdeGitAuthSetting -SettingsPath $ide.Path -Desired "false") {
                Write-Color "   [✔] $($ide.Name): Set `"github.gitAuthentication`": false" "Green"
            } else {
                Write-Color "   [X] $($ide.Name): Failed to update $($ide.Path)" "Red"
            }
        }
        return
    }
    if ($Opt -as [int]) {
        $idx = [int]$Opt - 1
        if ($idx -ge 0 -and $idx -lt $ides.Count) {
            $ide = $ides[$idx]
            $cur = Get-IdeGitAuthSetting -SettingsPath $ide.Path
            $next = if ($cur -eq "false") { "true" } else { "false" }
            if (Set-IdeGitAuthSetting -SettingsPath $ide.Path -Desired $next) {
                Write-Color "   [✔] $($ide.Name): Set `"github.gitAuthentication`": $next" "Green"
            } else {
                Write-Color "   [X] $($ide.Name): Failed to update $($ide.Path)" "Red"
            }
        }
    }
}

function Show-Settings-Action {
    Write-Host "`n"
    Draw-Header "SETTINGS & TOOLS"

    $SignState = if (Test-CommitSigningEnabled) { "ON" } else { "OFF" }
    Write-Host "     [1] Open profiles.json (View/Edit DB)"
    Write-Host "     [2] Backup Profiles (Create snapshot)"
    Write-Host "     [3] Open .ssh folder (View Keys)"
    Write-Host "     [4] Toggle SSH Commit Signing (Currently: $SignState)"
    Write-Host "     [5] Manage HTTPS Credentials (PAT / Keychain)"
    Write-Host "     [6] IDE Git Auth Sync (github.gitAuthentication)"
    Write-Host "     [0] Back"
    
    Draw-Sep

    $Opt = Read-Host "   Choose"
    switch ($Opt) {
        "1" { Open-Target $ProfilesFile }
        "2" { 
            $Bak = Join-Path $BaseDir "backup_$(Get-Date -Format 'yyyyMMdd_HHmm').json"
            Copy-Item $ProfilesFile $Bak
            Write-Color "   [✔] Backup created: $Bak" "Green"
        }
        "3" { Open-Target $SSHDir }
        "4" { Toggle-SSH-Signing }
        "5" { Manage-HttpsCredentials-Action }
        "6" { Sync-IdeGitAuth-Action }
    }
}


# -------------------------- MAIN UI --------------------------

function Show-Banner {
    $Art = @"
      ██████  ██ ████████     ███████ ██     ██ ██ ████████  ██████  ██   ██
     ██       ██    ██        ██      ██     ██ ██    ██    ██       ██   ██
     ██   ███ ██    ██        ███████ ██  █  ██ ██    ██    ██       ███████
     ██    ██ ██    ██             ██ ██ ███ ██ ██    ██    ██       ██   ██
      ██████  ██    ██        ███████  ███ ███  ██    ██     ██████  ██   ██
"@
    Write-Host $Art -ForegroundColor Magenta
    Draw-Sep
    
    $Curr = Get-Git-Current
    Write-Host "   » GIT PROFILE MANAGEMENT SYSTEM [v2.3]" -ForegroundColor White
    Draw-Sep
    
    if ($IsWinOS) {
        $IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if ($IsAdmin) {
            Write-Color "   [✔] STATUS: Running as Administrator" -Color Green
        } else {
            Write-Color "   [!] STATUS: Running as Standard User (Restrictions may apply)" -Color Yellow
        }
    } else {
        $OsLabel = if ($IsMacOS) { "macOS" } else { "Linux" }
        Write-Color "   [✔] STATUS: Running on $OsLabel ($env:USER)" -Color Green
    }

    Write-Host "   [●] CURRENT: " -NoNewline -ForegroundColor Cyan
    Write-Host "$($Curr.Name) " -NoNewline -ForegroundColor White
    Write-Host "<$($Curr.Email)>" -ForegroundColor DarkGray

    if (Test-InsideGitRepo) {
        $LocalEmail = git config --local user.email 2>$null
        $LocalName = git config --local user.name 2>$null
        if ($LocalEmail -and $LocalEmail -ne $Curr.Email) {
            $DispName = if ($LocalName) { $LocalName } else { $Curr.Name }
            Write-Color "   [!] LOCAL OVERRIDE: $DispName <$LocalEmail> (Switch to sync)" -Color Yellow
        }

        $OriginUrl = git remote get-url origin 2>$null
        if ($OriginUrl) {
            $rinfo = Get-GitHubRemoteInfo -Url $OriginUrl
            switch ($rinfo.Type) {
                "https" {
                    Write-Color "   [!] REMOTE (HTTPS): $OriginUrl (SSH config ignored; switch to convert/PAT)" -Color Yellow
                }
                "ssh_default" {
                    Write-Color "   [!] REMOTE (SSH): $OriginUrl (No profile alias; switch to bind)" -Color Yellow
                }
                "ssh_alias" {
                    $Profiles = @(Load-Profiles)
                    $Active = $Profiles | Where-Object { $_.userEmail -eq $Curr.Email } | Select-Object -First 1
                    if ($Active -and $rinfo.SshAlias -ne $Active.alias) {
                        Write-Color "   [!] REMOTE (SSH): github.com-$($rinfo.SshAlias) != active '$($Active.alias)' (Switch to sync)" -Color Yellow
                    } else {
                        Write-Color "   [✔] REMOTE (SSH): $OriginUrl" -Color Green
                    }
                }
            }
        }
    }

    if (Test-CommitSigningEnabled) {
        $SKey = git config --get user.signingkey 2>$null
        if ($SKey) {
            $KeyName = Split-Path $SKey -Leaf
            Write-Color "   [✔] SSH SIGNING: ON ($KeyName)" -Color Green
        } else {
            Write-Color "   [!] SSH SIGNING: ON (no signing key set)" -Color Yellow
        }
    }
    Draw-Sep
}

function Show-Menu {
    Write-Host ""
    Write-Host "   SELECT AN OPTION:" -ForegroundColor Gray
    Write-Host ""
    Write-Host "     [1] Add New Profile"
    Write-Host "     [2] Switch Profile"
    Write-Host "     [3] Remove Profile"
    Write-Host "     [4] Settings"
    Write-Host "     [5] Test Connection"
    Write-Host "     [0] Exit Program"
    Write-Host ""
    Draw-Sep
}
# ================= MAIN EXECUTION LOOP =================
$Running = $true
Initialize-System

do {
    Clear-Host
    Show-Banner
    Show-Menu
    $Selection = Read-Host "  Choose an option (0-5)"

    switch ($Selection) {
        "1" { Add-Profile-Action; Wait-KeyPress }
        "2" { Switch-Profile-Action; Wait-KeyPress }
        "3" { Remove-Profile-Action; Wait-KeyPress }
        "4" { Show-Settings-Action; Wait-KeyPress }
        "5" { Test-Connection-Action; Wait-KeyPress }
        "0" { $Running = $false; Write-Color "`n  Goodbye! 👋" "Magenta" }
        default { Write-Color "  Invalid option." "Red"; Start-Sleep -Milliseconds 500 }
    }
} while ($Running)