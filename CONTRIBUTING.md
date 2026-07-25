# Contributing

Thanks for looking. This is a small, focused utility, so the bar for new features is
"does it help someone run more than one Claude account", and the bar for fixes is
low: open a PR.

## Getting set up

```bash
git clone https://github.com/hudiohizari/claude-desktop-multi-account.git
cd claude-desktop-multi-account
swift test          # unit tests, no side effects outside a temp directory
./build.sh          # build/Claude Clones.app
./build.sh --install
```

`Package.swift` exists so `swift test` can compile the sources. The app bundle comes
from `build.sh`, which stamps the version from the `VERSION` file.

## House rules

- **No em dashes.** Use a comma, or a plain hyphen. CI enforces this.
- **No `NSLog` or `print` outside `CLI.swift`.** LaunchServices discards stderr, so
  use `Log.write`. CI enforces this too.
- **One line commit subjects**, conventional prefix, no body: `fix: keep renamed
  clones in store`.
- Match the surrounding code. Protocols exist where two consumers need them, not by
  default.

## Tests

Anything that touches the filesystem, LaunchServices or a process goes behind a
protocol and gets stubbed. Tests must never write to `~/Applications`,
`~/.claude-instances` or the LaunchServices database; `Sandbox` in the test support
file gives you a temp directory and a `Layout` pointing at it.

Three behaviours in `WrapperBuilderTests` are load bearing and cost real debugging to
find, so please do not relax them:

- the wrapper Info.plist must **not** declare `LSEnvironment`
- it must declare `LSArchitecturePriority = [arm64]`
- the launch script must record its pid and focus a running instance rather than
  starting a second one

## Releasing

Maintainers only:

```bash
./scripts/release.sh 0.2.0
```

That bumps `VERSION`, tags, and pushes. The tag triggers the release workflow, which
tests, builds, signs, notarizes when secrets are present, publishes, and bumps the
cask.
