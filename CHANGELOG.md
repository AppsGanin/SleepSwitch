# Changelog

## 1.3.1

- The battery settings are hidden on a Mac with no built-in battery instead of sitting
  there inert.
- The battery is now identified by power-source type rather than by taking the first source
  the system lists. A UPS is a power source too, so on a desktop it could have passed for a
  battery — and on a laptop with a UPS attached the app could have read the wrong one.

## 1.3.0

- **Battery guard.** Keeping a Mac awake makes one mistake easy — mode on, lid shut, laptop
  in a bag, running hot until the battery is flat. The mode now switches itself off at a
  charge you choose, 20% by default, and optionally the moment the power adapter is
  unplugged. A notification says which of the two fired.
- Neither trips on a desktop Mac or when the battery reading is missing: dropping the mode
  for a reason the app cannot name would be worse than leaving it alone.
- Power source changes arrive as events rather than polling — `IOPSNotificationCreateRunLoopSource`
  is public, unlike anything covering the sleep ban.

## 1.2.1

- Notification permission is asked for once, the first time there is an update to report,
  instead of on every check. If notifications are denied the app falls back to a window,
  but only once per version — a daily popup would be exactly the interruption the
  notification was meant to avoid.
- The sleep-mode state machine now takes its privileged half as a dependency, so the paths
  that matter are covered by tests: a declined password leaves the mode partial rather than
  off, a ban the app did not set is never cleared on the way out, logging out never opens a
  password dialog, and partial mode is not mistaken for the mode being switched off.

## 1.2.0

- A background update now arrives as a system notification with **Download** and **Skip
  this version**, instead of a modal dialog thrown over whatever you were doing. A check
  you start from the menu still answers in a window — you are waiting for that one.
- Turning the mode on at launch no longer means a password dialog at every login. Without
  the sudo rule it comes up in partial mode instead, and ticking the checkbox now explains
  that and offers to set the rule up.
- State is re-read every 30 seconds rather than every 5, plus on wake and whenever the menu
  opens. macOS publishes no notification for this setting — the general IOKit interest
  notification on IOPMrootDomain does not fire for it and IOPMLib exposes nothing public —
  so polling stays, just far less of it.
- The sources are split by responsibility instead of living in one file, and all code,
  comments and script output are English.

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
