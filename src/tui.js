"use strict";

// Claude-Code-inspired 256-color palette (warm coral/terracotta accent + crisp neutrals)
const RESET = "\x1b[0m";
const BOLD = "\x1b[1m";
const DIM = "\x1b[2m";

const C = {
  reset: RESET,
  bold: BOLD,
  dim: DIM,
  accent: "\x1b[38;5;209m",      // Warm Claude terracotta/coral
  accentSoft: "\x1b[38;5;216m",  // Soft peach
  border: "\x1b[38;5;240m",      // Subtle muted border
  muted: "\x1b[38;5;244m",       // Secondary text
  subtle: "\x1b[38;5;238m",      // Hairline divider
  white: "\x1b[38;5;255m",       // Primary text
  green: "\x1b[38;5;114m",       // Emerald green
  yellow: "\x1b[38;5;221m",      // Warm amber
  red: "\x1b[38;5;203m",         // Soft coral red
  cyan: "\x1b[38;5;117m",        // Soft sky blue
  bgFocus: "\x1b[48;5;236m",     // Subtle row highlight
};

const SYNC_START = "\x1b[?2026h";
const SYNC_END = "\x1b[?2026l";
const HIDE_CURSOR = "\x1b[?25l";
const SHOW_CURSOR = "\x1b[?25h";
const ALT_SCREEN_ON = "\x1b[?1049h";
const ALT_SCREEN_OFF = "\x1b[?1049l";

let prevLines = [];
let inAltScreen = false;
let rawMenuMode = false;

const pendingKeys = [];
let keyWaiter = null;
let rawAcc = "";
let rawEscTimer = null;

function parseKeyBuffer(str) {
  const keys = [];
  let i = 0;
  let remainder = "";
  while (i < str.length) {
    const ch = str[i];
    if (ch === "\x03") {
      keys.push("CTRL_C");
      i++;
    } else if (ch === "\r" || ch === "\n") {
      keys.push("ENTER");
      i++;
    } else if (ch === "\x7f" || ch === "\b") {
      keys.push("BACKSPACE");
      i++;
    } else if (ch === "\x1b") {
      if (i + 1 >= str.length) {
        remainder = "\x1b";
        break;
      }
      const next = str[i + 1];
      if (next === "[" || next === "O") {
        if (i + 2 >= str.length) {
          remainder = str.slice(i);
          break;
        }
        const code = str[i + 2];
        if (code === "A") keys.push("UP");
        else if (code === "B") keys.push("DOWN");
        else if (code === "C") keys.push("RIGHT");
        else if (code === "D") keys.push("LEFT");
        else keys.push("ESC");
        i += 3;
      } else {
        keys.push("ESC");
        i++;
      }
    } else {
      keys.push(ch);
      i++;
    }
  }
  return { keys, remainder };
}

function enqueueKey(k) {
  if (keyWaiter) {
    const resolve = keyWaiter;
    keyWaiter = null;
    resolve(k);
  } else {
    pendingKeys.push(k);
  }
}

function onRawMenuData(chunk) {
  rawAcc += chunk.toString("utf8");
  const { keys, remainder } = parseKeyBuffer(rawAcc);
  rawAcc = remainder;

  if (keys.length > 0) {
    if (rawEscTimer) {
      clearTimeout(rawEscTimer);
      rawEscTimer = null;
    }
    for (const k of keys) enqueueKey(k);
  }

  if (rawAcc) {
    if (rawEscTimer) clearTimeout(rawEscTimer);
    rawEscTimer = setTimeout(() => {
      rawAcc = "";
      rawEscTimer = null;
      enqueueKey("ESC");
    }, 45);
  }
}

function beginRawMenu() {
  if (process.stdin.isTTY && !rawMenuMode) {
    rawMenuMode = true;
    rawAcc = "";
    pendingKeys.length = 0;
    try {
      process.stdin.setRawMode(true);
    } catch {}
    process.stdin.on("data", onRawMenuData);
    process.stdin.resume();
  }
}

