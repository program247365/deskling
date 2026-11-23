<p align="center">
  <img src="docs/clawd-waving.gif" width="260" alt="Clawd, a small orange pixel creature, waving hello">
</p>

<h1 align="center">Deskling</h1>

<p align="center">
  Little pixel friends that live along the bottom of your Mac's screen, and come and find you when your coding agent needs you.
</p>

<p align="center">
  <a href="https://github.com/program247365/deskling/releases/latest"><img src="https://img.shields.io/github/v/release/program247365/deskling?style=flat-square" alt="Latest release"></a>
  <a href="#install"><img src="https://img.shields.io/badge/platform-macOS%2014%2B-555?style=flat-square" alt="macOS 14 or later"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/program247365/deskling?style=flat-square" alt="License"></a>
  <a href="https://github.com/program247365/homebrew-tap"><img src="https://img.shields.io/badge/Homebrew-program247365%2Ftap-FBB040?style=flat-square&logo=homebrew&logoColor=white" alt="Homebrew tap"></a>
</p>

<p align="center">
  <b>Clawd is Anthropic's character. This is an unofficial fan project.</b>
</p>

---

Pick a Deskling and they live in your menubar and walk along the bottom of your screen. Every so often they stop to perform: Clawd fishes and juggles, Minx leaps onto a pumpkin, Sol sets and rises again, Luna goes through her phases. Clicks pass straight through them, so they never get in the way.

The cast:

| | |
| --- | --- |
| **Clawd** | The original. Orange, earnest, always busy. |
| **Octo** | A spotted purple octopus with a long wavy arm. |
| **Minx** | A curious black cat. Especially curious about pumpkins. |
| **Sol** | The sun, up early and out late. |
| **Luna** | The moon, sleepy and soft. |

