# Security policy

## Reporting a vulnerability

Please report privately through GitHub, on the repository's Security tab, using
"Report a vulnerability". Do not open a public issue for anything exploitable.

I will confirm within a few days, and credit you in the release notes unless you
prefer otherwise.

## What this app can and cannot reach

Useful when judging severity:

- It makes **no network requests**, has no telemetry and no update check.
- It never reads Claude's profile, cookies, keychain items or chats.
- It writes only its own launchers in `~/Applications`,
  `~/.claude-instances/clones.json`, and `~/Library/Logs/ClaudeClones.log`, which is
  owner readable only.
- `claude://` links are redacted before being logged or displayed, so magic-link
  tokens and OAuth codes are not written to disk. A regression here is a real
  vulnerability, please report it.
- It never modifies `/Applications/Claude.app`, and it re-signs nothing.

## Scope

The clone launchers are shell scripts that run the Apple-signed Claude binary. If you
find a way to make one execute something other than that binary, that is in scope.
