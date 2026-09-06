#!/bin/bash
# One-shot install: wires up statusline.sh/settings.json, builds the app, and
# installs it into /Applications. Runs install.sh + build.sh as separate steps
# (still usable on their own) rather than duplicating their logic.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

./install.sh
./build.sh

pkill -f "ClaudeUsage.app/Contents/MacOS/ClaudeUsage" 2>/dev/null || true
sleep 1
rm -r -f /Applications/ClaudeUsage.app
ditto ClaudeUsage.app /Applications/ClaudeUsage.app
open /Applications/ClaudeUsage.app

cat <<'EOF'

Installed to /Applications/ClaudeUsage.app and launched.

If macOS blocked the launch with an "unidentified developer" warning:
Right-click ClaudeUsage.app in /Applications > Open > Open, once.

Usage numbers only appear for Pro/Max accounts, and only after Claude Code's
first response in a session writes rate_limits into the hook JSON.
EOF
