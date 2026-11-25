"use strict";

const fs = require("fs");
const path = require("path");
const pkg = require("../package.json");
const core = require("./core");
const tui = require("./tui");

const { C } = tui;

let toast = null; // { text, color }

function setToast(text, color = C.green) {
  toast = { text, color };
}

function getHomeSnapshot() {
  const profiles = core.loadProfiles();
  const curr = core.getGitCurrent();
  const active = core.getActiveProfile(profiles);
  const activeAlias = active ? active.alias : "";

  // Auto-heal global routing if an active profile is already set
  core.ensureActiveRoutingSynced(active);

  const inRepo = core.isInsideGitRepo();
  const repoName = inRepo ? core.getRepoName() : "";
  const local = inRepo ? core.getGitLocal() : { name: "", email: "" };
  const hasLocalOverride =
    inRepo &&
    ((local.email && local.email !== curr.email) || (local.name && local.name !== curr.name));

  let remoteWarning = "";
  if (inRepo && activeAlias) {
    const pushUrl =
      core.runGit(["remote", "get-url", "--push", "origin"]).stdout ||
      core.runGit(["remote", "get-url", "origin"]).stdout;
    if (pushUrl) {
      const rinfo = core.classifyGitHubRemote(pushUrl);
      if (rinfo.type === "ssh_alias" && rinfo.sshAlias !== activeAlias) {
        remoteWarning = `Repo remote uses '${rinfo.sshAlias}' instead of '${activeAlias}' — press Enter on account to sync`;
      } else if ((rinfo.type === "https" || rinfo.type === "ssh_default") && core.isSshRewriteEnabled()) {
        remoteWarning = `Repo remote not yet routed to '${activeAlias}' — press Enter on account to sync`;
      }
    }
  }

  return {
    profiles,
    curr,
    active,
    activeAlias,
    inRepo,
    repoName,
    local,
    hasLocalOverride,
    remoteWarning,
    signingOn: core.isCommitSigningEnabled(),
    autoRouteOn: core.isSshRewriteEnabled(),
  };
}

