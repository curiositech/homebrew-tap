cask "port-daddy-console" do
  version "3.20.0"
  sha256 "PLACEHOLDER_CONSOLE_ARM64"

  url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/PortDaddy-Console-macOS-arm64.zip"
  name "Port Daddy Console"
  desc "GPU-native operator console for the Port Daddy multi-agent coordinator"
  homepage "https://github.com/curiositech/port-daddy"

  # The .app is Developer-ID signed + notarized + stapled (ADR-0057), so no
  # quarantine override is needed — Gatekeeper trusts it on first launch.
  depends_on macos: ">= :monterey"
  depends_on arch: :arm64

  app "pd-console.app"

  zap trash: [
    "~/Library/Application Support/dev.portdaddy.console",
    "~/Library/Preferences/dev.portdaddy.console.plist",
    "~/Library/Saved Application State/dev.portdaddy.console.savedState",
  ]
end
