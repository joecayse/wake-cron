# wake-cron: Schedules a cron job and ensures your Mac wakes up to run it

## Introduction
`wake-cron` is a lightweight, command-line utility designed specifically for macOS environments. It addresses the common friction point between hardware energy management and task automation. On macOS, the system power controller (pmset) and the cron daemon function as independent systems; `wake-cron` bridges this gap to ensure hardware availability before automated tasks execute.

## Technical Architecture

The utility operates by synchronizing two distinct system-level processes:

### 1. Hardware Wake Synchronization
The tool calculates a 5-minute pre-execution buffer. It interfaces with the System Management Controller (SMC) via pmset to schedule a hardware wake event. This ensures:
- The system exits sleep/hibernation mode.
- Wireless/network interfaces initialize and re-establish connectivity.
- Background system services are active before the primary task execution.

### 2. Task Injection Logic
`wake-cron` automates crontab management, providing a cleaner alternative to manual configuration. It handles:
- Path Validation: Ensures executables are reachable.
- Entry Sanitization: Prevents duplicate entries in the local crontab.
- Atomic Scheduling: Aligns the hardware alarm and the cron job precisely.

## Deployment and Configuration

### Installation
Deploy the utility using the provided shell script:
curl -fsSL https://raw.githubusercontent.com/joecayse/wake-cron/main/install.sh | bash

### Syntax
wake-cron [HH:MM] "[executable_command]"

Operational Example:
wake-cron 06:15 "/usr/bin/python3 /Users/joecayse/example.py

## System Requirements & Security
Due to macOS security sandboxing, the cron engine requires explicit Full Disk Access.

**AC Power Dependency:** For reliable execution, wake-cron requires the system to be connected to AC power. macOS energy-management policies significantly throttle or suppress hardware wake events when operating on battery.
**Hardware Assertions:** macOS may prevent wake events based on thermal conditions or active assertions. Users can check for blocking states using pmset -g assertions.
**Future Roadmap:** Future versions may transition to launchd to provide more robust task scheduling and better integration with native macOS power management.

| Step | Action |
| :--- | :--- |
| 1 | Navigate to System Settings > Privacy & Security > Full Disk Access. |
| 2 | Select the + button. |
| 3 | Use Cmd + Shift + G to navigate to /usr/sbin/cron. |
| 4 | Ensure the service toggle is switched to ON. |

## Summary
`wake-cron` simplifies the automation lifecycle for macOS users requiring deterministic execution of background tasks. By coupling hardware wake events with standard cron scheduling, it minimizes execution failure due to power-state transitions. This utility is maintained under the MIT License and is designed for modular expansion to include advanced CLI flags in future releases.