function renderHome(snap, selectedIdx) {
  const w = tui.getTermWidth();
  const title = `${C.accent}${C.bold}✻ git-switch${C.reset} ${C.muted}v${pkg.version}${C.reset}`;
  const cardLines = [];

  if (snap.hasLocalOverride) {
    const dName = snap.local.name || snap.curr.name;
    const dEmail = snap.local.email || snap.curr.email;
    cardLines.push(
      `${C.yellow}▲ Pushing as${C.reset}  ${C.white}${C.bold}${tui.truncate(dName, 20)}${C.reset} ${C.yellow}<${tui.truncate(dEmail, 24)}>${C.reset}`
    );
    cardLines.push(`${C.yellow}  local .git/config override — select account to sync${C.reset}`);
  } else if (snap.curr.name === "Not Set" && snap.curr.email === "Not Set") {
    cardLines.push(`${C.yellow}○ Pushing as${C.reset}  ${C.muted}(not set — add an account below)${C.reset}`);
  } else if (snap.activeAlias) {
    cardLines.push(
      `${C.green}● Pushing as${C.reset}  ${C.white}${C.bold}${snap.activeAlias}${C.reset} ${C.muted}(${tui.truncate(`${snap.curr.name} <${snap.curr.email}>`, w - 26)})${C.reset}`
    );
  } else {
    cardLines.push(
      `${C.green}● Pushing as${C.reset}  ${C.white}${C.bold}${tui.truncate(snap.curr.name, 20)}${C.reset} ${C.muted}<${tui.truncate(snap.curr.email, 26)}>${C.reset}`
    );
  }

  // Subtle status pills row
  const pills = [];
  if (snap.inRepo) pills.push(`${C.muted}repo:${C.reset} ${C.white}${tui.truncate(snap.repoName, 18)}${C.reset}`);
  pills.push(snap.signingOn ? `${C.green}✓ signed${C.reset}` : `${C.muted}○ unsigned${C.reset}`);
  pills.push(snap.autoRouteOn ? `${C.green}✓ auto-route${C.reset}` : `${C.muted}○ manual-remote${C.reset}`);
  cardLines.push(`  ${pills.join(`  ${C.subtle}·${C.reset}  `)}`);

  const out = [];
  out.push("");
  out.push(
    tui
      .roundedBox(cardLines, w, snap.hasLocalOverride ? C.yellow : C.border, title)
      .split("\n")
      .map((l) => `  ${l}`)
      .join("\n")
  );

  if (snap.remoteWarning) {
    out.push(`  ${C.yellow}▲ ${snap.remoteWarning}${C.reset}`);
  } else if (toast) {
    out.push(`  ${toast.color}${toast.text}${C.reset}`);
  } else {
    // Fixed 1-line slot so rows never shift vertically when toast appears/disappears
    out.push("");
  }

  out.push(`  ${C.muted}${C.bold}ACCOUNTS${C.reset}`);

  if (snap.profiles.length === 0) {
    out.push(`    ${C.muted}No accounts yet — select '+ Add account' below${C.reset}`);
  } else {
    snap.profiles.forEach((p, i) => {
      const isActive = Boolean(snap.activeAlias && p.alias === snap.activeAlias && !snap.hasLocalOverride);
      const isFocus = i === selectedIdx;
      const dot = isActive ? `${C.green}●${C.reset}` : `${C.subtle}○${C.reset}`;
      const aliasPadded = tui.padRight(tui.truncate(p.alias, 16), 16);
      const emailStr = tui.truncate(p.userEmail || "", Math.max(18, w - 34));
      const activePill = isActive ? `  ${C.green}active${C.reset}` : "";
      const patPill = core.profileHasToken(p.alias) ? ` ${C.muted}PAT${C.reset}` : "";

      if (isFocus) {
        out.push(
          `  ${C.accent}${C.bold}❯${C.reset} ${dot} ${C.accentSoft}${C.bold}${aliasPadded}${C.reset} ${C.white}${emailStr}${C.reset}${activePill}${patPill}`
        );
      } else {
        out.push(
          `    ${dot} ${isActive ? C.white : C.muted}${aliasPadded}${C.reset} ${C.muted}${emailStr}${C.reset}${activePill}${patPill}`
        );
      }
    });
  }

  out.push("");
  out.push(tui.divider(w));
  out.push("");

  const actions = [
    { icon: "+", label: "Add account" },
    { icon: "−", label: "Remove account" },
    { icon: "✓", label: "Test connection" },
    { icon: "⚙", label: "Settings" },
    { icon: "×", label: "Exit" },
  ];

  actions.forEach((act, aIdx) => {
    const rowIdx = snap.profiles.length + aIdx;
    const isFocus = rowIdx === selectedIdx;
    if (isFocus) {
      out.push(`  ${C.accent}${C.bold}❯ ${act.icon} ${act.label}${C.reset}`);
    } else {
      out.push(`    ${C.muted}${act.icon} ${act.label}${C.reset}`);
    }
  });

  out.push("");
  out.push(`  ${C.muted}↑/↓ move  ·  enter select  ·  q quit${C.reset}`);
  tui.renderFrame(out.join("\n"));
}

