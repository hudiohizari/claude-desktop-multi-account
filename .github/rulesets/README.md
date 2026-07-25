# Rulesets

Import these instead of hand configuring branch protection: Settings, Rules,
Rulesets, New ruleset, Import a ruleset, then pick the JSON.

- `main-branch.json` protects the default branch: pull request required, CI must
  pass, conversations resolved, linear history, no force push, no deletion.
- `tags.json` makes `v*` tags immutable, so a published release cannot be quietly
  repointed.

Both give the **repository admin** bypass, which keeps a solo maintainer able to push
directly, and lets the release workflow's cask bump land on `main`. If you tighten
that to no bypass, change the "Bump the cask" step in
`.github/workflows/release.yml` to open a pull request instead of pushing, otherwise
releases will fail at that step.

The two required checks are named `Test and build` and `Style`, matching the job
names in `ci.yml`. Rename a job and you must update the ruleset.
