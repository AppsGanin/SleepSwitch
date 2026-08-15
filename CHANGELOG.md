# Changelog

## 1.1.1

- Removed the «Keep the screen on» checkbox. The screen now stays lit whenever the mode is
  on, and dims normally when it is off. The switch was confusing: its only effect showed up
  after the idle timer expired — tens of minutes later — so toggling it looked like it did
  nothing at all.

## 1.1.0

- English and Russian throughout: app menu, alerts, and the installer, following the
  system language.
- Update check against GitHub releases, once a day, switchable from the menu. The app
  downloads the `.pkg` and hands it to the system Installer instead of replacing itself;
  requests are pinned to `https` on GitHub hosts, redirects included.
- A missing translation now fails the build — `Tools/check-localization.sh` diffs the
  `L("…")` keys in the sources against every `Localizable.strings`.
- Tests for version comparison and download-source filtering, run in CI.

## 1.0.1

- App icon, drawn in code at build time.
- English README alongside the Russian one.

## 1.0.0

- Menu bar toggle: blocks lid-close sleep via `pmset -a disablesleep`, and idle sleep and
  display sleep via IOKit assertions.
- `.pkg` installer with an optional, narrowly scoped `sudo` rule so toggling never asks
  for a password.
- The sleep ban lifts itself on quit and on `SIGTERM`, and the real state is read back
  from `IOPMrootDomain` at launch.
- Universal binary, GitHub Actions build and release by tag.