async function selectFromList(title, items, subtitle = "") {
  if (!items.length) return -1;
  let selected = 0;
  const w = tui.getTermWidth();
  tui.hideCursor();

  while (true) {
    const out = [""];
    const headerLines = subtitle ? [`${C.muted}${subtitle}${C.reset}`] : [];
    const boxTitle = `${C.accent}${C.bold}${title}${C.reset}`;
    if (headerLines.length) {
      out.push(tui.roundedBox(headerLines, w, C.border, boxTitle).split("\n").map((l) => `  ${l}`).join("\n"));
    } else {
      out.push(`  ${C.accent}${C.bold}✻ ${title}${C.reset}`);
      out.push(tui.divider(w));
    }
    out.push("");

    items.forEach((label, i) => {
      if (i === selected) {
        out.push(`  ${C.accent}${C.bold}❯ ${label}${C.reset}`);
      } else {
        out.push(`    ${C.muted}${label}${C.reset}`);
      }
    });

    out.push("");
    out.push(`  ${C.muted}↑/↓ move  ·  enter select  ·  esc back${C.reset}`);
    tui.renderFrame(out.join("\n"));

    const key = await tui.readKey();
    if (key === "UP" || key === "k" || key === "K") {
      selected = (selected - 1 + items.length) % items.length;
    } else if (key === "DOWN" || key === "j" || key === "J") {
      selected = (selected + 1) % items.length;
    } else if (key === "ENTER") {
      tui.showCursor();
      return selected;
    } else if (key === "ESC" || key === "q" || key === "Q" || key === "CTRL_C" || key === "EOF") {
      tui.showCursor();
      return -1;
    }
  }
}

async function handleSwitchProfile(profile) {
  tui.resetScreen();
  const { warnings } = await tui.withSpinner(`Switching to ${profile.alias}...`, async () => {
    return core.applyProfile(profile);
  });

  let needPause = false;
  if (warnings.length > 0) {
    for (const w of warnings) {
      process.stdout.write(`  ${C.yellow}▲ ${w}${C.reset}\n`);
    }
    needPause = true;
  }

  // Check unpushed commits with wrong author / missing signature
  const unpushed = core.inspectUnpushedCommits(profile.userEmail);
  if (unpushed.count > 0) {
    process.stdout.write(
      `\n  ${C.yellow}▲ Found ${unpushed.count} unpushed commit(s) with different author or missing SSH signature.${C.reset}\n`
    );
    const fix = await tui.promptConfirm(
      `Update author to '${profile.userName} <${profile.userEmail}>' & re-sign?`,
      true
    );
    if (fix) {
      const res = await tui.withSpinner("Rewriting & signing unpushed commits...", async () =>
        core.rewriteUnpushedCommits(unpushed)
      );
      process.stdout.write(`  ${res.ok ? C.green + "✔" : C.red + "✕"} ${res.message}${C.reset}\n`);
      needPause = true;
    }
  }

  setToast(`✔ Switched to ${profile.alias} (${profile.userName} <${profile.userEmail}>)`, C.green);
  if (needPause) {
    await tui.waitAnyKey();
  }
  tui.resetScreen();
}

