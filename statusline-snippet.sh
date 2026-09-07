# This block is what install.sh appends to the end of ~/.claude/statusline.sh
# (or adds yourself, if you'd rather not run install.sh). It assumes the script
# has already captured the statusLine hook's stdin JSON into $input, e.g. via
# `input=$(cat)` near the top -- the idiom used by every example statusline
# script in Claude Code's own docs.
#
# rate_limits.* only appears in the hook JSON for Pro/Max accounts, and only
# after the first API response in a session -- until then jq's `//` fallback
# leaves the fields absent from the JSON, and the menu bar app shows "no data".
#
# Written via temp-file-then-mv so the app never reads a half-written file.
# >>> clife: write rate-limit usage snapshot >>>
echo "$input" | jq -c '{five_hour: .rate_limits.five_hour.used_percentage, seven_day: .rate_limits.seven_day.used_percentage, five_hour_resets_at: .rate_limits.five_hour.resets_at, seven_day_resets_at: .rate_limits.seven_day.resets_at, updated_at: now}' > ~/.claude/usage-status.json.tmp 2>/dev/null && mv ~/.claude/usage-status.json.tmp ~/.claude/usage-status.json
# <<< clife <<<
