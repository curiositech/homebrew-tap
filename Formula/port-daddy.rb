class PortDaddy < Formula
  desc "Authoritative port manager for multi-agent development"
  homepage "https://github.com/curiositech/port-daddy"
  version "3.12.0"
  license "FSL-1.1-MIT"

  # Per ADR-0028 (Signed Binary Distribution), Port Daddy ships as signed
  # Mach-O / ELF binaries built by `bun build --compile`. macOS binaries
  # are notarized via the Curiositech LLC Developer ID (P5H9P59X2M).
  # Linux binaries are stripped + GPG-signed tarballs from GitHub Releases.

  on_macos do
    on_arm do
      url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/port-daddy-darwin-arm64.tar.gz"
      sha256 "PLACEHOLDER_DARWIN_ARM64"
    end

    on_intel do
      url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/port-daddy-darwin-x64.tar.gz"
      sha256 "PLACEHOLDER_DARWIN_X64"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/port-daddy-linux-x64.tar.gz"
      sha256 "PLACEHOLDER_LINUX_X64"
    end

    on_arm do
      url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/port-daddy-linux-arm64.tar.gz"
      sha256 "PLACEHOLDER_LINUX_ARM64"
    end
  end

  def install
    # Three binaries shipped from the release tarball:
    #   pd                  user-facing CLI
    #   port-daddy-daemon   long-running HTTP/Unix-socket daemon
    #   pd-mcp              MCP server (stdio JSON-RPC)
    bin.install "pd"
    bin.install "port-daddy-daemon"
    bin.install "pd-mcp"

    # Content surface: skill bundle, examples, dashboard, schemas.
    # Per ADR-0028, the daemon serves these at /content/... and the
    # skill fanout resolver in `pd setup` reads from this location.
    # On Apple Silicon this becomes /opt/homebrew/share/port-daddy/...,
    # on Intel /usr/local/share/port-daddy/... — matches HOMEBREW_PREFIX.
    pkgshare.install "skills" if File.directory?("skills")
    pkgshare.install "examples" if File.directory?("examples")
    pkgshare.install "public" if File.directory?("public")
    pkgshare.install "schemas" if File.directory?("schemas")
  end

  def post_install
    ohai "Port Daddy v#{version} installed."
    ohai ""
    ohai "Start the daemon:"
    ohai "  brew services start port-daddy        # background, restarts on login"
    ohai "  pd start                              # foreground (alt)"
    ohai ""
    ohai "First-use:"
    ohai "  pd whoami     # identity + session"
    ohai "  pd status     # daemon health"
    ohai "  pd briefing   # what's happening across the fleet"
    ohai ""
    ohai "Skill fanout for AI coding agents:"
    ohai "  pd setup       # symlink the agent skill into ~/.claude, ~/.codex, etc."
  end

  service do
    # LaunchAgent (macOS) / systemd user unit (Linux) wrapper around the
    # daemon binary. brew services manages start/stop/restart.
    run [opt_bin/"port-daddy-daemon"]
    keep_alive true
    working_dir var/"port-daddy"
    log_path var/"log/port-daddy.log"
    error_log_path var/"log/port-daddy-error.log"

    # Skill + content live in the keg's share/ dir; the daemon reads them
    # via the content-root resolver (ADR-0028 step 3). Setting this env
    # var pins the embedded snapshot location for any case where the
    # binary's compiled-in default isn't sufficient (e.g. dev override).
    environment_variables PORT_DADDY_CONTENT_ROOT: opt_pkgshare.to_s
  end

  test do
    # Sanity: the CLI binary exists, prints its version, and the daemon
    # binary at least exposes --help without crashing. The full daemon
    # smoke (start + /health) requires bound ports and is run in CI,
    # not in `brew test`, to avoid colliding with a developer's already-
    # running daemon.
    assert_match version.to_s, shell_output("#{bin}/pd --version")
    assert_match(/usage|--help/i, shell_output("#{bin}/port-daddy-daemon --help 2>&1", 1))
    assert_predicate bin/"pd-mcp", :exist?
  end
end