async function handleAddProfile() {
  tui.resetScreen();
  const w = tui.getTermWidth();
  const drawHeader = () => {
    tui.renderFrame(
      [
        "",
        `  ${C.accent}${C.bold}✻ Add Account${C.reset} ${C.muted}(Esc to cancel)${C.reset}`,
        tui.divider(w),
        "",
      ].join("\n")
    );
  };

  drawHeader();
  const existing = core.loadProfiles();

  let alias = "";
  while (true) {
    const val = await tui.promptText("Profile alias", { placeholder: "e.g. Work, Personal" });
    if (val === null) return;
    if (!val) {
      process.stdout.write(`  ${C.red}✕ Alias is required.${C.reset}\n`);
      continue;
    }
    if (!/^[a-zA-Z0-9]+$/.test(val)) {
      process.stdout.write(`  ${C.red}✕ Alias must be alphanumeric (no spaces/symbols).${C.reset}\n`);
      continue;
    }
    if (existing.some((p) => p.alias === val)) {
      process.stdout.write(`  ${C.red}✕ Profile '${val}' already exists.${C.reset}\n`);
      continue;
    }
    alias = val;
    break;
  }

  const userName = await tui.promptText("Git user.name", { placeholder: "e.g. John Doe" });
  if (!userName) return;

  const userEmail = await tui.promptText("Git user.email", { placeholder: "e.g. john@company.com" });
  if (!userEmail) return;

  const githubUsername = await tui.promptText("GitHub username", { placeholder: "optional, Enter to skip" });
  if (githubUsername === null) return;

  const pat = await tui.promptText("GitHub HTTPS PAT", { secret: true, placeholder: "optional, Enter to skip" });
  if (pat === null) return;

  process.stdout.write("\n");
  const keyRes = await tui.withSpinner("Generating 4096-bit SSH key...", async () =>
    core.generateSshKey(userEmail, alias)
  );
  if (!keyRes.ok) {
    process.stdout.write(`  ${C.red}✕ Failed to generate SSH key. Ensure OpenSSH is installed.${C.reset}\n`);
    await tui.waitAnyKey();
    return;
  }
  process.stdout.write(
    `  ${C.green}✔${C.reset} ${keyRes.existed ? "Using existing SSH key" : "SSH key generated"} ${C.muted}(${path.basename(keyRes.keyPath)})${C.reset}\n`
  );

  core.updateSshConfig(alias, keyRes.keyPath);
  process.stdout.write(`  ${C.green}✔${C.reset} SSH config updated ${C.muted}(Host: github.com-${alias})${C.reset}\n`);

  const pubKeyPath = `${keyRes.keyPath}.pub`;
  if (fs.existsSync(pubKeyPath)) {
    const pubContent = fs.readFileSync(pubKeyPath, "utf8");
    if (core.copyToClipboard(pubContent)) {
      process.stdout.write(`  ${C.green}✔${C.reset} Public key copied to clipboard!\n`);
    } else {
      process.stdout.write(`  ${C.yellow}▲${C.reset} Copy manually from: ${pubKeyPath}\n`);
    }
  }

  const pasteKey = core.IS_MAC ? "Cmd+V" : "Ctrl+V";
  process.stdout.write(
    [
      "",
      `  ${C.accent}${C.bold}Add key on GitHub:${C.reset}`,
      `    ${C.muted}1.${C.reset} Paste (${pasteKey}) as ${C.white}Authentication Key${C.reset} (for git push)`,
      `    ${C.muted}2.${C.reset} Add the same key again as ${C.white}Signing Key${C.reset} (for Verified badge)`,
      "",
    ].join("\n")
  );

  core.openTarget("https://github.com/settings/ssh/new");
  await tui.waitAnyKey("Press Enter after adding the key on GitHub...");
  process.stdout.write("\n");

  const sshTest = await tui.withSpinner(`Testing SSH connection to github.com-${alias}...`, () =>
    core.testGitHubSshAsync(alias)
  );
  if (sshTest.ok) {
    process.stdout.write(
      `  ${C.green}✔ SSH authenticated${sshTest.login ? ` as ${sshTest.login}` : ""}!${C.reset}\n`
    );
  } else {
    process.stdout.write(`  ${C.yellow}▲ SSH test did not authenticate yet (you can test again later).${C.reset}\n`);
  }

  const now = new Date();
  const pad2 = (n) => String(n).padStart(2, "0");
  const created = `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())} ${pad2(now.getHours())}:${pad2(now.getMinutes())}`;

  const newProfile = {
    alias,
    userName,
    userEmail,
    keyPath: keyRes.keyPath,
    githubUsername: githubUsername || "",
    created,
  };
  existing.push(newProfile);
  core.saveProfiles(existing);
  if (pat) {
    core.saveProfileToken(alias, pat);
  }

  // Auto-activate if first profile or unset
  const curr = core.getGitCurrent();
  if (curr.name === "Not Set" || existing.length === 1) {
    core.applyProfile(newProfile);
  }

  setToast(`✔ Added account '${alias}'`, C.green);
  tui.resetScreen();
}

