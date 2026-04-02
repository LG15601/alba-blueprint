# Alba Army — Cron / LaunchD Schedule

## Overview

The army runs nightly from 23:00 to 05:30 (Europe/Paris).
Morning report compiled at 06:30, delivered at 07:00.

## Crontab Entries

```crontab
# Alba Army — Overnight Agent Dispatch
# Install: crontab -e (paste below)

# Start dispatcher loop at 23:00
0 23 * * * /Users/alba/AZW/alba-blueprint/scripts/army/army-dispatch.sh loop >> /Users/alba/.alba/army/logs/cron-dispatch.log 2>&1

# Heartbeat monitor every 15 min during army hours (23:00-05:30)
*/15 23 * * * /Users/alba/AZW/alba-blueprint/scripts/army/army-heartbeat.sh >> /Users/alba/.alba/army/logs/cron-heartbeat.log 2>&1
*/15 0-5 * * * /Users/alba/AZW/alba-blueprint/scripts/army/army-heartbeat.sh >> /Users/alba/.alba/army/logs/cron-heartbeat.log 2>&1

# Graceful shutdown at 05:30
30 5 * * * /Users/alba/AZW/alba-blueprint/scripts/army/army-shutdown.sh >> /Users/alba/.alba/army/logs/cron-shutdown.log 2>&1

# Compile morning report at 06:30
30 6 * * * /Users/alba/AZW/alba-blueprint/scripts/army/compile-report.sh >> /Users/alba/.alba/army/logs/cron-report.log 2>&1

# Deliver morning report at 07:00
0 7 * * * /Users/alba/AZW/alba-blueprint/scripts/army/deliver-morning.sh >> /Users/alba/.alba/army/logs/cron-deliver.log 2>&1
```

## LaunchD Plist Alternatives

For macOS, launchd plists are more reliable than cron. Place in `~/Library/LaunchAgents/`.

### com.alba.army-dispatch.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.alba.army-dispatch</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/alba/AZW/alba-blueprint/scripts/army/army-dispatch.sh</string>
        <string>loop</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>23</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/Users/alba/.alba/army/logs/launchd-dispatch.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/alba/.alba/army/logs/launchd-dispatch-err.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>/Users/alba</string>
    </dict>
</dict>
</plist>
```

### com.alba.army-heartbeat.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.alba.army-heartbeat</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/alba/AZW/alba-blueprint/scripts/army/army-heartbeat.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>900</integer>
    <key>StandardOutPath</key>
    <string>/Users/alba/.alba/army/logs/launchd-heartbeat.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/alba/.alba/army/logs/launchd-heartbeat-err.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>/Users/alba</string>
    </dict>
</dict>
</plist>
```

### com.alba.army-shutdown.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.alba.army-shutdown</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/alba/AZW/alba-blueprint/scripts/army/army-shutdown.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>5</integer>
        <key>Minute</key>
        <integer>30</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/Users/alba/.alba/army/logs/launchd-shutdown.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/alba/.alba/army/logs/launchd-shutdown-err.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>/Users/alba</string>
    </dict>
</dict>
</plist>
```

### com.alba.army-morning.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.alba.army-morning</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>/Users/alba/AZW/alba-blueprint/scripts/army/compile-report.sh &amp;&amp; sleep 5 &amp;&amp; /Users/alba/AZW/alba-blueprint/scripts/army/deliver-morning.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>7</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/Users/alba/.alba/army/logs/launchd-morning.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/alba/.alba/army/logs/launchd-morning-err.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>/Users/alba</string>
    </dict>
</dict>
</plist>
```

## Installation Commands

```bash
# Install launchd plists
# (Copy plists to ~/Library/LaunchAgents/ first, then:)
launchctl load ~/Library/LaunchAgents/com.alba.army-dispatch.plist
launchctl load ~/Library/LaunchAgents/com.alba.army-heartbeat.plist
launchctl load ~/Library/LaunchAgents/com.alba.army-shutdown.plist
launchctl load ~/Library/LaunchAgents/com.alba.army-morning.plist

# Verify
launchctl list | grep alba.army

# Uninstall
launchctl unload ~/Library/LaunchAgents/com.alba.army-*.plist
```

## Manual Testing

```bash
# Parse a todo list
echo "- Relancer le client Dupont par email
- Ecrire un article blog sur l'IA
- Urgent: corriger le bug API
- Faire une veille concurrentielle" | ./parse-todo.sh --stdin

# Check queue
ls -la ~/.alba/army/queue/

# Run single dispatch round
./army-dispatch.sh once

# Check status
./army-dispatch.sh status

# Run heartbeat manually
./army-heartbeat.sh

# Compile report for today
./compile-report.sh

# Full shutdown
./army-shutdown.sh
```
