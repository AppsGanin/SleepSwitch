<div align="center">

<img src="docs/icon.png" width="128" alt="SleepSwitch">

# SleepSwitch

**One click in the menu bar and your MacBook stops sleeping — lid closed included.**

[![Release](https://img.shields.io/github/v/release/AppsGanin/SleepSwitch?style=flat-square&color=5b63e8)](https://github.com/AppsGanin/SleepSwitch/releases/latest)
[![Build](https://img.shields.io/github/actions/workflow/status/AppsGanin/SleepSwitch/build.yml?branch=main&style=flat-square)](https://github.com/AppsGanin/SleepSwitch/actions)
[![Downloads](https://img.shields.io/github/downloads/AppsGanin/SleepSwitch/total?style=flat-square&color=5b63e8)](https://github.com/AppsGanin/SleepSwitch/releases)
[![macOS](https://img.shields.io/badge/macOS-13%2B-000?style=flat-square&logo=apple)](#requirements)
[![License](https://img.shields.io/github/license/AppsGanin/SleepSwitch?style=flat-square)](LICENSE)

[Русская версия](README.ru.md)

</div>

---

`caffeinate` keeps your Mac awake until you close the lid. Then it sleeps anyway, because
lid-close sleep is a separate setting that lives behind `sudo`. SleepSwitch flips both at
once, from a single menu bar icon.

Useful when you want to close the lid and keep a build, a download, a render, or an SSH
session running — without an external display, without a dummy HDMI plug, without leaving
the lid propped open.

## Features

- **Lid-close sleep off.** Shut the laptop, it keeps running.
- **Idle sleep off.** Your idle timer is ignored while the mode is on.
- **Screen stays lit** while the mode is on — no separate switch to think about.
- **Ask for the password once.** The installer sets up a narrowly scoped `sudo` rule, then
  toggling never prompts again.
- **Nothing left behind.** Quit the app — or kill it — and the sleep ban lifts itself.
- **Updates itself from GitHub** — checks daily, hands you the installer, never swaps
  binaries behind your back.
- **English and Russian**, app and installer, following your system language.
- **Two Swift files**, no dependencies, no background daemon, no telemetry.
- **Universal binary**, Apple Silicon and Intel.

## Install

Grab the `.pkg` from the [latest release](https://github.com/AppsGanin/SleepSwitch/releases/latest)
and open it.

> [!NOTE]
> The app is not signed with an Apple Developer certificate, so macOS blocks the first
> open. Right-click the `.pkg` → **Open** → **Open** again. One-time.

The installer drops the app in `/Applications`, launches it, and — unless you untick the
box under **Customize** — installs the passwordless `sudo` rule.

## Usage

| Action | Result |
| --- | --- |
| **Left click** the icon | Toggle the mode |
| **Right click** | Menu: launch behaviour, login item, updates, `sudo` rule |

The icon is the state:

| Icon | Meaning |
| --- | --- |
| 🌙 | Normal — your Mac sleeps as configured |
| ☕️ | Mode on — sleep fully blocked |
| ⚠️ | Partial — idle sleep blocked, but the lid still puts it to sleep |

## How it works

Two independent layers, because macOS treats these as two different things:

| Layer | Blocks | Needs root |
| --- | --- | --- |
| `pmset -a disablesleep 1` | Lid-close sleep, and all sleep | Yes |
| `PreventUserIdleSystemSleep` assertion | Idle sleep | No |
| `PreventUserIdleDisplaySleep` assertion | Display turning off | No |

The IOKit assertions are held by the process, so they evaporate the moment the app dies —
they can never get stuck. The `pmset` setting persists, so the app clears it on quit, on
`SIGTERM`, and reports the real state at launch by reading `SleepDisabled` straight from
`IOPMrootDomain`.

## About the sudo rule

`pmset disablesleep` needs root. Asking for a password on every toggle is unusable, so the
installer writes `/etc/sudoers.d/sleepswitch`:

```
you ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0
you ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1
```

Two commands, no wildcards. `sudo` matches arguments exactly, so this grants the ability to
toggle a sleep setting and nothing else — `pmset -a sleep 0` still asks for a password.

The rule is written, validated with `visudo`, and installed entirely as root inside a
mode-`0700` temp directory, so there is no user-writable file to swap in between the check
and the install. The username is validated before it reaches `sudoers`, and the rule is only
granted to an account in the `admin` group.

Opt out at install time, or later from the menu — or by hand:

```bash
sudo rm /etc/sudoers.d/sleepswitch
```

## Updates

The app asks GitHub once a day whether a newer release exists. If one does, you get an
alert with three choices: download, read the release notes, or later. Turn the check off
from the menu — then nothing goes over the network unless you ask.

SleepSwitch does not replace itself. It downloads the `.pkg` from the release and opens it
with the system Installer, so the upgrade goes through the same authenticated flow as the
first install. Requests are pinned to `https` on GitHub hosts, redirects included — anything
else is refused.

## Screen lock

Sleep and screen lock are separate macOS settings, and SleepSwitch only touches sleep. If
your Mac asks for a password when you reopen the lid, that is the lock, and macOS
deliberately requires your account password to change it — no app can flip it silently.

```bash
sysadminctl -screenLock off -password -        # disable
sysadminctl -screenLock immediate -password -  # restore
sysadminctl -screenLock status                 # check
```

The menu has a shortcut to the matching System Settings pane.

## Build from source

```bash
./make-installer.sh          # → dist/SleepSwitch-<version>.pkg
./install.sh                 # or straight into /Applications, no installer
./Tools/run-tests.sh         # tests; add --network to hit the real GitHub API
```

> [!NOTE]
> A local build leaves `build/SleepSwitch.app`, and Spotlight indexes it — so the app
> shows up twice in search next to the installed copy. `rm -rf build dist` clears it.
> `.metadata_never_index` does not help here; Spotlight ignores it for ordinary
> subfolders.

Xcode or the Command Line Tools is the only requirement. The app icon is drawn in code by
[`Tools/make-icon.swift`](Tools/make-icon.swift) at build time — no binary assets in the
repo. A missing translation fails the build:
[`Tools/check-localization.sh`](Tools/check-localization.sh) diffs the `L("…")` keys in the
sources against every `Localizable.strings`.

Releases are cut by tag:

```bash
git tag v1.0.1 && git push origin v1.0.1
```

## Requirements

macOS 13 Ventura or newer. Apple Silicon and Intel. The interface follows your system
language — English or Russian.

## Upgrading and uninstalling

**To upgrade, delete nothing.** Open the newer `.pkg` — the installer stops the running
copy and replaces the bundle in place. Your settings and the `sudo` rule survive.

**To remove it for good**, run [`uninstall.sh`](uninstall.sh) from a checkout, or the
equivalent by hand:

```bash
sudo pmset -a disablesleep 0          # first — see the warning below
sudo rm -rf /Applications/SleepSwitch.app
sudo rm -f /etc/sudoers.d/sleepswitch
sudo pkgutil --forget com.ganin.sleepswitch.app
defaults delete com.ganin.sleepswitch
```

> [!WARNING]
> Clear the sleep ban **before** deleting the app. It is a system setting that outlives the
> process, so dragging the app to the Trash while the mode is on leaves your Mac unable to
> sleep with no switch left to turn it off. Toggling the mode off in the menu first does the
> same thing.

Dropping the app in the Trash is enough only when the mode is off and you do not mind the
`sudo` rule and the receipt staying behind.

## License

[MIT](LICENSE)