async function handleRemoveProfile() {
  const profiles = core.loadProfiles();
  if (!profiles.length) {
    setToast("▲ No accounts to remove.", C.yellow);
    return;
  }

  const items = profiles.map((p) => `${tui.padRight(p.alias, 16)} ${C.muted}${p.userEmail}${C.reset}`);
  items.push("← Back");
  const idx = await selectFromList("Remove Account", items, "Select an account to remove");
  if (idx < 0 || idx >= profiles.length) return;

  const removed = profiles[idx];
  const prevActive = core.getActiveProfile(profiles);

  process.stdout.write("\n");
  const confirmed = await tui.promptConfirm(
    `Delete '${removed.alias}' (${removed.userEmail}) and its SSH keys?`,
    false
  );
  if (!confirmed) return;

  if (removed.keyPath) {
    try {
      if (fs.existsSync(removed.keyPath)) fs.unlinkSync(removed.keyPath);
      if (fs.existsSync(`${removed.keyPath}.pub`)) fs.unlinkSync(`${removed.keyPath}.pub`);
    } catch {}
  }

  core.removeFromSshConfig(removed.alias);
  core.deleteProfileToken(removed.alias);

  const remaining = profiles.filter((p) => p.alias !== removed.alias);
  core.saveProfiles(remaining);

  const curr = core.getGitCurrent();
  const wasActive =
    (prevActive && prevActive.alias === removed.alias) ||
    (!prevActive && (curr.name === removed.userName || curr.email === removed.userEmail));

  if (wasActive) {
    core.runGit(["config", "--global", "--unset", "user.name"]);
    core.runGit(["config", "--global", "--unset", "user.email"]);
    core.clearGlobalGitHubRouting();
    core.clearGitHubHttpsCredential();
  } else {
    const stillActive = core.getActiveProfile(remaining);
    if (stillActive) core.syncGlobalGitHubRouting(stillActive.alias, stillActive.keyPath);
  }

  const gSKey = core.runGit(["config", "--global", "user.signingkey"]).stdout;
  if (removed.keyPath && gSKey === `${removed.keyPath}.pub`) {
    core.runGit(["config", "--global", "--unset", "user.signingkey"]);
    core.runGit(["config", "--global", "--unset", "commit.gpgsign"]);
  }

  if (core.isInsideGitRepo()) {
    const loc = core.getGitLocal();
    if (loc.email === removed.userEmail) {
      core.runGit(["config", "--local", "--unset", "user.name"]);
      core.runGit(["config", "--local", "--unset", "user.email"]);
    }
    const lSKey = core.runGit(["config", "--local", "user.signingkey"]).stdout;
    if (removed.keyPath && lSKey === `${removed.keyPath}.pub`) {
      core.runGit(["config", "--local", "--unset", "user.signingkey"]);
      core.runGit(["config", "--local", "--unset", "commit.gpgsign"]);
    }
  }

  setToast(`✔ Removed account '${removed.alias}'`, C.green);
  tui.resetScreen();
}

