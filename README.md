# claude-usage-bar

A macOS menu bar app that shows your Claude Code rate-limit usage (session and
weekly) as a small dual-ring gauge, read from a JSON snapshot that a one-line
addition to your `statusline.sh` writes out.

**Not an official Anthropic product.** This is an independent, unofficial
tool with no affiliation to or endorsement by Anthropic. "Claude" and
"Claude Code" are Anthropic's names for their own products, referenced here
only to describe what this tool reads data from.

**Requires a Claude Code Pro or Max subscription.** The rate-limit fields this
app reads (`rate_limits.five_hour.used_percentage` and
`rate_limits.seven_day.used_percentage`) are only included in the statusLine
hook JSON for Pro/Max accounts, and only after Claude Code's first response in
a session. On other plans, or before that first response, the app shows a
"no data" icon -- there's nothing wrong, the data just isn't available yet.
See Anthropic's [statusline docs](https://code.claude.com/docs/en/statusline.md)
("Rate limit usage" section).

## How it works

1. Claude Code calls your `~/.claude/statusline.sh` on every prompt render,
   piping it a JSON blob that (for Pro/Max accounts) includes current
   rate-limit usage.
2. A one-line addition to that script extracts the two percentages and writes
   them to `~/.claude/usage-status.json`, atomically (write to a temp file,
   then `mv`), so the file is never read half-written.
3. This app watches that file and redraws its menu bar icon whenever it
   changes -- no polling.

## Install

```sh
git clone <this-repo> claude-usage-bar
cd claude-usage-bar
./install.sh   # wires up ~/.claude/statusline.sh and ~/.claude/settings.json
./build.sh     # builds ClaudeUsage.app
open ClaudeUsage.app
```

`install.sh` is idempotent and safe to re-run:
- If you have no `~/.claude/statusline.sh` yet, it creates a minimal one.
- If you already have a custom one, it appends the one-line snippet (see
  `statusline-snippet.sh`) instead of overwriting your script -- and only if
  your script captures the hook JSON the standard way (`input=$(cat)`); if it
  doesn't recognize your script's shape, it prints the snippet for you to add
  by hand rather than guessing and risking breaking it.
- If `~/.claude/settings.json` has no `statusLine` configured, it adds one
  pointing at `~/.claude/statusline.sh`. If you already have a different
  `statusLine` configured, it leaves your settings alone and tells you what to
  do instead.

To install into `/Applications` and keep it updated:

```sh
pkill -f ClaudeUsage.app/Contents/MacOS/ClaudeUsage 2>/dev/null
rm -r -f /Applications/ClaudeUsage.app
ditto ClaudeUsage.app /Applications/ClaudeUsage.app   # not cp -R: see note below
open /Applications/ClaudeUsage.app
```

(`cp -R` nests the copy inside an existing destination directory instead of
replacing it; `ditto` does the right thing either way.)

### Gatekeeper warning on first launch

This app is signed locally (ad-hoc, or with a free Apple Development
certificate if you have one in Xcode) but is not notarized by Apple, so
macOS will refuse to open it with a plain double-click the first time.
**Right-click (or Control-click) the app > Open > Open**, once. After that,
macOS remembers your choice and launches it normally, including on login.

## Uninstall

```sh
pkill -f ClaudeUsage.app/Contents/MacOS/ClaudeUsage
rm -r -f /Applications/ClaudeUsage.app
```

Then remove the snippet block (between the `# >>> claude-usage-bar` /
`# <<< claude-usage-bar` markers) from `~/.claude/statusline.sh`, and delete
`~/.claude/usage-status.json` if you want.

## Design notes

**Icon: dual concentric ring, in color.** The outer ring is 7-day usage, the
inner ring is the current 5-hour session, each colored green/yellow/red at the
same 70%/90% thresholds `statusline.sh` already uses for its context bar. A
rendered contact sheet at real menu-bar size (20pt, 1x/2x, light/dark)
confirmed the two rings stay visually distinct at that size. Color was chosen
over a monochrome template icon because two independently-thresholded values
need a stronger cue than grayscale tinting can give at 18-20pt; the tradeoff
is that a colored icon doesn't get the automatic light/dark tint and
selection-invert that template images get for free. Exact numbers are never
just implied by the rings -- they're always in the tooltip and the dropdown
menu. A missing/unreadable/stale status file shows a `questionmark.circle`
icon instead of an empty ring, so "no data" is never mistaken for "0% used".

**File watching, not polling.** The app watches `~/.claude` (the status
file's parent directory, via `DispatchSource.makeFileSystemObjectSource`) for
child changes, debounced 150ms, instead of polling on a timer. `mv`-based
atomic replacement gives the file a new inode on every update, which would
make a watch on the file's own descriptor go stale on every single write;
watching the directory instead sidesteps that, since the directory's own
inode never changes, so registration is one-time and effectively free while
idle.

## Security notes

- `statusline.sh` never interpolates the hook JSON into a shell command --
  it's only ever piped into `jq` as data, so there's no shell-injection
  surface from the JSON's contents.
- The app reads a fixed path under your own home directory
  (`~/.claude/usage-status.json`); malformed or missing JSON is treated the
  same as "no data" (an icon, not a crash or a dialog) -- there's nothing
  actionable a user could do about either case from this app, so that failure
  mode is by design, not a swallowed error.
- No personal paths, usernames, or team IDs are hardcoded anywhere in this
  repo; codesigning uses whatever identity is available locally (falls back
  to ad-hoc if no certificate is found -- see `build.sh`).

## License

MIT, see `LICENSE`.
