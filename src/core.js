"use strict";

const { execFileSync, spawn, spawnSync } = require("child_process");
const fs = require("fs");
const https = require("https");
const os = require("os");
const path = require("path");

const IS_WIN = process.platform === "win32";
const IS_MAC = process.platform === "darwin";

function getPaths() {
  const home = os.homedir();
  const baseDir = path.join(home, ".git-switch");
  const sshDir = path.join(home, ".ssh");
  return {
    home,
    baseDir,
    profilesFile: path.join(baseDir, "profiles.json"),
    tokensDir: path.join(baseDir, "tokens"),
    activeGitConfig: path.join(baseDir, "active.gitconfig"),
    noSshRewriteFlag: path.join(baseDir, "no-ssh-rewrite"),
    sshDir,
    sshConfigFile: path.join(sshDir, "config"),
  };
}

function chmodSafe(target, mode) {
  if (!IS_WIN) {
    try {
      fs.chmodSync(target, mode);
    } catch {}
  }
}

function initializeSystem() {
  const p = getPaths();
  fs.mkdirSync(p.baseDir, { recursive: true });
  fs.mkdirSync(p.tokensDir, { recursive: true });
  chmodSafe(p.tokensDir, 0o700);
  if (!fs.existsSync(p.profilesFile)) {
    fs.writeFileSync(p.profilesFile, "[]\n", "utf8");
  }
  fs.mkdirSync(p.sshDir, { recursive: true });
  chmodSafe(p.sshDir, 0o700);
  if (!fs.existsSync(p.sshConfigFile)) {
    fs.writeFileSync(p.sshConfigFile, "", "utf8");
  }
  chmodSafe(p.sshConfigFile, 0o600);
}

// -------------------------- GIT HELPERS --------------------------
function runGit(args, opts = {}) {
  const res = spawnSync("git", args, {
    encoding: "utf8",
    stdio: ["pipe", "pipe", "pipe"],
    ...opts,
  });
  return {
    ok: res.status === 0,
    status: res.status,
    stdout: (res.stdout || "").trim(),
    stderr: (res.stderr || "").trim(),
  };
}

function hasCommand(cmd) {
  const probe = IS_WIN ? "where" : "which";
  return spawnSync(probe, [cmd], { stdio: "ignore" }).status === 0;
}

function isInsideGitRepo() {
  const r = runGit(["rev-parse", "--is-inside-work-tree"]);
  return r.ok && r.stdout === "true";
}

function getRepoName() {
  if (!isInsideGitRepo()) return "";
  const r = runGit(["rev-parse", "--show-toplevel"]);
  return r.ok && r.stdout ? path.basename(r.stdout) : path.basename(process.cwd());
}

function getGitCurrent() {
  const name = runGit(["config", "--global", "user.name"]).stdout || "Not Set";
  const email = runGit(["config", "--global", "user.email"]).stdout || "Not Set";
  return { name, email };
}

function getGitLocal() {
  if (!isInsideGitRepo()) return { name: "", email: "" };
  return {
    name: runGit(["config", "--local", "user.name"]).stdout || "",
    email: runGit(["config", "--local", "user.email"]).stdout || "",
  };
}

function isCommitSigningEnabled() {
  const g = runGit(["config", "--global", "commit.gpgsign"]).stdout;
  const l = isInsideGitRepo() ? runGit(["config", "--local", "commit.gpgsign"]).stdout : "";
  return g === "true" || l === "true";
}

function isSshRewriteEnabled() {
  return !fs.existsSync(getPaths().noSshRewriteFlag);
}

// -------------------------- PROFILES JSON --------------------------
function loadProfiles() {
  initializeSystem();
  const { profilesFile } = getPaths();
  try {
    const raw = fs.readFileSync(profilesFile, "utf8").replace(/^\uFEFF/, "");
    if (!raw.trim()) return [];
    const data = JSON.parse(raw);
    if (Array.isArray(data)) return data;
    return data ? [data] : [];
  } catch {
    return [];
  }
}

function saveProfiles(profiles) {
  initializeSystem();
  const { profilesFile } = getPaths();
  fs.writeFileSync(profilesFile, JSON.stringify(profiles, null, 2) + "\n", "utf8");
}

