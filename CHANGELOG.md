# Changelog

## 1.1.2

- The menu now shows which version you are running. With an app that updates itself, the
  answer used to require Finder → Get Info.
- A failed update check no longer counts as a check. Being offline once used to postpone
  the next attempt by a full day.
- CI installs the built `.pkg` for real and inspects what it did: the `sudo` rule is
  validated with `visudo`, its mode and owner are asserted, and it must grant exactly the
  two `pmset` commands and nothing else. Then `uninstall.sh` runs and the removal is
  verified. These installer scripts run as root and had no test coverage at all.

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
