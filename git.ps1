# ==============================================================================
# GIT PROFILE MANAGER (NATIVE POWERSHELL)
# Version: 2.4 (Cross-Platform PowerShell)
# Author: nhatprx
# Features: 1-Click Switch, Global Multi-Repo Routing, SSH Signing, HTTPS PAT
# ==============================================================================

# -------------------------- CONFIGURATION --------------------------
$IsWinOS = ($env:OS -eq "Windows_NT") -or ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
$HomeDir = if ($IsWinOS -and $env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$BaseDir = Join-Path $HomeDir ".git-switch"
$ProfilesFile = Join-Path $BaseDir "profiles.json"
$TokensDir = Join-Path $BaseDir "tokens"
$ActiveGitConfig = Join-Path $BaseDir "active.gitconfig"
$ActiveGitConfigInclude = "~/.git-switch/active.gitconfig"
$NoSshRewriteFlag = Join-Path $BaseDir "no-ssh-rewrite"
$SSHDir = Join-Path $HomeDir ".ssh"
$SSHConfigFile = Join-Path $SSHDir "config"
$script:StatusMsg = ""
$script:StatusColor = "Green"
$script:NeedPause = $false

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
    param([string]$UserName, [string]$UserEmail, [string]$KeyPath, [switch]$Quiet)

    # 1. Global identity
    git config --global user.name "$UserName"
    git config --global user.email "$UserEmail"

    # 2. Clear stale local repo overrides so this repo inherits global switches cleanly
    $inRepo = Test-InsideGitRepo
    if ($inRepo) {
        git config --local --unset-all user.name 2>$null
        git config --local --unset-all user.email 2>$null
        git config --local --unset-all user.signingkey 2>$null
        git config --local --unset-all gpg.format 2>$null
        $lSignCur = git config --local commit.gpgsign 2>$null
        if ($lSignCur -ne "false") {
            git config --local --unset-all commit.gpgsign 2>$null
        }

        $localSshCmd = git config --local core.sshCommand 2>$null
        if (-not [string]::IsNullOrWhiteSpace($localSshCmd)) {
            Write-Color "   [!] Local core.sshCommand is set ($localSshCmd) and may override SSH key." -Color Yellow
            $script:NeedPause = $true
        }
    }

    $globalSshCmd = git config --global core.sshCommand 2>$null
    if (-not [string]::IsNullOrWhiteSpace($globalSshCmd)) {
        Write-Color "   [!] Global core.sshCommand is set ($globalSshCmd) and may override SSH key." -Color Yellow
        $script:NeedPause = $true
    }

    # 3. Auto-enable & sync global SSH commit signing unless user explicitly disabled it
    if ($KeyPath -and (Test-Path "$KeyPath.pub")) {
        $pubKey = "$KeyPath.pub"
        $gSign = git config --global commit.gpgsign 2>$null
        if ($gSign -ne "false") {
            git config --global gpg.format ssh
            git config --global user.signingkey "$pubKey"
            git config --global commit.gpgsign true
            if (-not $Quiet) {
                Write-Color "   [✔] SSH Commit Signing active: $pubKey" -Color Green
            }
        }
    }
}

function Test-SshRewriteEnabled {
    return (-not (Test-Path $NoSshRewriteFlag))
}

function Ensure-ActiveGitConfigIncluded {
    $existing = @(git config --global --get-all include.path 2>$null)
    if ($existing -notcontains $ActiveGitConfigInclude) {
        git config --global --add include.path $ActiveGitConfigInclude
    }
}

function Clear-GlobalGitHubRouting {
    if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null }
    [System.IO.File]::WriteAllText($ActiveGitConfig, "# Managed by git-switch (inactive)`n", [System.Text.UTF8Encoding]::new($false))
}