async function handleTestConnection() {
  const profiles = core.loadProfiles();
  if (!profiles.length) {
    setToast("▲ No accounts to test.", C.yellow);
    return;
  }

  const items = profiles.map((p) => `${tui.padRight(p.alias, 16)} ${C.muted}${p.userEmail}${C.reset}`);
  items.push("← Back");
  const idx = await selectFromList("Test Connection", items, "Verify SSH key & HTTPS PAT authentication");
  if (idx < 0 || idx >= profiles.length) return;

  const sel = profiles[idx];
  const w = tui.getTermWidth();
  tui.renderFrame(
    ["", `  ${C.accent}${C.bold}✻ Test Connection — ${sel.alias}${C.reset}`, tui.divider(w), ""].join("\n")
  );

  if (sel.keyPath) {
    const sshRes = await tui.withSpinner(`Testing SSH (github.com-${sel.alias})...`, () =>
      core.testGitHubSshAsync(sel.alias)
    );
    if (sshRes.ok) {
      process.stdout.write(
        `  ${C.green}✔ SSH OK${C.reset} ${C.muted}— authenticated${sshRes.login ? ` as ${C.white}${sshRes.login}${C.reset}` : ""}${C.reset}\n`
      );
    } else {
      process.stdout.write(`  ${C.red}✕ SSH FAILED${C.reset}\n`);
      if (sshRes.output) process.stdout.write(`    ${C.muted}${sshRes.output}${C.reset}\n`);
    }
  } else {
    process.stdout.write(`  ${C.yellow}▲ No SSH key recorded for '${sel.alias}'.${C.reset}\n`);
  }

  if (core.profileHasToken(sel.alias)) {
    const patRes = await tui.withSpinner("Testing HTTPS PAT (api.github.com)...", () =>
      core.testGitHubPatAsync(sel.alias)
    );
    if (patRes.ok) {
      process.stdout.write(
        `  ${C.green}✔ HTTPS PAT OK${C.reset} ${C.muted}— authenticated as ${C.white}${patRes.login}${C.reset}\n`
      );
    } else {
      process.stdout.write(`  ${C.red}✕ HTTPS PAT FAILED${C.reset} ${C.muted}(${patRes.output})${C.reset}\n`);
    }
  }

  await tui.waitAnyKey();
  tui.resetScreen();
}

async function handleManageHttpsCredentials() {
  while (true) {
    const profiles = core.loadProfiles();
    if (!profiles.length) {
      setToast("▲ No accounts found.", C.yellow);
      return;
    }

    const items = profiles.map((p) => {
      const gh = p.githubUsername || "(unset)";
      const status = core.profileHasToken(p.alias) ? `${C.green}PAT set${C.reset}` : `${C.muted}no PAT${C.reset}`;
      return `${tui.padRight(p.alias, 15)} ${tui.padRight(C.muted + gh + C.reset, 20)} ${status}`;
    });
    items.push("Clear cached github.com HTTPS credential now");
    items.push("← Back");

    const idx = await selectFromList("HTTPS Credentials (PAT)", items);
    if (idx < 0 || idx === items.length - 1) return;

    if (idx === items.length - 2) {
      core.clearGitHubHttpsCredential();
      setToast("✔ Cleared cached github.com HTTPS credential.", C.green);
      continue;
    }

    const sel = profiles[idx];
    const subIdx = await selectFromList(`HTTPS PAT — ${sel.alias}`, [
      "Set / Update GitHub Username & PAT",
      "Remove saved PAT",
      "Test saved PAT",
      "← Back",
    ]);

    if (subIdx === 0) {
      process.stdout.write("\n");
      const newGh = await tui.promptText("GitHub username", { defaultValue: sel.githubUsername || sel.userName });
      if (newGh === null) continue;
      const newPat = await tui.promptText("GitHub PAT", { secret: true, placeholder: "Enter to keep existing" });
      if (newPat === null) continue;

      sel.githubUsername = newGh;
      core.saveProfiles(profiles);
      if (newPat) core.saveProfileToken(sel.alias, newPat);

      const active = core.getActiveProfile(profiles);
      if (active && active.alias === sel.alias) {
        core.syncHttpsCredentials(sel.alias, newGh, sel.userName);
      }
      if (active) core.syncGlobalGitHubRouting(active.alias, active.keyPath);
    } else if (subIdx === 1) {
      core.deleteProfileToken(sel.alias);
      const active = core.getActiveProfile(profiles);
      if (active && active.alias === sel.alias) core.clearGitHubHttpsCredential();
    } else if (subIdx === 2) {
      process.stdout.write("\n");
      const res = await tui.withSpinner("Testing HTTPS PAT...", () => core.testGitHubPatAsync(sel.alias));
      process.stdout.write(
        res.ok
          ? `  ${C.green}✔ Authenticated as ${res.login}${C.reset}\n`
          : `  ${C.red}✕ Failed (${res.output})${C.reset}\n`
      );
      await tui.waitAnyKey();
    }
  }
}

