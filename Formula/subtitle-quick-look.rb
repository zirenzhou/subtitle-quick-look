class SubtitleQuickLook < Formula
  desc "Quick Look previews, translation, and subtitle format conversion"
  homepage "https://github.com/zirenzhou/subtitle-quick-look"
  url "https://github.com/zirenzhou/subtitle-quick-look/releases/download/v1.2.0/subtitle-quick-look-1.2.0.tar.gz"
  sha256 "75269684c110ae4fc348b369f022731dae64035d40bac02aa087e29125f1f17f"
  license "MIT"

  depends_on xcode: ["16.0", :build]
  depends_on macos: :sequoia

  def install
    ENV["VERSION"] = version.to_s
    system "./scripts/build-release.sh"

    libexec.install "build/ManualRelease/Subtitle Quick Look.app"

    launch_agent_label = "io.github.zirenzhou.subtitle-quick-look.register"
    (share/"#{launch_agent_label}.plist").write <<~PLIST
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>Label</key>
        <string>#{launch_agent_label}</string>
        <key>ProgramArguments</key>
        <array>
          <string>#{libexec}/Subtitle Quick Look.app/Contents/MacOS/Subtitle Quick Look</string>
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

    (bin/"subtitle-quick-look").write <<~SH
      #!/bin/bash
      set -euo pipefail

      app_path="#{libexec}/Subtitle Quick Look.app"
      plugin_path="$app_path/Contents/PlugIns/Subtitle Quick Look Preview.appex"
      extension_id="io.github.zirenzhou.subtitle-quick-look.preview"
      launch_agent_label="io.github.zirenzhou.subtitle-quick-look.register"
      launch_agent_source="#{share}/io.github.zirenzhou.subtitle-quick-look.register.plist"
      launch_agent_path="$HOME/Library/LaunchAgents/$launch_agent_label.plist"
      launch_domain="gui/$(/usr/bin/id -u)"
      lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

      status() {
        if /usr/bin/pluginkit -m -A -D -v -i "$extension_id" | /usr/bin/grep -Fq "$plugin_path"; then
          echo "registered: $extension_id"
          echo "container: $app_path"
          if /bin/launchctl print "$launch_domain/$launch_agent_label" >/dev/null 2>&1; then
            echo "login registration: enabled"
          else
            echo "login registration: disabled"
          fi
        else
          echo "not registered: $extension_id"
          return 1
        fi
      }

      case "${1:-status}" in
        register)
          "$app_path/Contents/MacOS/Subtitle Quick Look" --register-all
          echo "registered: $extension_id"
          echo "container: $app_path"
          ;;
        ensure)
          "$app_path/Contents/MacOS/Subtitle Quick Look" --ensure-registration
          ;;
        install-autostart)
          /bin/mkdir -p "$HOME/Library/LaunchAgents"
          /bin/cp "$launch_agent_source" "$launch_agent_path"
          /bin/launchctl bootout "$launch_domain" "$launch_agent_path" 2>/dev/null || true
          /bin/launchctl bootstrap "$launch_domain" "$launch_agent_path"
          /bin/launchctl enable "$launch_domain/$launch_agent_label"
          "$0" register
          echo "login registration: enabled"
          ;;
        remove-autostart)
          /bin/launchctl bootout "$launch_domain" "$launch_agent_path" 2>/dev/null || true
          /bin/rm -f "$launch_agent_path"
          echo "login registration: disabled"
          ;;
        unregister)
          "$0" remove-autostart
          /usr/bin/pluginkit -r "$plugin_path" 2>/dev/null || true
          "$lsregister" -u "$app_path" 2>/dev/null || true
          /usr/bin/qlmanage -r >/dev/null 2>&1 || true
          echo "unregistered: $extension_id"
          ;;
        status)
          status
          ;;
        *)
          echo "Usage: subtitle-quick-look {register|ensure|install-autostart|remove-autostart|unregister|status}" >&2
          exit 64
          ;;
      esac
    SH
  end

  def post_install
    system bin/"subtitle-quick-look", "install-autostart"
  end

  def caveats
    <<~EOS
      The Quick Look extension is registered automatically.
      Finder Services are also refreshed automatically after install or upgrade.
      A lightweight login agent verifies registration after login and every 15 minutes.
      It exits immediately after each check and does not remain running in the background.
      If macOS does not show the extension or Services immediately, run:
        subtitle-quick-look register

      Before uninstalling, unregister it with:
        subtitle-quick-look unregister
    EOS
  end

  test do
    extension = libexec/"Subtitle Quick Look.app/Contents/PlugIns/Subtitle Quick Look Preview.appex"
    launch_agent = share/"io.github.zirenzhou.subtitle-quick-look.register.plist"
    assert_path_exists extension
    assert_path_exists launch_agent
    assert_match "io.github.zirenzhou.subtitle-quick-look.preview",
                 shell_output("/usr/bin/plutil -p '#{extension}/Contents/Info.plist'")
    launch_agent_contents = shell_output("/usr/bin/plutil -p '#{launch_agent}'")
    assert_match "--ensure-registration", launch_agent_contents
    assert_match "900", launch_agent_contents
  end
end
