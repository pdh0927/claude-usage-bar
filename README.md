# clife

[한국어](README.ko.md)

A little macOS menu bar app that shows your Claude Code usage limits — current
session and weekly — as a small ring gauge, so you don't have to guess when
you're about to get rate-limited.

I made this because I kept losing track of how close I was to my 5-hour
window resetting mid-task. It reads a JSON snapshot that a one-line addition
to your `statusline.sh` writes out every time Claude Code runs.

**Not an official Anthropic product.** Just a side project. No affiliation
with or endorsement from Anthropic — "Claude" and "Claude Code" are their
names, mentioned here only because that's what this thing reads data from.

**You need a Claude Code Pro or Max subscription for this to show anything.**
The fields it reads (`rate_limits.five_hour.used_percentage` and
`rate_limits.seven_day.used_percentage`) only show up in the statusLine hook
JSON for Pro/Max accounts, and only after Claude Code's first response in a
session. If you're on another plan, or haven't sent a message yet, you'll
just see a "no data" icon — that's expected, not broken. Anthropic's own docs
cover this under "Rate limit usage": https://code.claude.com/docs/en/statusline.md

## How it works

Claude Code calls `~/.claude/statusline.sh` every time it renders a prompt,
and pipes it a JSON blob that includes your current rate-limit usage (if
you're Pro/Max). A one-line addition to that script grabs the two
percentages and writes them to `~/.claude/usage-status.json` — atomically
(temp file, then `mv`), so the app never catches it half-written.

The app itself just watches that file and redraws the icon whenever it
changes. No polling, no timers ticking in the background for no reason.

## Install

```sh
git clone <this-repo> clife
cd clife
./setup.sh
```

That wires up your `statusline.sh` and `settings.json`, builds the app,
drops it in `/Applications`, and opens it. One command. You'll probably hit
a Gatekeeper warning on first launch — see below, it's a two-click fix.

If you'd rather do it in pieces, `setup.sh` is just `install.sh` → `build.sh`
→ a `ditto` install, run in order. Each one works fine on its own — useful
if you're rebuilding after tweaking the Swift source and don't want to redo
the statusline wiring every time.

`install.sh` won't clobber anything you already have:
- No `~/.claude/statusline.sh`? It creates a minimal one.
- Already have one? It appends the snippet (see `statusline-snippet.sh`)
  instead of overwriting it — but only if your script reads the hook JSON
  the usual way (`input=$(cat)`). If it can't tell, it just prints the
  snippet for you to paste in by hand rather than risk breaking your setup.
- No `statusLine` in `settings.json`? It adds one. Already have a different
  one configured? It leaves it alone and tells you what to do instead.

If you want to install/reinstall into `/Applications` by hand (say, after
running `./build.sh` on its own):

```sh
pkill -f Clife.app/Contents/MacOS/Clife 2>/dev/null
rm -r -f /Applications/Clife.app
ditto Clife.app /Applications/Clife.app   # not cp -R, see below
open /Applications/Clife.app
```

Don't use `cp -R` here — if `/Applications/Clife.app` already exists,
it copies *into* it instead of replacing it, and you end up with a
nested app bundle that never actually updates. Ask me how I know. `ditto`
just does the right thing either way.

### That Gatekeeper warning

The app is signed locally (ad-hoc, or with a free Apple Development cert if
Xcode has one for you) but it's not notarized by Apple, so a plain
double-click gets refused the first time. Right-click the app in
`/Applications` → Open → Open, once. macOS remembers after that, and it'll
launch normally from then on, login items included.

## Uninstall

```sh
pkill -f Clife.app/Contents/MacOS/Clife
rm -r -f /Applications/Clife.app
```

Then, if you want to fully clean up, delete the snippet block from
`~/.claude/statusline.sh` (it's between `# >>> clife` and
`# <<< clife`) and remove `~/.claude/usage-status.json`.

## Display mode

The dropdown has two options — "아이콘으로 보기" (icon) and "숫자로 보기"
(plain text, like `54%/29%`, which is how the very first version of this
looked). Whichever you pick gets saved and remembered next launch; icon is
the default. Both read from the same file-watch, so switching between them
is instant either way.

## Why it looks the way it does

The icon is two colored rings — outer for the current 5-hour session, inner
for the 7-day window — each going green/yellow/red at the same 70%/90%
thresholds the statusline's own context bar already uses. I checked a
contact sheet of the icon at real menu-bar size (20pt, both scales, both
light and dark mode) before committing to this, and the two rings stay
readable even that small.

I went with color instead of a plain monochrome template icon because two
separately-thresholded numbers need more than grayscale to read at a glance
at that size. The cost is that a colored icon doesn't get the automatic
dark-mode tinting a template image gets for free — a fair trade here, I
think. Either way, the exact numbers are never just implied by the rings;
they're always spelled out in the tooltip and the dropdown. And if the
status file is missing or unreadable, you get a `questionmark.circle` icon
instead of an empty ring, so "no data" never looks like "0% used".

On the technical side: it watches `~/.claude` (the status file's parent
directory) for changes instead of polling on a timer. The status file gets
replaced atomically via `mv`, which means it gets a new inode every single
update — watching the file directly would mean reopening the watch on every
write. Watching the directory instead sidesteps all of that, since the
directory's inode never changes. One-time setup, basically free while idle.

## A note on security

- `statusline.sh` never interpolates the hook JSON into a shell command —
  it only ever gets piped into `jq` as data, so there's no injection path
  through the JSON's contents.
- The app just reads a fixed file under your own home directory. Bad or
  missing JSON shows the same "no data" icon as anything else — there's
  nothing you could actually do differently for a missing file vs. a
  malformed one, so that's intentional, not a swallowed error.
- Nothing personal — no usernames, paths, or team IDs — is hardcoded
  anywhere in here. Codesigning just uses whatever identity happens to be
  available on your machine, falling back to ad-hoc if there isn't one (see
  `build.sh`).

## License

MIT — see `LICENSE`.
