# proc-watchdog

A tiny macOS background check that tells you when something has been quietly cooking your CPU or eating your memory, and cleans up orphaned test workers that outlived their runner.

It exists because a hung `vitest` worker sat at 100% CPU for 7 hours before anyone noticed.

- **CPU hogs:** notifies once when a process stays above 80% CPU for 20 minutes.
- **Memory hogs:** notifies once when a process uses more than 3 GB.
- **Orphaned workers:** kills (or reports) vitest/jest workers whose parent run has exited.

One bash script, no dependencies, no daemon. launchd runs a check every 5 minutes; each check takes ~10 ms and ~3 MB, then exits.

## Install

```sh
git clone https://github.com/funinkina/proc-watchdog
cd proc-watchdog
./proc-watchdog install
```

This copies the script to `~/.local/bin/proc-watchdog`, writes a config to `~/.config/proc-watchdog/config`, and registers a launchd agent that starts at login.

Notifications are sent via AppleScript, so macOS lists them under **Script Editor**. If you see none, enable Script Editor in System Settings → Notifications.

## Commands

| Command | |
| --- | --- |
| `proc-watchdog install` | Install or update, and (re)start the background check |
| `proc-watchdog status` | Is it running, plus the last 10 alerts |
| `proc-watchdog run` | Run one check now |
| `proc-watchdog config` | Print the config path |
| `proc-watchdog uninstall` | Stop and remove; keeps your config |

## Config

`~/.config/proc-watchdog/config` is a shell file. Changes apply on the next check; run `proc-watchdog install` again if you change `INTERVAL_SECONDS`.

| Key | Default | |
| --- | --- | --- |
| `INTERVAL_SECONDS` | `300` | How often to check |
| `CPU_PERCENT` | `80` | CPU threshold; 100 = one full core |
| `CPU_MINUTES` | `20` | How long a process must stay above `CPU_PERCENT` |
| `MEM_GB` | `3` | Resident memory threshold |
| `IGNORE` | `""` | Extended regex on the command line; matches never alert |
| `ORPHAN_PATTERN` | `vitest/dist/workers/\|jest-worker/build/workers/` | Extended regex for workers to treat as orphans when their parent is gone |
| `ORPHAN_ACTION` | `kill` | `kill`, `notify` or `off` |
| `NOTIFY` | `true` | `false` writes to the log only |

Example: also reap orphaned TypeScript servers, and never alert on Xcode builds.

```sh
ORPHAN_PATTERN="vitest/dist/workers/|jest-worker/build/workers/|tsserver\.js"
IGNORE="Xcode\.app|xcodebuild"
```

## How it works

Each check snapshots `ps`, then:

- An orphan is a process with PPID 1 whose command line matches `ORPHAN_PATTERN`. `kill` sends SIGTERM, then SIGKILL if it's still alive 2 seconds later.
- A process is a CPU hog when every check for `CPU_MINUTES` saw it at or above `CPU_PERCENT`. One check below the threshold resets its streak.
- Each process alerts once per kind. A process is identified by PID plus command line, so a recycled PID alerts again.
- If more than two intervals pass between checks (the Mac slept), CPU streaks restart, so sleeping doesn't count as hot time.

Alerts are logged to `~/Library/Caches/proc-watchdog/log` with the full command line.

## Limits

- macOS only (launchd, AppleScript notifications).
- `%CPU` is the value `ps` reports, a short decaying average. A process that spikes in bursts between checks can go unnoticed.
- Only orphans matching `ORPHAN_PATTERN` are touched. Many legitimate apps also have PPID 1, so there's no generic "kill all orphans" mode.

## Development

```sh
./test.sh
```

Runs every behavior against real processes (a `yes` CPU hog and a fake orphan) in a throwaway config and state directory, with notifications off.

## License

MIT