async function handleIdeGitAuthSync() {
  while (true) {
    const ides = core.detectIdeSettingsPaths();
    if (!ides.length) {
      const w = tui.getTermWidth();
      tui.renderFrame(
        [
          "",
          `  ${C.accent}${C.bold}✻ IDE Git Auth Sync${C.reset}`,
          tui.divider(w),
          "",
          `  ${C.yellow}▲ No supported IDE settings directory detected automatically.${C.reset}`,
          `  ${C.muted}Add this to your IDE settings.json manually:${C.reset}`,
          `    ${C.white}"github.gitAuthentication": false${C.reset}`,
        ].join("\n")
      );
      await tui.waitAnyKey();
      return;
    }

    const items = ides.map((ide) => {
      const st = core.getIdeGitAuthSetting(ide.path);
      const lbl =
        st === "false"
          ? `${C.green}OFF (synced with git-switch)${C.reset}`
          : st === "error"
          ? `${C.red}parse error${C.reset}`
          : `${C.yellow}ON  (uses IDE OAuth)${C.reset}`;
      return `${tui.padRight(ide.name, 18)} ${lbl}`;
    });
    items.push("Disable for ALL detected IDEs (Recommended)");
    items.push("← Back");

    const idx = await selectFromList(
      "IDE Git Auth Sync",
      items,
      'Set "github.gitAuthentication": false so IDE UI Push uses git-switch'
    );
    if (idx < 0 || idx === items.length - 1) return;

    if (idx === items.length - 2) {
      for (const ide of ides) {
        core.setIdeGitAuthSetting(ide.path, false);
      }
    } else {
      const ide = ides[idx];
      const cur = core.getIdeGitAuthSetting(ide.path);
      core.setIdeGitAuthSetting(ide.path, cur === "false");
    }
  }
}

async function handleSettings() {
  let selected = 0;
  const w = tui.getTermWidth();
  tui.hideCursor();

  while (true) {
    const routeOn = core.isSshRewriteEnabled();
    const signOn = core.isCommitSigningEnabled();
    const items = [
      `Auto-Route GitHub HTTPS → SSH    ${routeOn ? C.green + "ON" : C.muted + "OFF"}${C.reset}`,
      `SSH Commit Signing               ${signOn ? C.green + "ON" : C.muted + "OFF"}${C.reset}`,
      "Manage HTTPS Credentials (PAT)",
      "IDE Git Auth Sync (github.gitAuthentication)",
      "Backup Profiles",
      "Open profiles.json",
      "Open .ssh folder",
      "← Back",
    ];

    const out = ["", `  ${C.accent}${C.bold}✻ Settings${C.reset}`, tui.divider(w), ""];
    items.forEach((label, i) => {
      if (i === selected) {
        out.push(`  ${C.accent}${C.bold}❯ ${label}${C.reset}`);
      } else {
        out.push(`    ${C.muted}${label}${C.reset}`);
      }
    });
    out.push("");
    out.push(`  ${C.muted}↑/↓ move  ·  enter toggle/open  ·  esc back${C.reset}`);
    tui.renderFrame(out.join("\n"));

    const key = await tui.readKey();
    if (key === "UP" || key === "k" || key === "K") {
      selected = (selected - 1 + items.length) % items.length;
    } else if (key === "DOWN" || key === "j" || key === "J") {
      selected = (selected + 1) % items.length;
    } else if (key === "ESC" || key === "q" || key === "Q" || key === "CTRL_C" || key === "EOF") {
      tui.showCursor();
      return;
    } else if (key === "ENTER") {
      tui.showCursor();
      const paths = core.getPaths();
      if (selected === 0) {
        if (routeOn) {
          fs.writeFileSync(paths.noSshRewriteFlag, "", "utf8");
          core.clearGlobalGitHubRouting();
        } else {
          try {
            if (fs.existsSync(paths.noSshRewriteFlag)) fs.unlinkSync(paths.noSshRewriteFlag);
          } catch {}
          const active = core.getActiveProfile();
          if (active) core.syncGlobalGitHubRouting(active.alias, active.keyPath);
        }
      } else if (selected === 1) {
        if (signOn) {
          core.runGit(["config", "--global", "commit.gpgsign", "false"]);
          if (core.isInsideGitRepo()) core.runGit(["config", "--local", "--unset-all", "commit.gpgsign"]);
        } else {
          core.runGit(["config", "--global", "gpg.format", "ssh"]);
          core.runGit(["config", "--global", "commit.gpgsign", "true"]);
          if (core.isInsideGitRepo()) {
            core.runGit(["config", "--local", "--unset-all", "gpg.format"]);
            core.runGit(["config", "--local", "--unset-all", "user.signingkey"]);
            core.runGit(["config", "--local", "--unset-all", "commit.gpgsign"]);
          }
          const active = core.getActiveProfile();
          if (active && active.keyPath && fs.existsSync(`${active.keyPath}.pub`)) {
            core.runGit(["config", "--global", "user.signingkey", `${active.keyPath}.pub`]);
          }
        }
      } else if (selected === 2) {
        await handleManageHttpsCredentials();
      } else if (selected === 3) {
        await handleIdeGitAuthSync();
      } else if (selected === 4) {
        const now = new Date();
        const pad2 = (n) => String(n).padStart(2, "0");
        const stamp = `${now.getFullYear()}${pad2(now.getMonth() + 1)}${pad2(now.getDate())}_${pad2(now.getHours())}${pad2(now.getMinutes())}`;
        const bak = path.join(paths.baseDir, `backup_${stamp}.json`);
        fs.copyFileSync(paths.profilesFile, bak);
        setToast(`✔ Backup saved: ${bak}`, C.green);
        return;
      } else if (selected === 5) {
        core.openTarget(paths.profilesFile);
      } else if (selected === 6) {
        core.openTarget(paths.sshDir);
      } else if (selected === 7) {
        return;
      }
      tui.hideCursor();
    }
  }
}

