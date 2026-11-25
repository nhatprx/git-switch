#!/usr/bin/env node
"use strict";

const pkg = require("../package.json");
const { runApp } = require("../src/app");

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

runApp().catch((err) => {
  process.stdout.write("\x1b[?25h");
  console.error(err && err.message ? err.message : err);
  process.exit(1);
});
