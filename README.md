# Claude Clones

Menu bar app for running several Claude Desktop accounts side by side on macOS,
each with its own login, chats, MCP servers and Cowork VM — and for deciding
which one an incoming `claude://` link opens in.

Every clone launches the untouched `/Applications/Claude.app` binary, so the app
keeps its Apple signature and entitlements. Nothing is copied or re-signed.

## Build

```bash
./build.sh --install
```

Puts `Claude Clones.app` in `~/Applications` and registers it. Open it; it lives
in the menu bar only (no Dock tile).

## Use

- **New Clone…** creates `~/Applications/Claude <name>.app` plus its profile at
  `~/.claude-instances/clone-N`. The launcher icon carries the clone number.
- Clicking a clone launches it, or focuses it if it is already running.
- Submenus: rename, reveal the profile, delete (launcher only, or with the profile).
- **Route claude:// links here** makes this app the handler. From then on every
  deep link asks which profile should open it. The menu item toggles back.

Same operations without the UI:

```bash
"~/Applications/Claude Clones.app/Contents/MacOS/ClaudeClones" --list
```

`--create <name>`, `--delete <name> [--with-profile]`.

## Layout

| File | Responsibility |
|---|---|
| `Clone.swift` | Value type: identity and derived paths |
| `CloneStore.swift` | `CloneStoring` — persistence (`clones.json`) |
| `WrapperBuilder.swift` | `CloneProvisioning` — writes/moves/removes the .app, badges the icon, registers it |
| `InstanceLocator.swift` | `InstanceLocating` — which process belongs to which clone |
| `LinkRouter.swift` | `LinkDelivering` — hands a link to one instance; scheme ownership |
| `CloneManager.swift` | Use cases shared by the menu and the CLI |
| `MenuBarController.swift` | UI only; depends on the protocols, never on LaunchServices directly |
| `Prompt.swift` | Every dialog |
| `CLI.swift` | Headless commands |
| `main.swift` | Composition root |

Protocols exist where the menu and the CLI both consume them, or where the system
boundary needs to be swappable for a test. Small helpers (`IconBadger`,
`BundleRegistrar`, `DiskSize`) stay concrete — an interface with one
implementation and one caller earns nothing.

## How it works, and why it is built this way

Measured on macOS 26 (Darwin 25.5) with Claude Desktop 1.24012.9:

- **Profiles.** `CLAUDE_USER_DATA_DIR` redirects `userData` *and* the log
  directory into the profile. The Chromium `--user-data-dir` flag isolates the
  data but leaves every instance writing one shared `~/Library/Logs/Claude/main.log`.
- **`LSEnvironment` does not work.** A bundle declaring it fails to launch with
  `_LSOpenURLsWithCompletionHandler() failed with error -54`, before the
  executable runs. The wrapper script exports the variable instead.
- **Do not codesign the wrappers.** Ad-hoc signing a bundle whose main executable
  is a shell script makes launchd refuse it (`Launchd job spawn failed`, POSIX 162).
- **Deep links cannot be aimed with LaunchServices.** All instances share one
  bundle id, so `claude://` always reaches the *first-launched* instance,
  regardless of which window is in front. Registering a second bundle only moves
  the default handler; `open -b` on a wrapper spawns a duplicate process rather
  than delivering to the running one.
- **A `GURL` Apple Event addressed to a pid does land in that exact process.**
  That is how routing works here: verified by sending a link to a clone and
  finding it in that clone's log while the default profile's log stayed
  untouched. macOS will ask once for Automation permission.
- **One process per profile.** A second process on the same profile comes up
  signed out, so the wrapper focuses the running instance instead of launching
  again. It records its pid before `exec`, and `exec` keeps the pid, so the pid
  file identifies the Claude process itself.

## Shared, unavoidably

The app binary, the `Claude Safe Storage` keychain key (same bundle, so no
prompts, and each instance only decrypts its own cookies), the `claude://`
handler, `~/.claude` if you use the Claude Code CLI, and your filesystem — a
Cowork VM mounts your home directory, so clones see the same files.
