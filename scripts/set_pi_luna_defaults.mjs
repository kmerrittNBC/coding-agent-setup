#!/usr/bin/env node
// Set the shared Pi CLI/pi-gui defaults without replacing other Pi settings.
import { existsSync, lstatSync, mkdirSync, readFileSync, renameSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

const agentDir = process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent");
const settingsPath = join(agentDir, "settings.json");
const exists = existsSync(settingsPath);
if (exists && lstatSync(settingsPath).isSymbolicLink()) {
  throw new Error(`${settingsPath} is a symlink; update its managed source instead`);
}
let settings = {};

if (exists) {
  settings = JSON.parse(readFileSync(settingsPath, "utf8"));
  if (settings === null || Array.isArray(settings) || typeof settings !== "object") {
    throw new Error(`${settingsPath} must contain a JSON object`);
  }
}
if (settings.modelThinkingLevels !== undefined &&
    (settings.modelThinkingLevels === null || Array.isArray(settings.modelThinkingLevels) ||
     typeof settings.modelThinkingLevels !== "object")) {
  throw new Error("modelThinkingLevels must be a JSON object");
}

const before = JSON.stringify(settings);
settings.defaultProvider = "github-copilot";
settings.defaultModel = "gpt-6-luna";
settings.defaultThinkingLevel = "high";
settings.modelThinkingLevels = {
  ...settings.modelThinkingLevels,
  "github-copilot/gpt-6-luna": "high",
};

if (JSON.stringify(settings) !== before || !exists) {
  mkdirSync(dirname(settingsPath), { recursive: true });
  const mode = exists ? statSync(settingsPath).mode & 0o777 : 0o600;
  const temporaryPath = `${settingsPath}.tmp-${process.pid}`;
  writeFileSync(temporaryPath, `${JSON.stringify(settings, null, 2)}\n`, { mode });
  renameSync(temporaryPath, settingsPath);
}
console.log(`Pi defaults: github-copilot/gpt-6-luna, high (${settingsPath})`);
