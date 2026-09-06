#!/bin/bash
# Wires up ~/.claude/statusline.sh + ~/.claude/settings.json so Claude Code
# writes a usage snapshot the menu bar app can read. Safe to re-run: every step
# checks what's already there before touching it.
set -e

command -v jq >/dev/null 2>&1 || { echo "jq is required (brew install jq)"; exit 1; }

DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
STATUSLINE="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
SNIPPET_FILE="$DIR/statusline-snippet.sh"
MARKER="# >>> claude-usage-bar: write rate-limit usage snapshot >>>"

mkdir -p "$CLAUDE_DIR"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# 1. Check settings.json first: if statusLine is already configured to run some
#    other script, don't create/touch statusline.sh at all -- it would just be
#    an unused file, since that other script is what Claude Code actually runs.
CURRENT_CMD=$(jq -r '.statusLine.command // empty' "$SETTINGS")
if [ -n "$CURRENT_CMD" ] && ! echo "$CURRENT_CMD" | grep -qF ".claude/statusline.sh"; then
  echo "WARNING: $SETTINGS already has a different statusLine command ($CURRENT_CMD)."
  echo "Add this block to whatever script it runs, reusing the variable it reads the hook JSON into:"
  echo
  cat "$SNIPPET_FILE"
  exit 0
fi

# 2. statusline.sh: create a minimal one if the user has none yet.
if [ ! -f "$STATUSLINE" ]; then
  cat > "$STATUSLINE" <<'EOF'
#!/bin/bash
input=$(cat)
echo "$(echo "$input" | jq -r '.model.display_name // "Claude"')"
EOF
  chmod +x "$STATUSLINE"
  echo "Created $STATUSLINE"
fi

# 3. Append the usage-snapshot snippet, once, only if the script looks like it
#    captures stdin the way the snippet expects ($input via `input=$(cat)`).
if grep -qF "$MARKER" "$STATUSLINE"; then
  echo "Usage snapshot snippet already present in $STATUSLINE -- skipping"
elif grep -qE '^\s*input=\$\(cat\)' "$STATUSLINE"; then
  printf '\n' >> "$STATUSLINE"
  cat "$SNIPPET_FILE" >> "$STATUSLINE"
  echo "Added usage snapshot snippet to $STATUSLINE"
else
  cat <<EOF
WARNING: $STATUSLINE doesn't appear to capture stdin as \$input (no "input=\$(cat)" line found).
Not modifying it automatically, to avoid breaking your existing script.
Add this block yourself, reusing whatever variable your script reads the hook JSON into:

$(cat "$SNIPPET_FILE")
EOF
fi

# 4. settings.json: point statusLine at our script, if nothing was configured
#    (step 1 already handled/exited the "something else is configured" case).
if [ -z "$CURRENT_CMD" ]; then
  TMP="$SETTINGS.tmp.$$"
  jq '.statusLine = {type: "command", command: "~/.claude/statusline.sh", padding: 0}' "$SETTINGS" > "$TMP"
  mv "$TMP" "$SETTINGS"
  echo "Set statusLine in $SETTINGS"
else
  echo "statusLine already points at statusline.sh -- skipping $SETTINGS"
fi

cat <<'EOF'

Done. Next:
  1. ./build.sh              # builds ClaudeUsage.app
  2. ./install.sh doesn't install the app itself -- copy/ditto ClaudeUsage.app
     to /Applications and open it, or just `open ClaudeUsage.app` in place.
  3. Usage numbers only appear for Pro/Max accounts, and only after Claude
     Code's first response in a session writes rate_limits into the hook JSON.
EOF
