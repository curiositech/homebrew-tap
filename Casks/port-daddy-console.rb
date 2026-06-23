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

  # The release artifact is pd-console.app (port-daddy's check-version-drift.mjs
  # --deep reads it by that name). Install it under the PROD lane name so it never
  # collides with a locally-built pd-console-latest.app (main) or a
  # pd-console_dev-<name>.app (worktree) — see port-daddy AGENTS.md "build LANES".
  # The shipped icon is the prod look: blue frame + vX.Y.Z badge.
  app "pd-console.app", target: "pd-console-prod.app"

  zap trash: [
    "~/Applications/pd-console-prod.app",
    "~/Library/Application Support/dev.portdaddy.console",
    "~/Library/Preferences/dev.portdaddy.console.plist",
    "~/Library/Saved Application State/dev.portdaddy.console.savedState",
  ]
end
