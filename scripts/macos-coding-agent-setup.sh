#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: bash scripts/macos-coding-agent-setup.sh [--preflight]"
}

case "${1:-}" in
  "") mode=install ;;
  --preflight) mode=preflight ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi

node_usable() {
  command -v node >/dev/null 2>&1 &&
    node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit(major > 22 || (major === 22 && minor >= 19) ? 0 : 1)'
}

python_runner() {
  local runner
  for runner in uvx uv pipx pip-run; do
    if command -v "$runner" >/dev/null 2>&1; then
      echo "$runner"
      return 0
    fi
  done
  return 1
}

gui_installed() {
  [[ -d /Applications/pi-gui.app || -d "$HOME/Applications/pi-gui.app" ]]
}

preflight() {
  local blocked=0
  local runner
  if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
    echo "Blocked: pi-gui for macOS requires an Apple Silicon Mac." >&2
    blocked=1
  else
    echo "macOS / Apple Silicon: ready"
  fi
  if ! command -v brew >/dev/null 2>&1; then
    echo "Blocked: install Homebrew first: https://brew.sh/" >&2
    blocked=1
  elif ! gui_installed && ! brew help trust >/dev/null 2>&1; then
    echo "Blocked: this Homebrew version lacks 'brew trust', needed for the pi-gui tap." >&2
    blocked=1
  else
    echo "Homebrew: ready"
  fi
  if [[ -L "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/settings.json" ]]; then
    echo "Blocked: Pi settings.json is a symlink; update its managed source instead." >&2
    blocked=1
  fi
  if node_usable; then
    echo "Node: $(node --version) (ready)"
  else
    echo "Node >=22.19: will install with Homebrew"
  fi
  if runner=$(python_runner); then
    echo "Python page-extraction runner: $runner (ready)"
  else
    echo "Python page-extraction runner: will install uv with Homebrew"
  fi
  if command -v pi >/dev/null 2>&1; then
    echo "Pi: $(pi --version) (ready)"
  else
    echo "Pi: will install via npm"
  fi
  if gui_installed; then
    echo "pi-gui: installed"
  else
    echo "pi-gui: will install with Homebrew"
  fi
  echo "Copilot account sign-in: interactive after installation"
  return "$blocked"
}

preflight
if [[ "$mode" == preflight ]]; then
  exit 0
fi

if ! node_usable; then
  brew install node
  hash -r
  if ! node_usable; then
    echo "Node >=22.19 is still not first on PATH after installation." >&2
    exit 1
  fi
fi
if ! python_runner >/dev/null; then
  brew install uv
  hash -r
fi
python_runner >/dev/null || { echo "No Python page-extraction runner is on PATH." >&2; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "npm is missing from PATH." >&2; exit 1; }
if ! command -v pi >/dev/null 2>&1; then
  npm install -g --ignore-scripts @earendil-works/pi-coding-agent@1.4.0
  hash -r
fi
command -v pi >/dev/null 2>&1 || { echo "Pi is still missing from PATH." >&2; exit 1; }

# Pi reconciles all configured packages on each install, so skip Puppeteer's
# automatic browser downloads for both commands.
export PUPPETEER_SKIP_DOWNLOAD=1
pi install npm:pi-web-search@1.7.0
pi install npm:pi-web-fetch@1.1.0

# web_fetch uses Chrome; install that browser without Puppeteer's unused headless shell.
agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
"$agent_dir/npm/node_modules/.bin/puppeteer" browsers install chrome
node -e '
  const puppeteer = require(process.argv[1]);
  (async () => {
    const browser = await puppeteer.launch({ headless: true });
    await browser.close();
    console.log("Chrome launch check: ready");
  })().catch(error => {
    console.error(`Chrome launch check failed at ${puppeteer.executablePath()}: ${error.message}`);
    process.exit(1);
  });
' "$agent_dir/npm/node_modules/puppeteer"

if ! gui_installed; then
  brew tap minghinmatthewlam/tap
  brew trust minghinmatthewlam/tap
  brew install --cask pi-gui
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
node "$script_dir/set_pi_luna_defaults.mjs"

echo
echo "Installed Pi $(pi --version) and extensions:"
pi list
echo
echo "Next: open Pi or pi-gui and sign in to GitHub Copilot with your organization account."
echo "Then create a new thread and verify github-copilot/gpt-6-luna at high."
