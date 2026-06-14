# wake-cron: macOS Power Management and Task Scheduling Utility

## Why wake-cron?

**launchd can schedule tasks. `pmset` can wake a sleeping Mac. Neither talks to the other — wake-cron bridges that gap.**

If your Mac is always on, you don't need this. Use launchd directly.

But if your Mac sleeps, you have a problem: launchd's `StartCalendarInterval` only fires if the system is already awake. Schedule a job for 06:15 and let the Mac sleep at midnight — the job never runs. `pmset` can wake the hardware on a schedule, but it knows nothing about your tasks. You'd have to configure both manually, keep them in sync, and repeat that for every job.

wake-cron does exactly that coordination in one command:

```bash
wake-cron 06:15 "/usr/bin/python3 /Users/joe/report.py"
```

It arms the hardware wake alarm 5 minutes early via `pmset`, deploys the job as a LaunchAgent, and keeps everything in sync — including when you have multiple jobs at different times.

**Use wake-cron if:**
- Your Mac sleeps overnight and you need tasks to run reliably in the morning
- You want a one-liner instead of hand-writing plist XML and wiring up `pmset` separately
- You need a job registry with `list`, `modify`, and `remove` without touching plist files

**Use launchd directly if:**
- Your Mac stays awake (server, always-on desktop)
- You need advanced launchd features (file watchers, network conditions, dependencies)

## Why launchd Instead of cron

Both the original and current versions use `pmset` to wake the hardware — that part is identical. The scheduler (cron vs. launchd) doesn't affect whether the Mac wakes up; `pmset` determines that.

The difference is what happens **after** the Mac wakes:

- **cron** runs on a fixed tick. If the system was still initializing when the scheduled minute passed, or if `pmset` failed to wake the Mac and the user opens the lid hours later, cron treats the scheduled time as missed and silently skips the job.
- **launchd** (`StartCalendarInterval`) detects that a job was missed and fires it immediately on the next wake — whenever that is. If `pmset` failed and the user opens the lid at noon, launchd still runs the 06:15 job.

| Behavior | cron | launchd |
| :--- | :--- | :--- |
| Fires while system is awake | ✅ | ✅ |
| Catches up missed job after any wake | ❌ | ✅ |
| Full PATH / user environment | ❌ | ✅ (login shell) |
| Timeout guardrail for hung scripts | ❌ | ✅ |
| Multiple independent job schedules | ✅ | ✅ |

In short: **`pmset` determines wake reliability. launchd buys you recovery when `pmset` itself fails.**

## Sleep Mode and Battery Limitations

wake-cron arms a hardware wake alarm via `pmset`. Whether that alarm fires depends on the Mac's sleep state:

| Sleep state | Triggered by | Wake alarm honoured? |
| :--- | :--- | :--- |
| Standard sleep (`hibernatemode 0`) | Lid close, idle timeout | ✅ Yes |
| Safe sleep (`hibernatemode 3`, default) | Lid close, idle timeout | ✅ Usually — unless battery critically low |
| Full hibernation (`hibernatemode 25`) | Manual or low battery fallback | ❌ No — system is fully powered down |
| Shut down | User action | ❌ No |

Check your current mode:
```bash
pmset -g | grep hibernatemode
```

**Recommendation:** Keep the Mac plugged in overnight for the most reliable results. On AC power, macOS stays in standard or safe sleep and consistently honours `pmset` wake alarms. On battery, if charge drops low enough for macOS to fall into full hibernation, the alarm will not fire — this is a hardware constraint no software can work around.

If the Mac was in full hibernation and the job was missed, launchd will still catch up and run it the next time the lid is opened.

## Technical Architecture

### 1. Hardware Wake Synchronization
`wake-cron` calculates a 5-minute pre-execution buffer and uses `pmset repeat wake` to arm a daily hardware wake event. When multiple jobs are scheduled, it always uses the **earliest** wake time across all jobs — avoiding the single-schedule limitation of `pmset repeat`.

### 2. LaunchAgent Injection
Each job is deployed as a `~/Library/LaunchAgents/com.wake-cron.<JOB_ID>.plist` file and loaded immediately via `launchctl`. Jobs run in a login shell (`/bin/bash -l`) so tools installed via Homebrew, rbenv, nvm, etc. are on PATH.

### 3. Timeout Guardrail
Every job is wrapped with `/usr/bin/timeout` (default: 300 seconds). If a script hangs due to a dropped network connection or unresponsive API, the process is force-killed after the timeout window, preventing indefinite machine wake and resource drain. Configurable per job via `--timeout`.

### 4. Job State Registry
A lightweight registry at `~/.wake-cron-jobs` tracks all scheduled jobs. This enables `list`, `modify`, and `remove` operations by JOB_ID, and ensures `pmset` is always synchronized to the earliest required wake time.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/joecayse/wake-cron/main/install.sh | bash
```

## Syntax

```
wake-cron [HH:MM] "[command]" [--timeout SECS]   Schedule (or update) a daily job
wake-cron list                                    List all active jobs
wake-cron modify <JOB_ID> [HH:MM]                Update an existing job's time
wake-cron remove <JOB_ID>                         Remove a job and clean up pmset
wake-cron -help | --help                          Show help and exit
```

### Flags

| Flag | Default | Description |
| :--- | :--- | :--- |
| `--timeout SECS` | `300` | Max runtime before the job process is force-killed |

### Examples

```bash
# Schedule a Python script at 06:15 daily
wake-cron 06:15 "/usr/bin/python3 /Users/joe/report.py"

# Schedule with a custom 2-minute timeout
wake-cron 06:15 "/usr/bin/python3 /Users/joe/report.py" --timeout 120

# List all scheduled jobs (shows JOB_ID, time remaining, status)
wake-cron list

# Update an existing job's execution time
wake-cron modify a1b2c3d4 07:00

# Remove a job — cleans registry and syncs pmset
wake-cron remove a1b2c3d4
```

### Execution Logs

Each job writes stdout and stderr to:
- `/tmp/wake-cron-<JOB_ID>.log`
- `/tmp/wake-cron-<JOB_ID>.err`

## System Requirements & Security

Due to macOS security sandboxing, launchd requires **Full Disk Access** to run tasks that touch protected directories.

| Step | Action |
| :--- | :--- |
| 1 | Navigate to **System Settings > Privacy & Security > Full Disk Access** |
| 2 | Click **+** |
| 3 | Press **Cmd + Shift + G** and navigate to `/bin/bash` |
| 4 | Ensure the toggle is **ON** |

> **Note:** `pmset repeat` only supports one repeating power-on event system-wide. `wake-cron` manages this automatically by always setting `pmset` to the earliest scheduled wake time across all jobs.

## Summary
`wake-cron` provides deterministic daily task execution for macOS by coupling hardware wake events (`pmset`) with launchd LaunchAgents. Jobs missed during sleep are caught up immediately on wake. Hung scripts are automatically killed by a configurable timeout guardrail. The utility is maintained under the MIT License.
