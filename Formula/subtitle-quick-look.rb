class SubtitleQuickLook < Formula
  desc "Quick Look previews and native translation for VTT, LRC, and SRT files"
  homepage "https://github.com/zirenzhou/subtitle-quick-look"
  url "https://github.com/zirenzhou/subtitle-quick-look/releases/download/v1.1.0/subtitle-quick-look-1.1.0.tar.gz"
  sha256 "90d995c017f172a46a3de49eae60bace11894a19327a706febfdc04d9e40963e"
  license "MIT"

  depends_on xcode: ["16.0", :build]
  depends_on macos: :sequoia

  def install
    ENV["VERSION"] = version.to_s
    system "./scripts/build-release.sh"

    libexec.install "build/ManualRelease/Subtitle Quick Look.app"

    (bin/"subtitle-quick-look").write <<~SH
      #!/bin/bash
      set -euo pipefail

      app_path="#{libexec}/Subtitle Quick Look.app"
      plugin_path="$app_path/Contents/PlugIns/Subtitle Quick Look Preview.appex"
      extension_id="io.github.zirenzhou.subtitle-quick-look.preview"
      lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

      status() {
        if /usr/bin/pluginkit -m -i "$extension_id" | /usr/bin/grep -q "$extension_id"; then
          echo "registered: $extension_id"
          echo "container: $app_path"
        else
          echo "not registered: $extension_id"
          return 1
        fi
      }

      case "${1:-status}" in
        register)
          "$lsregister" -f "$app_path"
          /usr/bin/pluginkit -a "$plugin_path"
          /usr/bin/qlmanage -r >/dev/null 2>&1 || true
          echo "registered: $extension_id"
          echo "container: $app_path"
          ;;
        unregister)
          /usr/bin/pluginkit -r "$plugin_path" 2>/dev/null || true
          "$lsregister" -u "$app_path" 2>/dev/null || true
          /usr/bin/qlmanage -r >/dev/null 2>&1 || true
          echo "unregistered: $extension_id"
          ;;
        status)
          status
          ;;
        *)
          echo "Usage: subtitle-quick-look {register|unregister|status}" >&2
          exit 64
          ;;
      esac
    SH
  end

  def post_install
    system bin/"subtitle-quick-look", "register"
  end

  def caveats
    <<~EOS
      The Quick Look extension is registered automatically.
      Before uninstalling, unregister it with:
        subtitle-quick-look unregister
    EOS
  end

  test do
    extension = libexec/"Subtitle Quick Look.app/Contents/PlugIns/Subtitle Quick Look Preview.appex"
    assert_path_exists extension
    assert_match "io.github.zirenzhou.subtitle-quick-look.preview",
                 shell_output("/usr/bin/plutil -p '#{extension}/Contents/Info.plist'")
  end
end