function getActiveProfile(profiles = null) {
  const list = profiles || loadProfiles();
  if (!list.length) return null;

  // 1. Match by active SSH signingkey
  const skey = runGit(["config", "--global", "user.signingkey"]).stdout;
  if (skey) {
    const byKey = list.find((p) => p.keyPath && `${p.keyPath}.pub` === skey);
    if (byKey) return byKey;
  }

  // 2. Match by active.gitconfig header
  const { activeGitConfig } = getPaths();
  if (fs.existsSync(activeGitConfig)) {
    try {
      const firstLine = fs.readFileSync(activeGitConfig, "utf8").split(/\r?\n/)[0] || "";
      const m = firstLine.match(/^# Active profile:\s*(.+)$/);
      if (m) {
        const byHeader = list.find((p) => p.alias === m[1].trim());
        if (byHeader) return byHeader;
      }
    } catch {}
  }

  // 3. Match by email + name, then email
  const curr = getGitCurrent();
  if (curr.email && curr.email !== "Not Set") {
    const exact = list.find((p) => p.userEmail === curr.email && p.userName === curr.name);
    if (exact) return exact;
    const byEmail = list.find((p) => p.userEmail === curr.email);
    if (byEmail) return byEmail;
  }
  return null;
}

// -------------------------- TOKENS / HTTPS --------------------------
function tokenFilePath(alias) {
  return path.join(getPaths().tokensDir, `${alias}.token`);
}

function profileHasToken(alias) {
  if (!alias) return false;
  const tp = tokenFilePath(alias);
  try {
    return fs.existsSync(tp) && fs.statSync(tp).size > 0;
  } catch {
    return false;
  }
}

function saveProfileToken(alias, token) {
  if (!alias || !token) return;
  const { tokensDir } = getPaths();
  fs.mkdirSync(tokensDir, { recursive: true });
  chmodSafe(tokensDir, 0o700);
  const tp = tokenFilePath(alias);
  fs.writeFileSync(tp, token.trim(), { encoding: "utf8", mode: 0o600 });
  chmodSafe(tp, 0o600);
}

function loadProfileToken(alias) {
  const tp = tokenFilePath(alias);
  if (!fs.existsSync(tp)) return "";
  return fs.readFileSync(tp, "utf8").replace(/[\r\n]/g, "").trim();
}

function deleteProfileToken(alias) {
  const tp = tokenFilePath(alias);
  try {
    if (fs.existsSync(tp)) fs.unlinkSync(tp);
  } catch {}
}

function hasOsxKeychainHelper() {
  if (!IS_MAC) return false;
  const execPath = runGit(["--exec-path"]).stdout;
  if (execPath && fs.existsSync(path.join(execPath, "git-credential-osxkeychain"))) {
    return true;
  }
  return hasCommand("git-credential-osxkeychain");
}

function hasActiveGitCredentialHelper() {
  const evalHelper = (key) => {
    const r = runGit(["config", "--get-all", key]);
    if (!r.ok) return "";
    let active = "";
    for (const line of r.stdout.split(/\r?\n/)) {
      active = line.trim() === "" ? "" : line.trim();
    }
    return active;
  };
  return Boolean(evalHelper("credential.helper") || evalHelper("credential.https://github.com.helper"));
}

function clearGitHubHttpsCredential() {
  const payload = "protocol=https\nhost=github.com\n\n";
  spawnSync("git", ["credential", "reject"], { input: payload, stdio: ["pipe", "ignore", "ignore"] });
  if (!hasActiveGitCredentialHelper() && hasOsxKeychainHelper()) {
    spawnSync("git", ["credential-osxkeychain", "erase"], { input: payload, stdio: ["pipe", "ignore", "ignore"] });
  }
}

function applyGitHubHttpsCredential(ghUser, pat) {
  if (!ghUser || !pat) return "error";
  if (!hasActiveGitCredentialHelper()) return "no_helper";
  clearGitHubHttpsCredential();
  const payload = `protocol=https\nhost=github.com\nusername=${ghUser}\npassword=${pat}\n\n`;
  const r = spawnSync("git", ["credential", "approve"], {
    input: payload,
    stdio: ["pipe", "ignore", "ignore"],
  });
  return r.status === 0 ? "ok" : "error";
}

function syncHttpsCredentials(alias, ghUser, fallbackUser) {
  const effectiveUser = ghUser || fallbackUser;
  let result = "cleared";
  if (profileHasToken(alias)) {
    const pat = loadProfileToken(alias);
    if (pat && effectiveUser) {
      result = applyGitHubHttpsCredential(effectiveUser, pat);
    }
  } else {
    clearGitHubHttpsCredential();
  }

  if (ghUser && hasCommand("gh")) {
    spawnSync("gh", ["auth", "switch", "--user", ghUser], { stdio: "ignore" });
  }
  return result;
}

// -------------------------- SSH & ROUTING --------------------------
function generateSshKey(email, alias) {
  const { sshDir } = getPaths();
  const keyPath = path.join(sshDir, `id_rsa_${alias}`);
  if (fs.existsSync(keyPath)) {
    return { ok: true, keyPath, existed: true };
  }
  const r = spawnSync("ssh-keygen", ["-t", "rsa", "-b", "4096", "-C", email, "-f", keyPath, "-N", ""], {
    stdio: "ignore",
  });
  if (r.status === 0 && fs.existsSync(keyPath)) {
    chmodSafe(keyPath, 0o600);
    chmodSafe(`${keyPath}.pub`, 0o644);
    if (IS_MAC) {
      const add1 = spawnSync("ssh-add", ["--apple-use-keychain", keyPath], { stdio: "ignore" });
      if (add1.status !== 0) spawnSync("ssh-add", [keyPath], { stdio: "ignore" });
    } else {
      spawnSync("ssh-add", [keyPath], { stdio: "ignore" });
    }
    return { ok: true, keyPath, existed: false };
  }
  return { ok: false, keyPath: null, existed: false };
}

function removeFromSshConfig(alias) {
  const { sshConfigFile } = getPaths();
  if (!fs.existsSync(sshConfigFile)) return;
  const targetHeader = `# Git profile: ${alias}`;
  const lines = fs.readFileSync(sshConfigFile, "utf8").split(/\r?\n/);
  const out = [];
  let skip = false;
  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed === targetHeader) {
      skip = true;
      continue;
    }
    if (skip) {
      if (trimmed === "") {
        skip = false;
        continue;
      }
      if ((trimmed.startsWith("Host ") && trimmed !== `Host github.com-${alias}`) || trimmed.startsWith("# Git profile:")) {
        skip = false;
        out.push(line);
      }
      continue;
    }
    out.push(line);
  }
  fs.writeFileSync(sshConfigFile, out.join("\n").replace(/\n{3,}/g, "\n\n"), "utf8");
  chmodSafe(sshConfigFile, 0o600);
}

