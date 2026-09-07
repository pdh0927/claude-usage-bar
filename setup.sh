#!/bin/bash
# One-shot install: wires up statusline.sh/settings.json, builds the app, and
# installs it into /Applications. Runs install.sh + build.sh as separate steps
# (still usable on their own) rather than duplicating their logic.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

./install.sh
./build.sh

pkill -f "Clife.app/Contents/MacOS/Clife" 2>/dev/null || true
sleep 1
rm -r -f /Applications/Clife.app
ditto Clife.app /Applications/Clife.app
open /Applications/Clife.app

cat <<'EOF'

Installed to /Applications/Clife.app and launched.

If macOS blocked the launch with an "unidentified developer" warning:
Right-click Clife.app in /Applications > Open > Open, once.

Usage numbers only appear for Pro/Max accounts, and only after Claude Code's
first response in a session writes rate_limits into the hook JSON.
EOF