function Sync-GlobalGitHubRouting {
    param([string]$Alias, [string]$KeyPath)

    if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null }
    if (-not (Test-SshRewriteEnabled)) {
        Clear-GlobalGitHubRouting
        return
    }
    if ([string]::IsNullOrWhiteSpace($Alias) -or [string]::IsNullOrWhiteSpace($KeyPath) -or -not (Test-Path $KeyPath)) {
        Clear-GlobalGitHubRouting
        return
    }

    Ensure-ActiveGitConfigIncluded

    $profiles = @(Load-Profiles)
    $insteadOf = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @("https://github.com/", "https://www.github.com/", "http://github.com/", "git@github.com:", "ssh://git@github.com/", "ssh://git@github.com:22/")) {
        $insteadOf.Add($p)
    }

    foreach ($prof in $profiles) {
        if ($null -eq $prof) { continue }
        $other = if ($prof.alias) { $prof.alias.Trim() } else { "" }
        if ($other -and $other -ne $Alias) {
            foreach ($pref in @("git@github.com-$other`:", "ssh://git@github.com-$other/", "ssh://git@github.com-$other`:22/")) {
                if (-not $insteadOf.Contains($pref)) { $insteadOf.Add($pref) }
            }
        }
        $ghUser = if ($prof.githubUsername) { $prof.githubUsername.Trim() } else { "" }
        if ($ghUser -and ($ghUser -match "^[A-Za-z0-9-]+$")) {
            $pref = "https://$ghUser@github.com/"
            if (-not $insteadOf.Contains($pref)) { $insteadOf.Add($pref) }
        }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# Managed by git-switch (Active: $Alias)")
    $lines.Add("[url `"git@github.com-$Alias`:`"]")
    foreach ($pref in $insteadOf) {
        $lines.Add("    insteadOf = $pref")
    }
    [System.IO.File]::WriteAllText($ActiveGitConfig, (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
}

function Get-ActiveProfile {
    param([array]$Profiles = $null)
    if ($null -eq $Profiles) { $Profiles = @(Load-Profiles) }
    $Curr = Get-Git-Current
    $emailMatches = @($Profiles | Where-Object { $null -ne $_ -and $_.userEmail -eq $Curr.Email })
    if ($emailMatches.Count -eq 0) { return $null }

    # 1. Exact match on signing key
    $currSKey = git config --global user.signingkey 2>$null
    if (-not [string]::IsNullOrWhiteSpace($currSKey)) {
        foreach ($p in $emailMatches) {
            if ($p.keyPath -and ($currSKey -eq "$($p.keyPath).pub" -or $currSKey -eq $p.keyPath)) {
                return $p
            }
        }
    }

    # 2. Match active alias recorded in active.gitconfig
    if (Test-Path $ActiveGitConfig) {
        $firstLine = (Get-Content $ActiveGitConfig -TotalCount 1 -Encoding UTF8 -ErrorAction SilentlyContinue)
        if ($firstLine -and $firstLine.Trim() -match "^# Managed by git-switch \(Active:\s*([^)]+)\)$") {
            $cfgAlias = $Matches[1].Trim()
            foreach ($p in $emailMatches) {
                if ($p.alias -eq $cfgAlias) { return $p }
            }
        }
    }

    # 3. Match email + name
    foreach ($p in $emailMatches) {
        if ($p.userName -eq $Curr.Name) { return $p }
    }

    # 4. Fallback: first profile with matching email
    return $emailMatches[0]
}

function Ensure-ActiveRoutingSynced {
    param($ActiveProfile)
    if ($null -eq $ActiveProfile -or -not (Test-SshRewriteEnabled)) { return }
    if ([string]::IsNullOrWhiteSpace($ActiveProfile.alias) -or [string]::IsNullOrWhiteSpace($ActiveProfile.keyPath) -or -not (Test-Path $ActiveProfile.keyPath)) { return }

    $needsSync = $false
    $existingInc = @(git config --global --get-all include.path 2>$null)
    if ($existingInc -notcontains $ActiveGitConfigInclude) {
        $needsSync = $true
    } elseif (-not (Test-Path $ActiveGitConfig)) {
        $needsSync = $true
    } else {
        $firstLine = (Get-Content $ActiveGitConfig -TotalCount 1 -Encoding UTF8 -ErrorAction SilentlyContinue)
        if (-not $firstLine -or $firstLine.Trim() -ne "# Managed by git-switch (Active: $($ActiveProfile.alias))") {
            $needsSync = $true
        }
    }

    if ($needsSync) {
        Ensure-SshReady -Alias $ActiveProfile.alias -KeyPath $ActiveProfile.keyPath
        Sync-GlobalGitHubRouting -Alias $ActiveProfile.alias -KeyPath $ActiveProfile.keyPath
    }
}

function Ensure-SshReady {
    param([string]$Alias, [string]$KeyPath)
    if ([string]::IsNullOrWhiteSpace($Alias) -or [string]::IsNullOrWhiteSpace($KeyPath) -or -not (Test-Path $KeyPath)) { return }
    $hasHost = $false
    if (Test-Path $SSHConfigFile) {
        $content = Get-Content $SSHConfigFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($content -match "(?m)^\s*Host\s+github\.com-$([regex]::Escape($Alias))(\s|$)") {
            $hasHost = $true
        }
    }
    if (-not $hasHost) {
        Update-SSH-Config -Alias $Alias -KeyPath $KeyPath -Quiet
    }
}

function Clear-EmbeddedHttpsRemote {
    param([string]$Alias)
    if (-not (Test-InsideGitRepo) -or -not (Test-SshRewriteEnabled)) { return }
    $rawUrl = git config --local --get remote.origin.url 2>$null
    if ([string]::IsNullOrWhiteSpace($rawUrl)) { return }
    $u = $rawUrl.Trim()
    if ($u -match "^https?://[^/@]+@github\.com(?::\d+)?/(.+)$") {
        $repoPath = $Matches[1].TrimEnd('/')
        git remote set-url origin "https://github.com/$repoPath"
        return
    }
    if ($u -match "^(?:ssh://)?git@github\.com-([^:/]+)(?::\d+)?[:/](.+)$") {
        if ($Matches[1] -ne $Alias) {
            $effUrl = git remote get-url origin 2>$null
            $rinfo = Get-GitHubRemoteInfo -Url $effUrl
            if ($rinfo.SshAlias -ne $Alias -and $rinfo.RepoPath) {
                git remote set-url origin "https://github.com/$($rinfo.RepoPath)"
            }
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

    $script:NeedPause = $true
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
    param($Alias, $KeyPath, [switch]$Quiet)

    # Remove existing entry with the same alias first to avoid duplicates
    Remove-From-SSH-Config -Alias $Alias -Quiet

    # Host ảo sẽ là: github.com-<alias>
    $ConfigBlock = @"

# Git profile: $Alias
Host github.com-$Alias
    HostName github.com
    User git
    IdentityFile "$KeyPath"
    IdentitiesOnly yes
"@
    
    try {
        Add-Content -Path $SSHConfigFile -Value $ConfigBlock -Encoding UTF8
        if (-not $Quiet) { Write-Color "  [✔] SSH Config updated (Host: github.com-$Alias)." -Color Green }
    } catch {
        if (-not $Quiet) { Write-Color "  [X] Failed to update .ssh/config." -Color Red }
    }
}

function Remove-From-SSH-Config {
    param($Alias, [switch]$Quiet)
    
    if (-not (Test-Path $SSHConfigFile)) { return }
    
    try {
        $Lines = @(Get-Content $SSHConfigFile -Encoding UTF8)
        $NewLines = @()
        $Skip = $false
        $TargetHeader = "# Git profile: $Alias"
        $TargetHost = "Host github.com-$Alias"
        
        foreach ($Line in $Lines) {
            $Trimmed = $Line.Trim()
            if ($Trimmed -eq $TargetHeader) {
                $Skip = $true
                continue
            }
            if ($Skip) {
                if ($Trimmed -eq "") {
                    $Skip = $false
                    continue
                }
                if (($Trimmed.StartsWith("Host ") -and $Trimmed -ne $TargetHost) -or $Trimmed.StartsWith("# Git profile:")) {
                    $Skip = $false
                    $NewLines += $Line
                }
                continue
            }
            $NewLines += $Line
        }
        
        $NewLines | Set-Content $SSHConfigFile -Encoding UTF8
        if (-not $Quiet) { Write-Color "  [✔] Removed entry from SSH Config." -Color Green }
    } catch {
        if (-not $Quiet) { Write-Color "  [!] Error cleaning SSH Config." -Color Yellow }
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
    param([string]$Alias, [string]$GitHubUser, [string]$FallbackUser, [switch]$Quiet)
    $effectiveUser = if (-not [string]::IsNullOrWhiteSpace($GitHubUser)) { $GitHubUser } else { $FallbackUser }

    if (Test-ProfileHasToken -Alias $Alias) {
        $pat = Get-ProfileToken -Alias $Alias
        if ($pat -and $effectiveUser) {
            $res = Set-GitHubHttpsCredential -GitHubUser $effectiveUser -Token $pat
            if (-not $Quiet) {
                if ($res -eq "ok") {
                    Write-Color "   [✔] Swapped HTTPS credential for github.com (user: $effectiveUser)." -Color Green
                } elseif ($res -eq "no_helper") {
                    $hintHelper = if ($IsWinOS) { "manager" } elseif ($IsMacOS) { "osxkeychain" } else { "store" }
                    Write-Color "   [!] No Git credential.helper configured. Run: git config --global credential.helper $hintHelper" -Color Yellow
                } else {
                    Write-Color "   [!] Could not write HTTPS credential to Git credential helper." -Color Yellow
                }
            }
        }
    } else {
        Clear-GitHubHttpsCredential
        if (-not $Quiet) {
            Write-Color "   [INFO] Cleared cached HTTPS credential for github.com (no PAT saved for '$Alias')." -Color Gray
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($GitHubUser) -and (Get-Command gh -ErrorAction SilentlyContinue)) {
        try {
            & gh auth switch --user $GitHubUser 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0 -and -not $Quiet) {
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

# -------------------------- FEATURE FUNCTIONS --------------------------
function Test-Connection-Action {
    $Profiles = @(Load-Profiles)
    if ($Profiles.Count -eq 0) { Write-Color "`n  [!] No profiles found." "Yellow"; return }

    $items = @()
    foreach ($p in $Profiles) {
        $items += ("{0,-15} {1}" -f $p.alias, $p.userEmail)
    }
    $items += "← Back"

    $Idx = Select-ArrowMenu -Title "TEST GITHUB CONNECTION" -Items $items
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
        if ($OutputStr -match "Hi ([^!]+)!") {
            Write-Color "   [✔] Connection SUCCESS! Authenticated as: $($Matches[1])" -Color Green
        } else {
            Write-Color "   [✔] Connection SUCCESS! You are authenticated." -Color Green
        }
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

    $UName = Read-Host "   Git User Name (e.g. John Doe)"
    $UEmail = Read-Host "   Git Email     (e.g. john@company.com)"

    if ([string]::IsNullOrWhiteSpace($UName) -or [string]::IsNullOrWhiteSpace($UEmail)) { 
        Write-Color "   [!] Name and Email are required." "Red"; return 
    }

    # 1. Generate Key
    $KeyPath = Generate-SSH-Key -Email $UEmail -Alias $Alias
    if (-not $KeyPath) { return }

    # 2. Update SSH Config
    Update-SSH-Config -Alias $Alias -KeyPath $KeyPath -Quiet

    # 3. Clipboard
    $PubKeyPath = "$KeyPath.pub"
    if (Test-Path $PubKeyPath) {
        $PubKeyContent = Get-Content $PubKeyPath -Raw
        try {
            Copy-TextToClipboard -Text $PubKeyContent
            Write-Color "   [✔] Public Key copied to clipboard." -Color Green
        } catch {
            Write-Color "   [!] Could not auto-copy. Please open .pub file manually." -Color Yellow
        }
    }

    # 4. Instructions & Open Browser
    $PasteKey = if ($IsMacOS) { "Cmd+V" } else { "Ctrl+V" }
    Write-Host "`n   Add the key on GitHub (opening browser):" -ForegroundColor Yellow
    Write-Host "   1. Paste ($PasteKey) as 'Authentication Key' (for git push)." -ForegroundColor Gray
    Write-Host "   2. (Optional, for Verified badge) Add the same key as 'Signing Key'." -ForegroundColor Gray
    Write-Host "   3. Return here and press ENTER." -ForegroundColor Gray
    
    Start-Sleep -Seconds 1
    Open-Target "https://github.com/settings/ssh/new"
    
    Read-Host "`n   Press ENTER after adding the key on GitHub..."

    # 5. Test Connection
    $null = Test-GitHub-Connection -Alias $Alias

    # 6. Save Profile
    $NewProfile = [PSCustomObject]@{
        alias = $Alias
        userName = $UName
        userEmail = $UEmail
        keyPath = $KeyPath
        githubUsername = ""
        created = (Get-Date).ToString("yyyy-MM-dd HH:mm")
    }
    $Profiles += $NewProfile
    Save-Profiles $Profiles
    Write-Color "`n   [✔] Account '$Alias' saved!" -Color Green

    $Curr = Get-Git-Current
    if ($Curr.Name -eq "Not Set" -or $Curr.Name -eq $null) {
        Apply-ProfileIndex -Index ($Profiles.Count - 1)
    } else {
        $Active = Get-ActiveProfile -Profiles $Profiles
        if ($Active) {
            Sync-GlobalGitHubRouting -Alias $Active.alias -KeyPath $Active.keyPath
        }
    }
}

function Apply-ProfileIndex {
    param([int]$Index)
    $Profiles = @(Load-Profiles)
    if ($Index -lt 0 -or $Index -ge $Profiles.Count) { return }

    $Selected = $Profiles[$Index]

    # 1. Global identity + SSH signing + clear stale local overrides
    Sync-Git-Identity -UserName $Selected.userName -UserEmail $Selected.userEmail -KeyPath $Selected.keyPath -Quiet

    # 2. Self-heal ~/.ssh/config
    Ensure-SshReady -Alias $Selected.alias -KeyPath $Selected.keyPath

    # 3. Global multi-repo GitHub routing (~/.git-switch/active.gitconfig)
    Sync-GlobalGitHubRouting -Alias $Selected.alias -KeyPath $Selected.keyPath

    # 4. Sync/clear HTTPS credentials & gh CLI silently
    Sync-HttpsCredentials -Alias $Selected.alias -GitHubUser $Selected.githubUsername -FallbackUser $Selected.userName -Quiet

    # 5. Clean embedded-username or orphaned-alias remotes in current repo
    Clear-EmbeddedHttpsRemote -Alias $Selected.alias

    # 6. Offer to fix unpushed commits only if any have wrong author/signature
    Invoke-FixUnpushedCommits -TargetName $Selected.userName -TargetEmail $Selected.userEmail

    $script:StatusMsg = "✔ Switched to $($Selected.alias) ($($Selected.userName) <$($Selected.userEmail)>)"
    $script:StatusColor = "Green"
}

function Remove-Profile-Action {
    $Profiles = @(Load-Profiles)
    if ($Profiles.Count -eq 0) { Write-Color "`n   [!] No accounts to remove." "Yellow"; return }

    $items = @()
    foreach ($p in $Profiles) {
        $items += ("{0,-15} {1}" -f $p.alias, $p.userEmail)
    }
    $items += "← Back"

    $Idx = Select-ArrowMenu -Title "REMOVE ACCOUNT" -Items $items
    if ($Idx -lt 0 -or $Idx -ge $Profiles.Count) { return }

    $Removed = $Profiles[$Idx]
    $PrevActive = Get-ActiveProfile -Profiles $Profiles
    $PrevActiveAlias = if ($PrevActive) { $PrevActive.alias } else { "" }
    
    Write-Color "`n   Deleting '$($Removed.alias)' ($($Removed.userEmail))..." "Red"
    $Confirm = Read-Host "   Type 'DELETE' to confirm"
    if ($Confirm -ne "DELETE") { return }

    # 1. Remove SSH Keys
    if ($Removed.keyPath) {
        if (Test-Path $Removed.keyPath) { Remove-Item $Removed.keyPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path "$($Removed.keyPath).pub") { Remove-Item "$($Removed.keyPath).pub" -Force -ErrorAction SilentlyContinue }
    }

    # 2. Remove from SSH Config & Saved HTTPS PAT
    Remove-From-SSH-Config -Alias $Removed.alias -Quiet
    Remove-ProfileToken -Alias $Removed.alias

    # 3. Remove from JSON
    $NewProfiles = @($Profiles | Where-Object { $_.alias -ne $Removed.alias })
    if ($NewProfiles.Count -eq 0) {
        "[]" | Set-Content $ProfilesFile -Encoding UTF8
    } else {
        Save-Profiles $NewProfiles
    }

    # 4. Check & Clear Global/Local Config, Routing, Signing Key, and Cached HTTPS Credential
    $Curr = Get-Git-Current
    if ($PrevActiveAlias -eq $Removed.alias -or ([string]::IsNullOrWhiteSpace($PrevActiveAlias) -and ($Curr.Name -eq $Removed.userName -or $Curr.Email -eq $Removed.userEmail))) {
        git config --global --unset user.name 2>$null
        git config --global --unset user.email 2>$null
        Clear-GlobalGitHubRouting
        Clear-GitHubHttpsCredential
    } else {
        $Active = Get-ActiveProfile -Profiles $NewProfiles
        if ($Active) {
            Sync-GlobalGitHubRouting -Alias $Active.alias -KeyPath $Active.keyPath
        }
    }
    $currSKey = git config --global user.signingkey 2>$null
    if ($Removed.keyPath -and $currSKey -eq "$($Removed.keyPath).pub") {
        git config --global --unset user.signingkey 2>$null
        git config --global --unset commit.gpgsign 2>$null
    }
    if (Test-InsideGitRepo) {
        $localEmail = git config --local user.email 2>$null
        if ($localEmail -eq $Removed.userEmail) {
            git config --local --unset user.name 2>$null
            git config --local --unset user.email 2>$null
        }
        $localSKey = git config --local user.signingkey 2>$null
        if ($Removed.keyPath -and $localSKey -eq "$($Removed.keyPath).pub") {
            git config --local --unset user.signingkey 2>$null
            git config --local --unset commit.gpgsign 2>$null
        }
    }

    $script:StatusMsg = "✔ Removed account '$($Removed.alias)'."
    $script:StatusColor = "Green"
    Write-Color "   [✔] Account '$($Removed.alias)' removed." "Green"
}

function Toggle-SshRewrite {
    if (Test-SshRewriteEnabled) {
        New-Item -ItemType File -Path $NoSshRewriteFlag -Force | Out-Null
        Clear-GlobalGitHubRouting
        Write-Color "   [✔] Auto-Route GitHub HTTPS -> SSH disabled (using raw repo remotes / HTTPS PAT)." "Yellow"
    } else {
        if (Test-Path $NoSshRewriteFlag) { Remove-Item $NoSshRewriteFlag -Force -ErrorAction SilentlyContinue }
        $Active = Get-ActiveProfile
        if ($Active) {
            Sync-GlobalGitHubRouting -Alias $Active.alias -KeyPath $Active.keyPath
        }
        Write-Color "   [✔] Auto-Route GitHub HTTPS -> SSH enabled (all repos push as active account)." "Green"
    }
}

function Toggle-SSH-Signing {
    if (Test-CommitSigningEnabled) {
        git config --global commit.gpgsign false
        if (Test-InsideGitRepo) { git config --local --unset-all commit.gpgsign 2>$null }
        Write-Color "   [✔] SSH Commit Signing disabled (commit.gpgsign = false)." "Yellow"
    } else {
        git config --global gpg.format ssh
        git config --global commit.gpgsign true
        if (Test-InsideGitRepo) {
            git config --local --unset-all gpg.format 2>$null
            git config --local --unset-all user.signingkey 2>$null
            git config --local --unset-all commit.gpgsign 2>$null
        }
        $Matched = Get-ActiveProfile
        if ($Matched -and $Matched.keyPath -and (Test-Path "$($Matched.keyPath).pub")) {
            $pubKey = "$($Matched.keyPath).pub"
            git config --global user.signingkey "$pubKey"
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
            $Active = Get-ActiveProfile -Profiles $Profiles
            if ($Active) {
                Sync-GlobalGitHubRouting -Alias $Active.alias -KeyPath $Active.keyPath
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

# -------------------------- ARROW-KEY TUI HELPERS --------------------------
function Read-NavKey {
    try {
        $k = [Console]::ReadKey($true)
        switch ($k.Key) {
            "UpArrow"   { return "UP" }
            "DownArrow" { return "DOWN" }
            "Enter"     { return "ENTER" }
            "Escape"    { return "ESC" }
            default {
                $ch = $k.KeyChar.ToString()
                if ($ch -eq "k" -or $ch -eq "K") { return "UP" }
                if ($ch -eq "j" -or $ch -eq "J") { return "DOWN" }
                if ($ch -eq "q" -or $ch -eq "Q" -or $ch -eq "0") { return "ESC" }
                return $ch
            }
        }
    } catch {
        $line = Read-Host
        if ([string]::IsNullOrEmpty($line)) { return "ENTER" }
        return $line
    }
}

function Select-ArrowMenu {
    param([string]$Title, [string[]]$Items)
    if (-not $Items -or $Items.Count -eq 0) { return -1 }
    $selected = 0
    $origCursor = $true
    try { $origCursor = [Console]::CursorVisible; [Console]::CursorVisible = $false } catch {}
    try {
        while ($true) {
            Clear-Host
            Write-Host ""
            Draw-Header $Title
            Write-Host ""
            for ($i = 0; $i -lt $Items.Count; $i++) {
                if ($i -eq $selected) {
                    Write-Host ("   ❯ {0}" -f $Items[$i]) -ForegroundColor Cyan
                } else {
                    Write-Host ("     {0}" -f $Items[$i]) -ForegroundColor Gray
                }
            }
            Write-Host ""
            Write-Host "   ↑/↓ Move   Enter Select   Esc Back" -ForegroundColor DarkGray

            $key = Read-NavKey
            switch ($key) {
                "UP"    { $selected = ($selected - 1 + $Items.Count) % $Items.Count }
                "DOWN"  { $selected = ($selected + 1) % $Items.Count }
                "ENTER" { return $selected }
                "ESC"   { return -1 }
            }
        }
    } finally {
        try { [Console]::CursorVisible = $origCursor } catch {}
    }
}

function Show-Settings-Action {
    $selected = 0
    $origCursor = $true
    try { $origCursor = [Console]::CursorVisible; [Console]::CursorVisible = $false } catch {}
    try {
        while ($true) {
            $RouteState = if (Test-SshRewriteEnabled) { "ON" } else { "OFF" }
            $SignState = if (Test-CommitSigningEnabled) { "ON" } else { "OFF" }
            $items = @(
                "Auto-Route GitHub HTTPS -> SSH  [$RouteState]",
                "SSH Commit Signing              [$SignState]",
                "Manage HTTPS Credentials (PAT)",
                "IDE Git Auth Sync (github.gitAuthentication)",
                "Backup Profiles",
                "Open profiles.json",
                "Open .ssh folder",
                "← Back"
            )

            Clear-Host
            Write-Host ""
            Draw-Header "SETTINGS"
            Write-Host ""
            for ($i = 0; $i -lt $items.Count; $i++) {
                if ($i -eq $selected) {
                    Write-Host ("   ❯ {0}" -f $items[$i]) -ForegroundColor Cyan
                } else {
                    Write-Host ("     {0}" -f $items[$i]) -ForegroundColor Gray
                }
            }
            Write-Host ""
            Write-Host "   ↑/↓ Move   Enter Select   Esc Back" -ForegroundColor DarkGray

            $key = Read-NavKey
            switch ($key) {
                "UP"   { $selected = ($selected - 1 + $items.Count) % $items.Count }
                "DOWN" { $selected = ($selected + 1) % $items.Count }
                "ESC"  { return }
                "ENTER" {
                    try { [Console]::CursorVisible = $origCursor } catch {}
                    switch ($selected) {
                        0 { Toggle-SshRewrite }
                        1 { Toggle-SSH-Signing }
                        2 { Manage-HttpsCredentials-Action; Wait-KeyPress }
                        3 { Sync-IdeGitAuth-Action; Wait-KeyPress }
                        4 {
                            $Bak = Join-Path $BaseDir "backup_$(Get-Date -Format 'yyyyMMdd_HHmm').json"
                            Copy-Item $ProfilesFile $Bak
                            Write-Color "`n   [✔] Backup created: $Bak" "Green"
                            Wait-KeyPress
                        }
                        5 { Open-Target $ProfilesFile }
                        6 { Open-Target $SSHDir }
                        7 { return }
                    }
                    try { [Console]::CursorVisible = $false } catch {}
                }
            }
        }
    } finally {
        try { [Console]::CursorVisible = $origCursor } catch {}
    }
}


# -------------------------- MAIN UI --------------------------

function Show-Home {
    param([int]$SelectedIndex = 0)

    $Curr = Get-Git-Current
    $Profiles = @(Load-Profiles)
    $Active = Get-ActiveProfile -Profiles $Profiles
    $ActiveAlias = if ($Active) { $Active.alias } else { "" }

    # Auto-heal global routing if active profile is set (e.g. upgraded from v2.3.0)
    Ensure-ActiveRoutingSynced -ActiveProfile $Active

    $hasLocalOverride = $false
    $LocalName = ""
    $LocalEmail = ""
    if (Test-InsideGitRepo) {
        $LocalName = git config --local user.name 2>$null
        $LocalEmail = git config --local user.email 2>$null
        if (($LocalEmail -and $LocalEmail -ne $Curr.Email) -or ($LocalName -and $LocalName -ne $Curr.Name)) {
            $hasLocalOverride = $true
        }
    }

    Write-Host ""
    Draw-Border-Top 62 "Cyan"
    Draw-Line "git-switch v2.5" 62 "Cyan" "White"
    if ($hasLocalOverride) {
        $dName = if ($LocalName) { $LocalName } else { $Curr.Name }
        $dEmail = if ($LocalEmail) { $LocalEmail } else { $Curr.Email }
        Draw-Line "! Pushing as: $dName <$dEmail> (local)" 62 "Cyan" "Yellow"
    } elseif ($Curr.Name -eq "Not Set" -and $Curr.Email -eq "Not Set") {
        Draw-Line "Pushing as: (not set)" 62 "Cyan" "Yellow"
    } elseif ($ActiveAlias) {
        Draw-Line "● Pushing as: $ActiveAlias ($($Curr.Name) <$($Curr.Email)>)" 62 "Cyan" "Green"
    } else {
        Draw-Line "● Pushing as: $($Curr.Name) <$($Curr.Email)>" 62 "Cyan" "Green"
    }
    Draw-Border-Bottom 62 "Cyan"

    if ($hasLocalOverride) {
        Write-Color "  [!] Local repo config overrides global — select account to sync" -Color Yellow
    }

    if (Test-InsideGitRepo) {
        $OriginUrl = git remote get-url --push origin 2>$null
        if (-not $OriginUrl) { $OriginUrl = git remote get-url origin 2>$null }
        if ($OriginUrl -and $ActiveAlias) {
            $rinfo = Get-GitHubRemoteInfo -Url $OriginUrl
            if ($rinfo.Type -eq "ssh_alias" -and $rinfo.SshAlias -ne $ActiveAlias) {
                Write-Color "  [!] Repo remote uses '$($rinfo.SshAlias)' instead of '$ActiveAlias' — select account to sync" -Color Yellow
            } elseif (($rinfo.Type -eq "https" -or $rinfo.Type -eq "ssh_default") -and (Test-SshRewriteEnabled)) {
                Write-Color "  [!] Repo remote not yet routed to '$ActiveAlias' — select account to sync" -Color Yellow
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($script:StatusMsg)) {
        Write-Color "  $($script:StatusMsg)" -Color $script:StatusColor
    }

    Write-Host ""
    Write-Host "  ACCOUNTS" -ForegroundColor DarkGray
    if ($Profiles.Count -eq 0) {
        Write-Host "    (no accounts yet — select '+ Add account' below)" -ForegroundColor Gray
    } else {
        for ($i = 0; $i -lt $Profiles.Count; $i++) {
            $p = $Profiles[$i]
            $isActive = ($ActiveAlias -and $p.alias -eq $ActiveAlias -and -not $hasLocalOverride)
            $badge = if ($isActive) { " (active)" } else { "" }
            if ($i -eq $SelectedIndex) {
                if ($isActive) {
                    Write-Host ("  ❯ ● {0,-15} " -f $p.alias) -NoNewline -ForegroundColor Cyan
                    Write-Host $p.userEmail -NoNewline -ForegroundColor White
                    Write-Host $badge -ForegroundColor Green
                } else {
                    Write-Host ("  ❯   {0,-15} " -f $p.alias) -NoNewline -ForegroundColor Cyan
                    Write-Host $p.userEmail -ForegroundColor White
                }
            } else {
                if ($isActive) {
                    Write-Host ("    ● {0,-15} " -f $p.alias) -NoNewline -ForegroundColor Green
                    Write-Host $p.userEmail -NoNewline -ForegroundColor DarkGray
                    Write-Host $badge -ForegroundColor Green
                } else {
                    Write-Host ("      {0,-15} " -f $p.alias) -NoNewline -ForegroundColor White
                    Write-Host $p.userEmail -ForegroundColor DarkGray
                }
            }
        }
    }

    Write-Host ""
    Write-Host "  ACTIONS" -ForegroundColor DarkGray
    $actions = @("+ Add account", "- Remove account", "✓ Test connection", "⚙ Settings", "× Exit")
    for ($a = 0; $a -lt $actions.Count; $a++) {
        $rowIdx = $Profiles.Count + $a
        if ($rowIdx -eq $SelectedIndex) {
            Write-Host ("  ❯ {0}" -f $actions[$a]) -ForegroundColor Cyan
        } else {
            Write-Host ("    {0}" -f $actions[$a]) -ForegroundColor Gray
        }
    }

    Write-Host ""
    Write-Host "  ↑/↓ Move   Enter Select   q Quit" -ForegroundColor DarkGray
}

# ================= MAIN EXECUTION LOOP =================
Initialize-System
$Running = $true
$Selected = 0

$InitProfiles = @(Load-Profiles)
$InitActive = Get-ActiveProfile -Profiles $InitProfiles
if ($InitActive) {
    for ($i = 0; $i -lt $InitProfiles.Count; $i++) {
        if ($InitProfiles[$i].alias -eq $InitActive.alias) { $Selected = $i; break }
    }
}

$OrigCursorVisible = $true
try { $OrigCursorVisible = [Console]::CursorVisible; [Console]::CursorVisible = $false } catch {}
try {
    while ($Running) {
        $Profiles = @(Load-Profiles)
        $Total = $Profiles.Count + 5
        if ($Selected -ge $Total) { $Selected = $Total - 1 }

        Clear-Host
        Show-Home -SelectedIndex $Selected

        $Key = Read-NavKey
        $script:StatusMsg = ""
        $script:StatusColor = "Green"

        switch ($Key) {
            "UP"   { $Selected = ($Selected - 1 + $Total) % $Total }
            "DOWN" { $Selected = ($Selected + 1) % $Total }
            "ESC"  { $Running = $false }
            "ENTER" {
                try { [Console]::CursorVisible = $OrigCursorVisible } catch {}
                if ($Selected -lt $Profiles.Count) {
                    $script:NeedPause = $false
                    Apply-ProfileIndex -Index $Selected
                    if ($script:NeedPause) { Wait-KeyPress }
                } else {
                    $act = $Selected - $Profiles.Count
                    switch ($act) {
                        0 { Add-Profile-Action; Wait-KeyPress }
                        1 { Remove-Profile-Action; Wait-KeyPress }
                        2 { Test-Connection-Action; Wait-KeyPress }
                        3 { Show-Settings-Action }
                        4 { $Running = $false }
                    }
                }
                if ($Running) {
                    try { [Console]::CursorVisible = $false } catch {}
                }
            }
        }
    }
} finally {
    try { [Console]::CursorVisible = $OrigCursorVisible } catch {}
}