function updateSshConfig(alias, keyPath) {
  const { sshConfigFile } = getPaths();
  removeFromSshConfig(alias);
  const blockLines = [
    "",
    `# Git profile: ${alias}`,
    `Host github.com-${alias}`,
    "    HostName github.com",
    "    User git",
    `    IdentityFile "${keyPath}"`,
    "    IdentitiesOnly yes",
  ];
  if (IS_MAC) {
    blockLines.push("    AddKeysToAgent yes");
    blockLines.push("    UseKeychain yes");
  }
  blockLines.push("");
  fs.appendFileSync(sshConfigFile, blockLines.join("\n"), "utf8");
  chmodSafe(sshConfigFile, 0o600);
}

function ensureSshReady(alias, keyPath) {
  if (!alias || !keyPath || !fs.existsSync(keyPath)) return;
  const { sshConfigFile } = getPaths();
  const content = fs.existsSync(sshConfigFile) ? fs.readFileSync(sshConfigFile, "utf8") : "";
  const hostRe = new RegExp(`^Host\\s+github\\.com-${alias.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*$`, "m");
  if (!hostRe.test(content)) {
    updateSshConfig(alias, keyPath);
  }
  if (IS_MAC) {
    const a1 = spawnSync("ssh-add", ["--apple-use-keychain", keyPath], { stdio: "ignore" });
    if (a1.status !== 0) spawnSync("ssh-add", [keyPath], { stdio: "ignore" });
  } else {
    spawnSync("ssh-add", [keyPath], { stdio: "ignore" });
  }
}

