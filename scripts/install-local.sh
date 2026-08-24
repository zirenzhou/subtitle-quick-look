#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_app="$project_root/build/ManualRelease/Subtitle Quick Look.app"
target_app="$HOME/Applications/Subtitle Quick Look.app"
agent_label="io.github.zirenzhou.subtitle-quick-look.register"
agent_path="$HOME/Library/LaunchAgents/$agent_label.plist"
launch_domain="gui/$(/usr/bin/id -u)"

if [[ ! -d "$source_app" ]]; then
  echo "Build not found. Run ./scripts/build-release.sh first." >&2
  exit 66
fi

/bin/mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
/usr/bin/ditto "$source_app" "$target_app"

/bin/launchctl bootout "$launch_domain/$agent_label" 2>/dev/null || true

/bin/cat > "$agent_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$agent_label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$target_app/Contents/MacOS/Subtitle Quick Look</string>
    <string>--ensure-registration</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>900</integer>
  <key>ThrottleInterval</key>
  <integer>60</integer>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$agent_path" >/dev/null
"$target_app/Contents/MacOS/Subtitle Quick Look" --register-all
/bin/launchctl bootstrap "$launch_domain" "$agent_path"
/bin/launchctl enable "$launch_domain/$agent_label"

echo "Installed: $target_app"
echo "Self-healing registration: enabled (login + every 15 minutes)"
