# Koderkatins

A small cat that lives on your Mac desktop and keeps an eye on your **Claude Code** usage.

- **Every active session** at a glance: its title, project, state (working · your turn · needs you · idle), input and output tokens, cache reads and context size, plus totals
- **5-hour and weekly plan limits**: the percentage used and a countdown to the next reset (green below 70%, orange from 70%, red from 90%)
- **Five skins built in** (Koderkatis, Grinkats, Juodkats, Purpalins, Ryzkats), plus your own: any [petdex](https://github.com/crafter-station/petdex)-format sprite sheet, or one you make with ChatGPT using the [ready-made prompts](docs/SPRITES.md)
- **The pet reacts to what's happening**:

  | Koderkatis… | when |
  | --- | --- |
  | types | Claude is writing (the session log changed in the last few seconds) |
  | thinks | a session is mid-turn but quiet (the model is thinking or a tool is running) |
  | celebrates | a turn just finished |
  | looks puzzled | a session needs you (permission or question, via the optional hook) |
  | gets sleepy | you're close to a plan limit, or no session is active |
  | idles | sessions are open but waiting for you |
- **Sound alerts you can configure**, for example a mew every 3 minutes once the 5-hour limit passes 90%, when more than 5 sessions are active, or when a session needs your attention
- **Fully configurable**: choose what the panel shows, the panel size (compact, regular or large), and the pet's size from small to huge

It's a native Swift/SwiftUI app with no Dock icon. It floats above other windows on every Space, never takes keyboard focus, and remembers where you dragged it. It's light on resources: after it settles it uses about 0.1% CPU and 30–40 MB of memory (see [Performance](#performance)).

> **Unofficial.** Koderkatins is a community project. It is not affiliated with, endorsed by, or supported by Anthropic. "Claude" and "Claude Code" are trademarks of Anthropic.

---

## Quick start

**Download:** get `Koderkatins-<version>.zip` from [Releases](https://github.com/tjrtm/koderkatins/releases), unzip it and move `Koderkatins.app` to Applications. The app isn't notarized (it's a free hobby project), so macOS blocks the first launch. Either right-click the app and choose **Open**, or run `xattr -dr com.apple.quarantine /Applications/Koderkatins.app` once.

**Or build it yourself** (about 10 seconds):

```sh
xcode-select --install                 # once: Swift compiler (skip if you have Xcode)
python3 -m pip install --user pillow   # once: used to make the app icon

git clone https://github.com/tjrtm/koderkatins.git
cd koderkatins
./build.sh --install                   # builds and copies the app to ~/Applications
open ~/Applications/Koderkatins.app
```

A cat appears in the bottom-right corner of your main screen, and 🐾 appears in the menu bar.

Requirements: **macOS 14 or later**, and Claude Code logged in with a Claude subscription if you want the limit bars. Token counts work without logging in.

The app is signed ad hoc, so it's trusted only on the Mac that built it. If you copy the built app to another Mac, Gatekeeper will block the first launch. Right-click it and choose **Open** to allow it, or build it on that Mac.

## Using it

| Do this | What happens |
| --- | --- |
| Click the cat | Show or hide the stats panel. If a session needs attention, the first click acknowledges the alert. |
| Drag the cat | Move it anywhere. The position is remembered. |
| 🐾 → Skins | Switch skins, or open the Skins folder to add your own |
| 🐾 → Size | Small, Medium, Large or Huge. Settings has a slider for any size in between. |
| 🐾 → Motion | **Still**, **Calm** (default), **Normal** or **Lively**. Settings has sliders for speed and the rest between loops. |
| 🐾 → Check Plan Limits Online | Switch off and the app never goes online (see [What it reads](#how-it-works-and-what-it-reads)) |
| 🐾 → Settings… (⌘,) | Everything below |
| 🐾 → Launch at Login | Start automatically when you log in |

### Settings

- **Koderkatins**: choose the skin and its size; open or reload the Skins folder. **Motion**: a preset, or exact speed (2–8 frames per second) and rest between loops (0–10 s), plus smooth cross-fading between frames. Idle and sleepy always play at half speed. Animations switch only when a loop finishes, so the cat never jumps mid-move. **Still** holds one pose and only moves when a session needs you or finishes.
- **Display**: turn plan-limit checks on or off and choose how often they run (1–30 min; 2 by default). Show or hide the stats panel; choose the panel size (Compact, Regular, Large) and exactly what it shows: session counts, 5-hour bar, weekly bar, session list, session titles, input/output tokens, cache reads, context size, totals. You can also set how many sessions to list (all by default; the list scrolls) and how recent "active" means (15 minutes by default).
- **Alerts**: master switch and volume. For each event you can pick a sound: one of the macOS sounds, any audio file, or anything you put in the **Sounds folder** (`~/Library/Application Support/Koderkatins/Sounds`).

| Alert | Default | Configurable |
| --- | --- | --- |
| 5-hour limit is high | on: at **90%**, repeats **every 3 min** while it stays there | threshold, repeat interval, sound |
| Weekly limit is high | off: at 90%, every 30 min | threshold, repeat interval, sound |
| More than N active sessions | on: N = **5**, plays once each time the count goes above N | N, sound |
| A session finished its turn | off | sound |
| A session needs attention | on (needs the hook below) | sound |

Want a real mew? Download any short cat sound you like (an mp3 is fine), drop it into the Sounds folder, and pick it in the alert's sound menu. No sound files are bundled because most free sound sites don't state a licence.

### "Needs attention" alerts (optional, one-time setup)

Claude Code can run a command whenever it needs you, for example to approve a tool or answer a question. Koderkatins listens for that **only if you opt in** by adding Claude Code's official `Notification` hook. The app never edits Claude Code's settings itself.

Open `~/.claude/settings.json` and add this (merge it into an existing `"hooks"` block if you already have one). **Settings → Alerts → Copy Hook Setup** puts the same text on your clipboard:

```json
"hooks": {
  "Notification": [
    { "hooks": [ { "type": "command",
      "command": "mkdir -p \"$HOME/Library/Application Support/Koderkatins/signals\" && cat > \"$HOME/Library/Application Support/Koderkatins/signals/$(date +%s)-$$.json\"" } ] }
  ]
}
```

The hook writes Claude Code's small notification message (session ID and text) to a file. Koderkatins reads that file, deletes it and alerts you. That session's row turns red, and the cat waves until the session continues or you click the cat. Settings shows ✓ once the hook is detected.

Without the hook you still get **"finished its turn"**, which is read from the session logs.

## Skins

- **Make one with ChatGPT**: [docs/SPRITES.md](docs/SPRITES.md) has detailed, copy-paste prompts (character sheet plus 5 animations) and a one-command importer (`tools/import_sprites.py`). The importer removes the background, finds the frames, scales them all to one size and lines up their feet.
- **Use a petdex pet**: drop its folder (`spritesheet.webp` + `pet.json`) into 🐾 → Skins → Open Skins Folder… (`~/Library/Application Support/Koderkatins/Pets`).
- **Ship it in the app**: put the folder in `pets/` in this repo and run `./build.sh`. It's bundled automatically.

Built-in skins, each with 36 poses (idle, typing, thinking, celebrating, puzzled, sleepy): **Koderkatis** (default), **Grinkats**, **Juodkats**, **Purpalins** and **Ryzkats**. They live in `pets/` and were imported from single ChatGPT sheets with `tools/import_sprites.py`.

## How it works and what it reads

Everything is read-only and stays on your Mac. The only network request is the optional limits check, which you can switch off.

| Data | Source |
| --- | --- |
| Tokens, session titles, turn state | Claude Code's local session logs at `~/.claude/projects/**/*.jsonl` (including subagent logs). Re-read when macOS reports a change (FSEvents), plus a 10 s safety check. Only new bytes are read, and only from sessions active in the last few minutes; progress is cached in `~/Library/Caches/Koderkatins`, so a relaunch doesn't re-read history. Usage is de-duplicated by message ID. |
| Running sessions | `~/.claude/sessions/<pid>.json`, counted only while that process is alive |
| Needs attention | Files written by your optional Notification hook to `~/Library/Application Support/Koderkatins/signals/` |
| 5-hour / weekly limits | `GET https://api.anthropic.com/api/oauth/usage` every 2 min (configurable, or off), using the OAuth token Claude Code keeps in your login Keychain (`Claude Code-credentials`). The last result and the time of the last request are remembered, so restarting the app never sends an extra request. If Anthropic answers "too many requests" the app waits 5, 10, 20… up to 60 min and keeps showing the last values. It's skipped entirely when no limit bar or limit alert is switched on. The request sends no prompts or code, uses no tokens and doesn't count against your plan. |

**About the limits endpoint:** it isn't a documented public API. It's the endpoint Claude Code itself uses to show usage. It could change or stop working at any time, and calling it from a third-party app may not be allowed by Anthropic's terms. **You use it at your own risk.** If the request fails, everything else keeps working and the panel shows a short message. The token is read fresh for each request and is never written to disk, logged or sent anywhere except `api.anthropic.com`. The first time the app reads it, macOS may ask whether to allow access to the Keychain item.

Settings are stored in `~/Library/Preferences/io.github.koderkatins.plist`. To uninstall, quit the app and delete it, that plist and `~/Library/Application Support/Koderkatins`.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Limit bars show "—" or `HTTP 401` | Open Claude Code once so it refreshes its login, then choose 🐾 → Refresh Now. |
| "limits paused by Anthropic, retrying at …" | The endpoint answered "too many requests" (HTTP 429), often because another usage tool is polling too. Koderkatins keeps the last values and retries by itself; you can also check less often in Settings → Display. |
| No sessions listed | Sessions only count as active if they were used within the last 15 min (configurable). Check what the app sees with `~/Applications/Koderkatins.app/Contents/MacOS/Koderkatins --dump`. |
| Cat is off-screen after unplugging a monitor | `defaults delete io.github.koderkatins "NSWindow Frame KoderkatinsPet"`, then restart the app. |
| No sound | Check 🐾 → Sounds is ticked, then use the ▶︎ preview button next to the sound in Settings → Alerts. |

## Performance

Koderkatins is meant to sit on a laptop all day without being noticed. On an M4 Mac mini, with 283 log files (874 MB) and one busy session:

| | Before tuning | Now |
| --- | --- | --- |
| CPU, Calm motion (default) | 3.1 % | **0.1 %** |
| CPU, Still | — | **0.1 %** |
| Memory | 269 MB | **30–40 MB** |
| First log scan (454 MB active session) | 6.3 s | 1.6 s, then **0.01 s** on relaunch (cached) |

How: frames are played by Core Animation (`layer.contents` + a fade the window server does), not by re-rendering SwiftUI; frames are pre-scaled once to screen pixels; animation stops while the cat is hidden, the screen is off or you've switched user; logs are watched with FSEvents instead of polled; long log lines are only searched near their end, where the usage record is, instead of JSON-decoding megabytes; the UI is only updated when a value actually changed.

## Development

```
Sources/main.swift        app delegate, floating window, menu, data model, --dump
Sources/Scanner.swift     incremental reader for the Claude Code session logs, hook signals
Sources/Usage.swift       plan-limit client
Sources/Pets.swift        pet library, sprite-sheet slicing, pre-scaled frame cache
Sources/SpritePlayer.swift  Core Animation frame player (timer per frame, pauses when hidden)
Sources/Debug.swift       opt-in diagnostics file (KODERKATINS_DEBUG=1)
Sources/Sounds.swift      sound playback and the alert rules
Sources/Views.swift       pet, stats panel and Settings (SwiftUI)
Sources/Prefs.swift       all settings (UserDefaults)
tools/import_sprites.py   turns ChatGPT images into a sprite sheet (stabilises frame-to-frame wobble)
tools/bench.py            measures the running app's steady CPU with `top`
pets/                     the skins bundled into every build
docs/SPRITES.md           pet-making guide with prompts
build.sh                  compile → bundle → sign → zip (→ --install)
```

No Xcode project and no dependencies beyond the Swift toolchain and Pillow. `./build.sh` takes about 10 seconds. Useful flags:

- `Koderkatins --dump` prints sessions, skins, hook status and the cached limits, then exits (`--limits` fetches them live, `--cold` ignores the scan cache)
- `python3 tools/bench.py calm motion=1` relaunches the app with those settings and reports its average CPU
- `open --env KODERKATINS_DEBUG=1 ~/Applications/Koderkatins.app` keeps `~/Library/Caches/Koderkatins/debug-state.json` up to date with what the app is really doing (animation speed, frame count, skin, window size, sounds played, limit requests). Handy for checking that a setting took effect; off by default.
- `Koderkatins --settings` opens the Settings window at launch
- `VERSION=1.2.0 BUNDLE_ID=com.example.pet ./build.sh` overrides the version and bundle ID

Pull requests are welcome: new skins (with a licence you're allowed to grant), translations and fixes.

## Licence

[MIT](LICENSE) for the code and the bundled skin artwork.