function ensureGitIncludePath() {
  const { activeGitConfig } = getPaths();
  const normalized = activeGitConfig.replace(/\\/g, "/");
  const existing = runGit(["config", "--global", "--get-all", "include.path"]);
  const lines = existing.ok ? existing.stdout.split(/\r?\n/).map((s) => s.trim()) : [];
  if (!lines.includes(normalized) && !lines.includes(activeGitConfig)) {
    runGit(["config", "--global", "--add", "include.path", normalized]);
  }
}

function clearGlobalGitHubRouting() {
  const { activeGitConfig } = getPaths();
  fs.writeFileSync(activeGitConfig, "# Managed by git-switch (inactive)\n", "utf8");
}

function syncGlobalGitHubRouting(alias, keyPath) {
  const { activeGitConfig } = getPaths();
  ensureGitIncludePath();

  if (!isSshRewriteEnabled() || !alias || !keyPath || !fs.existsSync(keyPath)) {
    clearGlobalGitHubRouting();
    return;
  }

  const profiles = loadProfiles();
  const rules = [
    "https://github.com/",
    "http://github.com/",
    "https://www.github.com/",
    "http://www.github.com/",
    "git@github.com:",
    "ssh://git@github.com/",
    "ssh://git@github.com:22/",
  ];

  for (const p of profiles) {
    if (p.alias && p.alias !== alias) {
      rules.push(`git@github.com-${p.alias}:`);
      rules.push(`ssh://git@github.com-${p.alias}/`);
      rules.push(`ssh://git@github.com-${p.alias}:22/`);
    }
    if (p.githubUsername) {
      rules.push(`https://${p.githubUsername}@github.com/`);
    }
  }

  const uniqueRules = Array.from(new Set(rules));
  const lines = [
    `# Active profile: ${alias}`,
    `# Managed by git-switch — routes all GitHub repos to github.com-${alias}`,
    `[url "git@github.com-${alias}:"]`,
    ...uniqueRules.map((r) => `\tinsteadOf = ${r}`),
    "",
  ];
  fs.writeFileSync(activeGitConfig, lines.join("\n"), "utf8");
}

function ensureActiveRoutingSynced(activeProfile) {
  if (!activeProfile || !activeProfile.alias || !isSshRewriteEnabled()) return;
  const { activeGitConfig } = getPaths();
  let needsSync = !fs.existsSync(activeGitConfig);
  if (!needsSync) {
    const firstLine = (fs.readFileSync(activeGitConfig, "utf8").split(/\r?\n/)[0] || "").trim();
    if (firstLine !== `# Active profile: ${activeProfile.alias}`) {
      needsSync = true;
    }
  }
  if (needsSync) {
    ensureSshReady(activeProfile.alias, activeProfile.keyPath);
    syncGlobalGitHubRouting(activeProfile.alias, activeProfile.keyPath);
  }
}

function classifyGitHubRemote(url) {
  const u = (url || "").trim();
  if (!u) return { type: "other", repoPath: "", sshAlias: "" };

  let m = u.match(/^https?:\/\/(?:[^/@]+@)?(?:www\.)?github\.com(?::\d+)?\/(.+)$/i);
  if (m) return { type: "https", repoPath: m[1].replace(/\/+$/, ""), sshAlias: "" };

  m = u.match(/^git@github\.com:(.+)$/i);
  if (m) return { type: "ssh_default", repoPath: m[1].replace(/\/+$/, ""), sshAlias: "" };

  m = u.match(/^ssh:\/\/git@github\.com(?::\d+)?\/(.+)$/i);
  if (m) return { type: "ssh_default", repoPath: m[1].replace(/\/+$/, ""), sshAlias: "" };

  m = u.match(/^git@github\.com-([^:/]+):(.+)$/i);
  if (m) return { type: "ssh_alias", repoPath: m[2].replace(/\/+$/, ""), sshAlias: m[1] };

  m = u.match(/^ssh:\/\/git@github\.com-([^:/]+)(?::\d+)?\/(.+)$/i);
  if (m) return { type: "ssh_alias", repoPath: m[2].replace(/\/+$/, ""), sshAlias: m[1] };

  return { type: "other", repoPath: "", sshAlias: "" };
}