async function runApp() {
  if (!core.hasCommand("git")) {
    console.error("Error: 'git' is not installed.");
    process.exit(1);
  }
  core.initializeSystem();

  const restore = () => {
    tui.showCursor();
    tui.leaveAltScreen();
  };
  process.on("exit", restore);
  process.on("SIGINT", () => {
    restore();
    process.exit(0);
  });

  tui.enterAltScreen();
  tui.beginRawMenu();
  let snap = getHomeSnapshot();
  let selected = 0;
  if (snap.activeAlias) {
    const activeIdx = snap.profiles.findIndex((p) => p.alias === snap.activeAlias);
    if (activeIdx >= 0) selected = activeIdx;
  }

  tui.hideCursor();
  while (true) {
    const total = snap.profiles.length + 5;
    if (selected >= total) selected = total - 1;

    renderHome(snap, selected);

    const key = await tui.readKey();
    toast = null;

    if (key === "UP" || key === "k" || key === "K") {
      selected = (selected - 1 + total) % total;
      continue;
    }
    if (key === "DOWN" || key === "j" || key === "J") {
      selected = (selected + 1) % total;
      continue;
    }
    if (key === "ESC" || key === "q" || key === "Q" || key === "0" || key === "CTRL_C" || key === "EOF") {
      break;
    }
    if (key === "ENTER") {
      tui.endRawMenu();
      tui.showCursor();
      if (selected < snap.profiles.length) {
        await handleSwitchProfile(snap.profiles[selected]);
      } else {
        const act = selected - snap.profiles.length;
        if (act === 0) await handleAddProfile();
        else if (act === 1) await handleRemoveProfile();
        else if (act === 2) await handleTestConnection();
        else if (act === 3) await handleSettings();
        else if (act === 4) break;
      }
      snap = getHomeSnapshot();
      tui.beginRawMenu();
      tui.hideCursor();
    }
  }
  restore();
}

module.exports = { runApp };