function endRawMenu() {
  if (process.stdin.isTTY && rawMenuMode) {
    rawMenuMode = false;
    if (rawEscTimer) {
      clearTimeout(rawEscTimer);
      rawEscTimer = null;
    }
    rawAcc = "";
    process.stdin.removeListener("data", onRawMenuData);
    try {
      process.stdin.setRawMode(false);
    } catch {}
    process.stdin.pause();
  }
}

function enterAltScreen() {
  if (process.stdout.isTTY && !inAltScreen) {
    inAltScreen = true;
    prevLines = [];
    process.stdout.write(`${ALT_SCREEN_ON}\x1b[2J\x1b[H`);
  }
}

function leaveAltScreen() {
  endRawMenu();
  if (process.stdout.isTTY && inAltScreen) {
    inAltScreen = false;
    prevLines = [];
    process.stdout.write(`${SHOW_CURSOR}${ALT_SCREEN_OFF}`);
  }
}

function resetScreen() {
  prevLines = [];
  if (process.stdout.isTTY) {
    process.stdout.write("\x1b[2J\x1b[H");
  }
}

// Reset diff cache on terminal resize so next render repaints cleanly
if (process.stdout.isTTY) {
  process.stdout.on("resize", () => {
    prevLines = [];
  });
}

function stripAnsi(str) {
  return String(str).replace(/\x1b\[[0-9;?]*[a-zA-Z]/g, "");
}

function visibleLength(str) {
  // Strip ANSI; handle common wide/emoji chars gracefully
  return Array.from(stripAnsi(str)).length;
}

function padRight(str, width) {
  const len = visibleLength(str);
  return len >= width ? str : str + " ".repeat(width - len);
}

function truncate(str, maxLen) {
  const chars = Array.from(str);
  if (chars.length <= maxLen) return str;
  return chars.slice(0, Math.max(0, maxLen - 1)).join("") + "…";
}

function getTermWidth() {
  const cols = process.stdout.columns || 80;
  return Math.max(54, Math.min(76, cols - 4));
}

// Render a rounded box (Claude Code style)
function roundedBox(lines, width = null, borderColor = C.border, title = "") {
  const w = width || getTermWidth();
  const inner = w - 2;
  let top;
  if (title) {
    const tVis = visibleLength(title);
    const rightDashes = Math.max(1, inner - tVis - 3);
    top = `${borderColor}╭─ ${RESET}${title}${borderColor} ${"─".repeat(rightDashes)}╮${RESET}`;
  } else {
    top = `${borderColor}╭${"─".repeat(inner)}╮${RESET}`;
  }
  const body = lines.map((line) => {
    const content = ` ${line} `;
    const pad = Math.max(0, inner - visibleLength(content));
    return `${borderColor}│${RESET}${content}${" ".repeat(pad)}${borderColor}│${RESET}`;
  });
  const bottom = `${borderColor}╰${"─".repeat(inner)}╯${RESET}`;
  return [top, ...body, bottom].join("\n");
}

function divider(width = null) {
  const w = width || getTermWidth();
  return `  ${C.subtle}${"─".repeat(w - 2)}${RESET}`;
}

function badge(text, color = C.green) {
  return `${color}${text}${RESET}`;
}

// True zero-flicker differential line renderer:
// Never wipes the screen (\x1b[2J) between frames — only updates lines that changed!
function renderFrame(content) {
  if (!process.stdout.isTTY) {
    process.stdout.write(`${content}\n`);
    return;
  }

  const nextLines = content.split("\n");
  let out = SYNC_START;

  if (prevLines.length === 0) {
    // First frame after screen reset: move home, write each line + clear-to-EOL, then clear below
    out += "\x1b[H";
    for (let i = 0; i < nextLines.length; i++) {
      out += `${nextLines[i]}\x1b[K\n`;
    }
    out += "\x1b[J";
  } else {
    // Diff frame: only repaint rows that actually changed (e.g. 2 rows on arrow up/down!)
    const maxLen = Math.max(prevLines.length, nextLines.length);
    for (let i = 0; i < maxLen; i++) {
      const prev = prevLines[i];
      const next = nextLines[i];
      if (prev !== next) {
        if (next === undefined) {
          out += `\x1b[${i + 1};1H\x1b[2K`;
        } else {
          out += `\x1b[${i + 1};1H${next}\x1b[K`;
        }
      }
    }
    // Park cursor cleanly below last line
    out += `\x1b[${nextLines.length + 1};1H`;
  }

  out += SYNC_END;
  prevLines = nextLines;
  process.stdout.write(out);
}

function hideCursor() {
  if (process.stdout.isTTY) process.stdout.write(HIDE_CURSOR);
}

function showCursor() {
  if (process.stdout.isTTY) process.stdout.write(SHOW_CURSOR);
}

// Instant 0ms single-key reader with persistent raw-mode buffering (handles rapid key repeat!)
function readKey() {
  if (pendingKeys.length > 0) {
    return Promise.resolve(pendingKeys.shift());
  }

  const stdin = process.stdin;
  if (!stdin.isTTY) {
    return new Promise((resolve) => {
      stdin.resume();
      stdin.setEncoding("utf8");
      const onData = (chunk) => {
        stdin.removeListener("data", onData);
        stdin.pause();
        const line = chunk.split(/\r?\n/)[0].trim();
        if (!line) return resolve("ENTER");
        if (["UP", "DOWN", "ENTER", "ESC", "q", "Q", "0"].includes(line)) return resolve(line);
        resolve(line);
      };
      stdin.once("end", () => resolve("EOF"));
      stdin.on("data", onData);
    });
  }

  if (rawMenuMode) {
    return new Promise((resolve) => {
      keyWaiter = resolve;
    });
  }

  return new Promise((resolve) => {
    stdin.setRawMode(true);
    stdin.resume();
    let escTimer = null;
    let acc = "";

    const finish = (key) => {
      if (escTimer) clearTimeout(escTimer);
      stdin.removeListener("data", onData);
      try {
        stdin.setRawMode(false);
      } catch {}
      stdin.pause();
      resolve(key);
    };

    const onData = (chunk) => {
      acc += chunk.toString("utf8");
      const { keys, remainder } = parseKeyBuffer(acc);
      acc = remainder;
      if (keys.length > 0) {
        for (let k = 1; k < keys.length; k++) pendingKeys.push(keys[k]);
        return finish(keys[0]);
      }
      if (acc) {
        if (escTimer) clearTimeout(escTimer);
        escTimer = setTimeout(() => {
          acc = "";
          finish("ESC");
        }, 45);
      }
    };

    stdin.on("data", onData);
  });
}

// Styled text input prompt (supports masked password input & Esc to cancel)
function promptText(label, { defaultValue = "", secret = false, placeholder = "" } = {}) {
  return new Promise((resolve) => {
    const stdin = process.stdin;
    showCursor();
    const hint = defaultValue ? ` ${C.muted}[${defaultValue}]${RESET}` : placeholder ? ` ${C.muted}(${placeholder})${RESET}` : "";
    const prefix = `  ${C.accent}❯${RESET} ${C.white}${label}${RESET}${hint}: `;
    process.stdout.write(prefix);

    if (!stdin.isTTY) {
      stdin.resume();
      stdin.setEncoding("utf8");
      stdin.once("data", (chunk) => {
        stdin.pause();
        const val = chunk.split(/\r?\n/)[0].trim();
        resolve(val || defaultValue);
      });
      stdin.once("end", () => resolve(null));
      return;
    }

    const wasRaw = stdin.isRaw;
    stdin.setRawMode(true);
    stdin.resume();

    let value = "";
    const cleanup = () => {
      stdin.removeListener("data", onData);
      try {
        stdin.setRawMode(Boolean(wasRaw));
      } catch {}
      stdin.pause();
    };

    const onData = (chunk) => {
      const str = chunk.toString("utf8");
      for (const ch of str) {
        if (ch === "\x03") {
          cleanup();
          process.stdout.write("\n");
          return resolve(null);
        }
        if (ch === "\x1b") {
          cleanup();
          process.stdout.write("\n");
          return resolve(null);
        }
        if (ch === "\r" || ch === "\n") {
          cleanup();
          process.stdout.write("\n");
          return resolve(value.trim() || defaultValue);
        }
        if (ch === "\x7f" || ch === "\b") {
          if (value.length > 0) {
            value = value.slice(0, -1);
            process.stdout.write("\b \b");
          }
          continue;
        }
        if (ch >= " ") {
          value += ch;
          process.stdout.write(secret ? `${C.muted}•${RESET}` : ch);
        }
      }
    };

    stdin.on("data", onData);
  });
}

// Inline Yes/No arrow/key prompt
async function promptConfirm(question, defaultYes = true) {
  let choice = defaultYes;
  hideCursor();
  const renderLine = () => {
    const yesStyled = choice
      ? `${C.accent}${BOLD}❯ Yes${RESET}`
      : `${C.muted}  Yes${RESET}`;
    const noStyled = !choice
      ? `${C.accent}${BOLD}❯ No${RESET}`
      : `${C.muted}  No${RESET}`;
    process.stdout.write(`\r\x1b[2K  ${C.white}${question}${RESET}   ${yesStyled}   ${noStyled}`);
  };
  renderLine();
  while (true) {
    const key = await readKey();
    if (key === "LEFT" || key === "RIGHT" || key === "UP" || key === "DOWN" || key === "\t") {
      choice = !choice;
      renderLine();
    } else if (key === "y" || key === "Y") {
      choice = true;
      renderLine();
      process.stdout.write("\n");
      showCursor();
      return true;
    } else if (key === "n" || key === "N" || key === "ESC" || key === "CTRL_C") {
      choice = false;
      renderLine();
      process.stdout.write("\n");
      showCursor();
      return false;
    } else if (key === "ENTER") {
      process.stdout.write("\n");
      showCursor();
      return choice;
    }
  }
}

// Animated braille spinner (Claude Code style)
async function withSpinner(label, asyncFn) {
  const frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
  let idx = 0;
  let timer = null;
  if (process.stdout.isTTY) {
    hideCursor();
    process.stdout.write(`  ${C.accent}${frames[0]}${RESET} ${C.muted}${label}${RESET}`);
    timer = setInterval(() => {
      idx = (idx + 1) % frames.length;
      process.stdout.write(`\r\x1b[2K  ${C.accent}${frames[idx]}${RESET} ${C.muted}${label}${RESET}`);
    }, 80);
  }
  try {
    const result = await asyncFn();
    if (timer) {
      clearInterval(timer);
      process.stdout.write("\r\x1b[2K");
    }
    return result;
  } catch (err) {
    if (timer) {
      clearInterval(timer);
      process.stdout.write("\r\x1b[2K");
    }
    throw err;
  }
}

async function waitAnyKey(message = "Press Enter or Esc to return...") {
  process.stdout.write(`\n  ${C.muted}${message}${RESET}`);
  await readKey();
}

module.exports = {
  C,
  stripAnsi,
  visibleLength,
  padRight,
  truncate,
  getTermWidth,
  roundedBox,
  divider,
  badge,
  beginRawMenu,
  endRawMenu,
  enterAltScreen,
  leaveAltScreen,
  resetScreen,
  renderFrame,
  hideCursor,
  showCursor,
  readKey,
  promptText,
  promptConfirm,
  withSpinner,
  waitAnyKey,
};