function cleanRepoRemoteForRouting(alias) {
  if (!isInsideGitRepo() || !isSshRewriteEnabled()) return;
  const raw = runGit(["config", "--local", "--get", "remote.origin.url"]).stdout;
  if (!raw) return;

  // Embedded username in HTTPS URL: https://olduser@github.com/org/repo.git -> https://github.com/org/repo.git
  const emb = raw.match(/^https?:\/\/[^/@]+@(?:www\.)?github\.com(?::\d+)?\/(.+)$/i);
  if (emb) {
    runGit(["remote", "set-url", "origin", `https://github.com/${emb[1]}`]);
    return;
  }

  // Orphaned ssh alias not in profiles.json
  const info = classifyGitHubRemote(raw);
  if (info.type === "ssh_alias" && info.sshAlias !== alias) {
    const profiles = loadProfiles();
    const known = profiles.some((p) => p.alias === info.sshAlias);
    if (!known) {
      runGit(["remote", "set-url", "origin", `git@github.com-${alias}:${info.repoPath}`]);
    }
  }
}

// -------------------------- IDENTITY & UNPUSHED COMMITS --------------------------
function syncGitIdentity(userName, userEmail, keyPath) {
  const warnings = [];
  runGit(["config", "--global", "user.name", userName]);
  runGit(["config", "--global", "user.email", userEmail]);

  if (isInsideGitRepo()) {
    // Clear stale local overrides so global active profile governs all repos cleanly
    runGit(["config", "--local", "--unset-all", "user.name"]);
    runGit(["config", "--local", "--unset-all", "user.email"]);
    runGit(["config", "--local", "--unset-all", "gpg.format"]);
    runGit(["config", "--local", "--unset-all", "user.signingkey"]);
    runGit(["config", "--local", "--unset-all", "commit.gpgsign"]);

    const localSshCmd = runGit(["config", "--local", "core.sshCommand"]).stdout;
    if (localSshCmd) {
      warnings.push(`Local core.sshCommand is set (${localSshCmd}) and may override ~/.ssh/config.`);
    }
  }

  const pubKey = keyPath ? `${keyPath}.pub` : "";
  const gSign = runGit(["config", "--global", "commit.gpgsign"]).stdout;
  if (pubKey && fs.existsSync(pubKey) && gSign !== "false") {
    runGit(["config", "--global", "gpg.format", "ssh"]);
    runGit(["config", "--global", "user.signingkey", pubKey]);
    runGit(["config", "--global", "commit.gpgsign", "true"]);
  }

  return warnings;
}

function applyProfile(profile) {
  const warnings = syncGitIdentity(profile.userName, profile.userEmail, profile.keyPath);
  ensureSshReady(profile.alias, profile.keyPath);
  syncGlobalGitHubRouting(profile.alias, profile.keyPath);
  syncHttpsCredentials(profile.alias, profile.githubUsername || "", profile.userName);
  cleanRepoRemoteForRouting(profile.alias);
  return { warnings };
}

function inspectUnpushedCommits(targetEmail) {
  if (!isInsideGitRepo()) return { count: 0, total: 0, hasUpstream: false, hasMerges: false };
  if (!runGit(["rev-parse", "--verify", "HEAD"]).ok) return { count: 0, total: 0, hasUpstream: false, hasMerges: false };

  const hasUpstream = runGit(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]).ok;
  const rangeArgs = hasUpstream ? ["@{u}..HEAD"] : ["HEAD", "--not", "--remotes"];
  const total = parseInt(runGit(["rev-list", "--count", ...rangeArgs]).stdout || "0", 10);
  if (!total) return { count: 0, total: 0, hasUpstream, hasMerges: false };

  const signingOn = isCommitSigningEnabled();
  const logOut = runGit(["log", "--format=%H|%ae|%G?", ...rangeArgs]).stdout;
  let mismatch = 0;
  for (const line of logOut.split(/\r?\n/)) {
    if (!line) continue;
    const [, email, sig] = line.split("|");
    if (email !== targetEmail || (signingOn && sig === "N")) {
      mismatch++;
    }
  }
  const merges = parseInt(runGit(["rev-list", "--merges", "--count", ...rangeArgs]).stdout || "0", 10);
  return { count: mismatch, total, hasUpstream, hasMerges: merges > 0 };
}