Meet the cast, and try them on the page, at **[deskling.kbr.sh](https://deskling.kbr.sh)**.

## Install

```sh
brew install --cask program247365/tap/deskling
```

Or download [Deskling.dmg](https://github.com/program247365/deskling/releases/latest/download/Deskling.dmg), open it, and drag Deskling to Applications.

Requires macOS 14 or later, on Apple silicon or Intel. The app is signed and notarized. Windows and Linux are planned.

Coming from Clawd? Deskling brings your settings across the first time it runs. Turn Launch at Login back on from the menu; macOS treats Deskling as a new app.

## Quick start

```sh
open -a Deskling
```

The first time, you pick your Deskling on a character-select screen: arrow keys and Enter, or click. They drop in from the top of the screen under a spotlight, land, wave, and get going. Their icon appears in the menubar.

## What a Deskling does

| | |
| --- | --- |
| **Makes an entrance** | On launch they fall in under a stage spotlight, land, and wave. |
| **Walks and performs** | They patrol the bottom of the screen, on top of the Dock, and play each of their acts once before repeating any. |
| **Roams, if you let them** | They stay at the bottom by default. Choose "Let them roam!" in Settings and about one time in four they pop up somewhere else to perform. |
| **Notices you** | Bring the cursor near and they stop, turn to face it, and look up if it's above them. Leave it there and after a while they get back to work. |
| **Likes a pet** | Rub the cursor back and forth over them and they show you they like it. No click needed. |
| **Naps while you're away** | After five minutes without a key press or a mouse move they fall asleep where they stand, and wake up when you come back. |
| **Visits your lock screen** | Turn on "Bring them along to the lock screen" and they keep walking while your Mac is locked. |
| **Stays out of the way** | They sit above your windows but never take a click, a scroll, or focus, and they step aside for fullscreen apps. |
| **Fits your screen** | Small, Medium, or Large, from the menu. |
| **Keeps up to date** | Once a day they check for a new version. When there is one they tell you in their speech bubble; click them to update, and they come back saying so. You can turn the daily check off in Settings. |

From the menubar you can switch characters, hide them, change their size, turn on Launch at Login, check for updates, and open Settings (⌘,).

Updates come through [Sparkle](https://sparkle-project.org). The daily check fetches the update feed from GitHub and sends nothing about you or your Mac; every update is signed, and the app refuses one that isn't.

### About the lock screen visit

macOS has no official way for an app to appear on the lock screen. Deskling gets there with private window-server functions, so the option is off by default, and a macOS update could break it. If the functions are missing, the option turns itself off. It is confirmed on macOS 27 and untested on earlier versions.

### Why it isn't on the Mac App Store

The lock screen visit alone rules it out: the App Store accepts only apps that use public APIs (guideline 2.5.1), and Deskling loads the private SkyLight framework to get there (`LockScreenVisitor.swift`). Dropping that feature wouldn't be enough, though:

- **No sandbox.** App Store apps must run in the App Sandbox, and Deskling doesn't.
- **Sparkle updates.** App Store apps can't update themselves.
- **Focusing your terminal.** Clicking the character runs `osascript` to bring Terminal's tab forward, which a sandboxed app can't do without Apple Events exceptions that Apple grants case by case.
- **Agent hooks and the `deskling` command.** Agents reach the app through system-wide notifications and report which terminal they're in. That would need checking, and likely redesigning, inside the sandbox, and the App Store can't install the hooks or the command for you.
- **Clawd.** Clawd is Anthropic's character and this is an unofficial fan app, which the App Store rejects without the owner's permission (guideline 5.2).

An App Store version would be a separate, smaller build without the lock screen, Sparkle, terminal focusing, or Clawd. For now Deskling ships as a signed and notarized download and through Homebrew.

### Claude Code and Codex

Your Deskling can act out what your coding agents are doing (thinking, typing, editing, browsing), celebrate when one finishes, and come to the middle of the screen to wave when one is waiting on you. With more than one display they come to the one your cursor is on, follow you if you move, and go home once you answer. The wave lasts until you answer or click. Click them, or their speech bubble, to jump to the agent and dismiss its alert; if there's more than one, the one that has waited longest, and they keep waving for the rest. In Warp and Terminal that's the agent's own tab (Terminal asks once for permission); in other terminals and editors, the app. Clicks only land on them while they wave; the rest of the time they pass straight through. Both are on by default in Settings and do nothing until an agent is connected.

**Claude Code:** run this in a session:

```
/plugin install deskling --marketplace program247365/deskling
```

**Codex:** open Settings, choose **Connect Codex**, then trust the new hooks in Codex with `/hooks`. Connecting adds Deskling's hooks to `~/.codex/hooks.json` without touching any you already have, and keeps the previous file as `hooks.json.before-deskling`. **Disconnect Codex** removes only Deskling's hooks. Codex calls them over when it asks for approval (its `PermissionRequest` hook). Codex has no idle notification, so they only celebrate when a Codex turn ends.

When more than one agent is waiting, the bubble names them if they fit ("api and web need you") and counts them otherwise, and they keep waving until the last one is answered. The menu lists each waiting session, like "Claude Code · api · 3 min"; choose one to stop waving for it, or **Dismiss All**.

The hooks send the app only the event type, the session id, the project folder's name, and the tool name. When an agent is waiting on you they also send the process ids above the hook, the app the shell was started from, the terminal device, and in Warp the tab's `WARP_FOCUS_URL`, so a click can find your terminal tab. Prompts, commands, and file contents never leave the agent. If the app isn't running, the hooks do nothing. Any other agent can join in by running `Deskling.app/Contents/Helpers/deskling-hook --agent <name> --event <kind>`. The event kinds are listed in `apps/deskling/Sources/DesklingHook/main.swift`.

### Letting agents speak

Agents, scripts, and you can also have your Deskling say things on purpose with the `deskling` command:

```sh
deskling say "Tests pass" --as celebrate   # words in a bubble, with an act if you name one
deskling act think                         # an act on its own
deskling alert "Review the migration plan" # come and wave until you answer or clear it
deskling alert "3 notes to review" --character nook  # Nook drops in to wave instead
deskling alert "3 notes to review" --character nook --open https://host:4648/  # clicking Nook opens that page
deskling alert "build is red" --open https://ci.example/run/42      # clicking your own character opens it
deskling clear                             # stop waving for this folder's alert
deskling mcp                               # the same four as tools on an MCP server over stdio
```

It ships inside the app as `Deskling.app/Contents/Helpers/deskling`; link it onto your `PATH` to use it from a shell (`ln -s /Applications/Deskling.app/Contents/Helpers/deskling ~/.local/bin/deskling`). The Claude Code plugin puts it on Claude's `PATH` and connects the MCP server, so Claude can use the `say`, `act`, `alert`, and `clear` tools. For other MCP clients, such as Claude Desktop, add a server whose command is that path with the argument `mcp`.

Text is cut to one line of 60 characters, and words sent within four seconds of the last are dropped, so a chatty agent can't keep them talking. Nothing is said while they wave for an agent. Words sent while they nap (you've been away for a while) are kept, the latest three, and when you're back they wake up, wave, and tell you. An alert belongs to the folder it was sent from: it's listed in the menu as "Agent · <folder>", clicking it goes to the sender's terminal and dismisses it, and otherwise it ends with `deskling clear` from that folder or, with the Claude Code or Codex hooks connected, your next prompt there. Name a character with `--character` (the MCP `alert` tool's `character`) and they drop in beside yours to wave instead, then leave when it's cleared or clicked; yours carries on and can still talk for your agents. Add `--open URL` (http or https only), with or without `--character`, and clicking whoever brought the alert opens that page instead of a terminal. Any program on your Mac can send an alert, so the first time a site would open, Deskling asks: **Open**, **Always Allow**, or **Cancel**. Always Allow remembers that site (scheme, host and port); `defaults delete sh.kbr.deskling allowedLinkSites` forgets them all. Unlike the hooks, these carry words an agent chose to show you; turn off **Let agents speak through them** in Settings to ignore them all.

## Development

The repo holds two apps:

| Path | What |
| --- | --- |
| `apps/deskling` | the Mac app (Swift package) |
| `apps/website` | the deskling.kbr.sh site, and Clawd's animation files |

Building needs a Swift 6 toolchain (Xcode 16 or newer). Everything runs from the repository root; `make` on its own lists every task.

```sh
make check
```

`make check` verifies every character's acts have their animations, that the site's copies of the characters match the app's, and that the site shows the version being released; then it builds the app and runs the tests, including ones that render every animation.

To run a local build of the app:

```sh
make run
```

That builds `apps/deskling/dist/Deskling.app` for your Mac with an ad-hoc signature. `make site` serves the website locally. Tasks that regenerate things made from the art live in the app's own Makefile: `make -C apps/deskling icons`, `readme-gif`, and `site-characters`, which copies the characters into the website, renders their stills, and redraws the site's cast background.

### Drawing a new character

Characters are drawn in [Aseprite](https://www.aseprite.org) and exported to Lottie files in the same format as Clawd's, so the app treats them all alike.

```sh
make -C apps/deskling new-character ID=pip    # apps/deskling/characters/pip/pip.aseprite + character.json
make -C apps/deskling export-characters       # writes each character's animations/ folder
```

The starter file is 27 x 18 pixels. One pixel is one of Clawd's body pixels, and the bottom row is the floor. Each tag holds Clawd traced onto a faded `reference` layer with his timing (12fps); draw on the `art` layer. The exporter skips any layer whose name starts with `ref`.

| Tag | Used for |
| --- | --- |
| `walk`, `stand` | Required. The step loop, and one standing frame |
| `wave` | The entrance, the character-select pick, and the "needs you" alert |
| `look-up` | One frame, eyes up, for when the cursor is above them. Exported as `looking`, which never plays as an act |
| `ready` | The character-select idle, fists up. Without it, their standing pose bounces through a crouch |
| `think`, `type`, `write`, `browse`, `search`, `delegate`, `compact`, `celebrate` | What agents are doing. Any you leave out are skipped. All but `celebrate` also play as ordinary acts |
| `pet` | When you rub the cursor over them. Without it they play `celebrate` |
| `nap`, `wake` | Looped while you're away, and played when you come back. Without `nap` they stand still |
| anything else | An extra act in the routine |

Set the name and blurb in `character.json`. Commit the exported `animations/` folder too, so building the app never needs Aseprite. The character shows up on the character-select screen and under **Character** in the menu, and gets a menubar icon made from their standing pose. If their eyes are not near-black, list the eye color in `character.json` as `"iconHoles": ["#e9b03a"]` so the icon cuts them out.

### Releasing

`make release` builds a universal app, signs it with a Developer ID, notarizes it with Apple, and leaves `Deskling.dmg` in `apps/deskling/dist`. It uploads nothing else. It needs notary credentials in a keychain profile, stored once:

```sh
xcrun notarytool store-credentials clawd-notary   # the profile keeps its old name --apple-id <your Apple ID> --team-id <your team ID>
```

Set `APP_IDENTITY="Developer ID Application: You (TEAMID)"` to sign with your own identity.

`make publish` then uploads that disk image as a GitHub release for the version in `apps/deskling/VERSION` and updates the Homebrew cask from `scripts/deskling.rb.in`, in one commit to the tap. The first Deskling release also renames the cask from `clawd` to `deskling` and records the rename in the tap's `cask_renames.json`, so `brew upgrade` moves existing users across. Pass `NOTES=<file>` for hand-written release notes, and `BUBBLE=<file>` with one to three short lines (40 characters at most) that the character says when offering the update. `make publish` signs the disk image with the Sparkle update key in your login keychain and uploads `appcast.xml`, the feed the app reads, with the release. The website deploys on its own when `main` changes.

## License

MIT for the code — see [LICENSE](LICENSE). © 2026 Kevin B. Ridgway. The Clawd character and the animation files belong to Anthropic and are not covered by the license.
