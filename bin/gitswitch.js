#!/usr/bin/env node
"use strict";

const { spawnSync } = require("child_process");
const path = require("path");
const pkg = require("../package.json");

const args = process.argv.slice(2);

if (args.includes("-v") || args.includes("--version")) {
  console.log(`${pkg.name} v${pkg.version}`);
  process.exit(0);
}

if (args.includes("-h") || args.includes("--help")) {
  console.log(
    [
      `${pkg.name} v${pkg.version}`,
      pkg.description,
      "",
      "Usage:",
      "  gitswitch          Launch interactive Git Profile Manager",
      "  git-switch         Alias for gitswitch",
      "  gitswitch -v       Show version",
      "  gitswitch -h       Show help",
    ].join("\n")
  );
  process.exit(0);
}

const rootDir = path.resolve(__dirname, "..");
const isWindows = process.platform === "win32";

let command;
let commandArgs;

if (isWindows) {
  const psScript = path.join(rootDir, "git.ps1");
  // Prefer pwsh if available, otherwise fall back to Windows PowerShell
  const hasPwsh =
    spawnSync("pwsh", ["-NoProfile", "-Command", "$PSVersionTable.PSVersion"], {
      stdio: "ignore",
    }).status === 0;
  command = hasPwsh ? "pwsh" : "powershell.exe";
  commandArgs = [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-Command",
    `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8; & '${psScript.replace(/'/g, "''")}'`,
  ];
} else {
  const shScript = path.join(rootDir, "git.sh");
  command = "bash";
  commandArgs = [shScript, ...args];
}

const result = spawnSync(command, commandArgs, {
  stdio: "inherit",
});

if (result.error) {
  console.error(`Failed to launch ${command}: ${result.error.message}`);
  process.exit(1);
}

process.exit(typeof result.status === "number" ? result.status : 0);