function rewriteUnpushedCommits(info) {
  if (info.hasMerges) {
    return { ok: false, message: "Unpushed range contains merge commit(s). Skipped auto-rewrite." };
  }
  const signingOn = isCommitSigningEnabled();
  if (info.total === 1) {
    const staged = runGit(["diff", "--cached", "--quiet"]);
    if (!staged.ok) {
      return { ok: false, message: "Staged changes present. Commit or unstage before amending HEAD." };
    }
    const args = ["commit", "--amend", "--reset-author", "--no-edit"];
    if (signingOn) args.push("-S");
    const r = runGit(args);
    return r.ok
      ? { ok: true, message: "Updated author & re-signed unpushed commit." }
      : { ok: false, message: "Failed to amend unpushed commit." };
  }

  if (runGit(["status", "--porcelain"]).stdout) {
    return { ok: false, message: `Uncommitted changes present. Stash/commit before rewriting ${info.total} commits.` };
  }
  const execCmd = signingOn
    ? "git commit --amend --reset-author --no-edit -S"
    : "git commit --amend --reset-author --no-edit";
  const rebaseArgs = info.hasUpstream
    ? ["rebase", "--exec", execCmd, "@{u}"]
    : ["rebase", "--root", "--exec", execCmd];
  const r = runGit(rebaseArgs);
  if (r.ok) {
    return { ok: true, message: `Updated author & re-signed ${info.total} unpushed commits.` };
  }
  runGit(["rebase", "--abort"]);
  return { ok: false, message: "Could not rewrite unpushed commits cleanly (aborted safely)." };
}

// -------------------------- CONNECTION TESTS (ASYNC) --------------------------
function testGitHubSshAsync(alias) {
  return new Promise((resolve) => {
    const hostAlias = `github.com-${alias}`;
    const child = spawn("ssh", ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new", "-T", `git@${hostAlias}`], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let out = "";
    child.stdout.on("data", (d) => (out += d.toString()));
    child.stderr.on("data", (d) => (out += d.toString()));
    child.on("error", (err) => resolve({ ok: false, login: "", output: err.message }));
    child.on("close", () => {
      if (/successfully authenticated/i.test(out)) {
        const m = out.match(/Hi ([^!]+)!/);
        resolve({ ok: true, login: m ? m[1] : "", output: out.trim() });
      } else {
        resolve({ ok: false, login: "", output: out.trim() });
      }
    });
  });
}

function testGitHubPatAsync(alias) {
  return new Promise((resolve) => {
    if (!profileHasToken(alias)) {
      resolve({ ok: false, login: "", output: "No PAT configured" });
      return;
    }
    const pat = loadProfileToken(alias);
    const req = https.request(
      "https://api.github.com/user",
      {
        method: "GET",
        headers: {
          Authorization: `Bearer ${pat}`,
          Accept: "application/vnd.github+json",
          "User-Agent": "git-switch",
        },
        timeout: 10000,
      },
      (res) => {
        let body = "";
        res.on("data", (c) => (body += c));
        res.on("end", () => {
          try {
            const data = JSON.parse(body);
            if (res.statusCode === 200 && data.login) {
              resolve({ ok: true, login: data.login, output: "" });
            } else {
              resolve({ ok: false, login: "", output: data.message || `HTTP ${res.statusCode}` });
            }
          } catch {
            resolve({ ok: false, login: "", output: `HTTP ${res.statusCode}` });
          }
        });
      }
    );
    req.on("timeout", () => {
      req.destroy();
      resolve({ ok: false, login: "", output: "Request timed out" });
    });
    req.on("error", (err) => resolve({ ok: false, login: "", output: err.message }));
    req.end();
  });
}

// -------------------------- CLIPBOARD & OPEN --------------------------
function copyToClipboard(text) {
  if (IS_MAC && hasCommand("pbcopy")) {
    return spawnSync("pbcopy", [], { input: text, stdio: ["pipe", "ignore", "ignore"] }).status === 0;
  }
  if (IS_WIN) {
    return spawnSync("clip", [], { input: text, stdio: ["pipe", "ignore", "ignore"] }).status === 0;
  }
  for (const [cmd, args] of [
    ["wl-copy", []],
    ["xclip", ["-selection", "clipboard"]],
    ["xsel", ["--clipboard", "--input"]],
  ]) {
    if (hasCommand(cmd)) {
      return spawnSync(cmd, args, { input: text, stdio: ["pipe", "ignore", "ignore"] }).status === 0;
    }
  }
  return false;
}

function openTarget(target) {
  try {
    if (IS_MAC) {
      spawn("open", [target], { detached: true, stdio: "ignore" }).unref();
      return true;
    }
    if (IS_WIN) {
      spawn("cmd", ["/c", "start", "", target], { detached: true, stdio: "ignore" }).unref();
      return true;
    }
    if (hasCommand("xdg-open")) {
      spawn("xdg-open", [target], { detached: true, stdio: "ignore" }).unref();
      return true;
    }
  } catch {}
  return false;
}

// -------------------------- IDE JSONC SYNC --------------------------
function detectIdeSettingsPaths() {
  const home = os.homedir();
  let roots;
  if (IS_MAC) {
    const base = path.join(home, "Library", "Application Support");
    roots = [
      ["VS Code", path.join(base, "Code", "User", "settings.json")],
      ["VS Code Insiders", path.join(base, "Code - Insiders", "User", "settings.json")],
      ["Cursor", path.join(base, "Cursor", "User", "settings.json")],
      ["Antigravity", path.join(base, "Antigravity", "User", "settings.json")],
      ["Windsurf", path.join(base, "Windsurf", "User", "settings.json")],
    ];
  } else if (IS_WIN) {
    const base = process.env.APPDATA || path.join(home, "AppData", "Roaming");
    roots = [
      ["VS Code", path.join(base, "Code", "User", "settings.json")],
      ["VS Code Insiders", path.join(base, "Code - Insiders", "User", "settings.json")],
      ["Cursor", path.join(base, "Cursor", "User", "settings.json")],
      ["Antigravity", path.join(base, "Antigravity", "User", "settings.json")],
      ["Windsurf", path.join(base, "Windsurf", "User", "settings.json")],
    ];
  } else {
    const base = path.join(home, ".config");
    roots = [
      ["VS Code", path.join(base, "Code", "User", "settings.json")],
      ["VS Code Insiders", path.join(base, "Code - Insiders", "User", "settings.json")],
      ["Cursor", path.join(base, "Cursor", "User", "settings.json")],
      ["Antigravity", path.join(base, "Antigravity", "User", "settings.json")],
      ["Windsurf", path.join(base, "Windsurf", "User", "settings.json")],
    ];
  }

  return roots
    .filter(([, p]) => fs.existsSync(p) || fs.existsSync(path.dirname(p)))
    .map(([name, settingsPath]) => ({ name, path: settingsPath }));
}

function maskJsoncComments(text) {
  const out = text.split("");
  const n = text.length;
  let i = 0;
  let inStr = false;
  while (i < n) {
    const c = text[i];
    if (inStr) {
      if (c === "\\" && i + 1 < n) {
        i += 2;
        continue;
      }
      if (c === '"') inStr = false;
      i++;
    } else if (c === '"') {
      inStr = true;
      i++;
    } else if (c === "/" && text[i + 1] === "/") {
      out[i] = " ";
      out[i + 1] = " ";
      i += 2;
      while (i < n && text[i] !== "\n") {
        out[i] = " ";
        i++;
      }
    } else if (c === "/" && text[i + 1] === "*") {
      out[i] = " ";
      out[i + 1] = " ";
      i += 2;
      while (i + 1 < n && !(text[i] === "*" && text[i + 1] === "/")) {
        if (text[i] !== "\n") out[i] = " ";
        i++;
      }
      if (i + 1 < n) {
        out[i] = " ";
        out[i + 1] = " ";
        i += 2;
      } else {
        if (i < n && text[i] !== "\n") out[i] = " ";
        i++;
      }
    } else {
      i++;
    }
  }
  return out.join("");
}

function stripJsonc(text) {
  return maskJsoncComments(text).replace(/,(\s*[}\]])/g, "$1");
}

function findRootAndGitAuthKey(masked) {
  let depth = 0;
  let inStr = false;
  let rootClose = -1;
  let keySpan = null;
  const keyRe = /"github\.gitAuthentication"\s*:\s*(true|false)/y;
  let i = 0;
  const n = masked.length;

  while (i < n) {
    const c = masked[i];
    if (inStr) {
      if (c === "\\" && i + 1 < n) {
        i += 2;
        continue;
      }
      if (c === '"') inStr = false;
      i++;
    } else if (c === '"') {
      if (depth === 1 && !keySpan) {
        keyRe.lastIndex = i;
        const m = keyRe.exec(masked);
        if (m) {
          const valStart = m.index + m[0].lastIndexOf(m[1]);
          keySpan = [valStart, valStart + m[1].length];
          i = keyRe.lastIndex;
          continue;
        }
      }
      inStr = true;
      i++;
    } else if (c === "{") {
      depth++;
      i++;
    } else if (c === "}") {
      depth--;
      if (depth === 0) {
        rootClose = i;
        break;
      }
      i++;
    } else {
      i++;
    }
  }
  return { rootClose, keySpan };
}

function getIdeGitAuthSetting(settingsPath) {
  if (!fs.existsSync(settingsPath)) return "unset";
  try {
    const raw = fs.readFileSync(settingsPath, "utf8").replace(/^\uFEFF/, "");
    if (!raw.trim()) return "unset";
    const data = JSON.parse(stripJsonc(raw));
    if (data && typeof data === "object" && Object.prototype.hasOwnProperty.call(data, "github.gitAuthentication")) {
      return data["github.gitAuthentication"] === false ? "false" : "true";
    }
    return "unset";
  } catch {
    return "error";
  }
}

function setIdeGitAuthSetting(settingsPath, desiredBool) {
  const desired = desiredBool ? "true" : "false";
  try {
    fs.mkdirSync(path.dirname(settingsPath), { recursive: true });
    if (!fs.existsSync(settingsPath)) {
      fs.writeFileSync(settingsPath, `{\n  "github.gitAuthentication": ${desired}\n}\n`, "utf8");
      return true;
    }
    const raw = fs.readFileSync(settingsPath, "utf8").replace(/^\uFEFF/, "");
    if (!raw.trim()) {
      fs.writeFileSync(settingsPath, `{\n  "github.gitAuthentication": ${desired}\n}\n`, "utf8");
      return true;
    }
    const masked = maskJsoncComments(raw);
    const { rootClose, keySpan } = findRootAndGitAuthKey(masked);
    let updated;
    if (keySpan) {
      updated = raw.slice(0, keySpan[0]) + desired + raw.slice(keySpan[1]);
    } else {
      if (rootClose < 0) return false;
      let j = rootClose - 1;
      while (j >= 0 && /\s/.test(masked[j])) j--;
      if (j < 0) return false;
      const needsComma = masked[j] !== "{" && masked[j] !== ",";
      const beforeBrace = needsComma
        ? raw.slice(0, j + 1) + "," + raw.slice(j + 1, rootClose)
        : raw.slice(0, rootClose);
      const sep = beforeBrace.endsWith("\n") ? "" : "\n";
      updated = `${beforeBrace}${sep}  "github.gitAuthentication": ${desired}\n${raw.slice(rootClose)}`;
    }
    // Validate JSONC
    JSON.parse(stripJsonc(updated));
    fs.writeFileSync(settingsPath, updated, "utf8");
    return true;
  } catch {
    return false;
  }
}

module.exports = {
  IS_WIN,
  IS_MAC,
  getPaths,
  initializeSystem,
  runGit,
  hasCommand,
  isInsideGitRepo,
  getRepoName,
  getGitCurrent,
  getGitLocal,
  isCommitSigningEnabled,
  isSshRewriteEnabled,
  loadProfiles,
  saveProfiles,
  getActiveProfile,
  profileHasToken,
  saveProfileToken,
  loadProfileToken,
  deleteProfileToken,
  hasActiveGitCredentialHelper,
  clearGitHubHttpsCredential,
  syncHttpsCredentials,
  generateSshKey,
  updateSshConfig,
  removeFromSshConfig,
  ensureSshReady,
  clearGlobalGitHubRouting,
  syncGlobalGitHubRouting,
  ensureActiveRoutingSynced,
  classifyGitHubRemote,
  applyProfile,
  syncGitIdentity,
  inspectUnpushedCommits,
  rewriteUnpushedCommits,
  testGitHubSshAsync,
  testGitHubPatAsync,
  copyToClipboard,
  openTarget,
  detectIdeSettingsPaths,
  getIdeGitAuthSetting,
  setIdeGitAuthSetting,
};
