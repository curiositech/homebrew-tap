class PortDaddy < Formula
  desc "Authoritative port manager for multi-agent development"
  homepage "https://github.com/curiositech/port-daddy"
  version "3.25.1"
  license "MIT"
  revision 1

  on_macos do
    on_arm do
      url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/pd-darwin-arm64.tar.gz"
      sha256 "d4a605dd7ad3addb50dcb45d24b0a7811e7728664ac0355ae39e2b544a57d200"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/pd-linux-x64.tar.gz"
      sha256 "373b05daed6e0037f0471be2f61f21ea8ee08a9dd0f4c2e9e603c5a081fce9da"
    end
  end

  def install
    bin.install "pd", "port-daddy"
  end

  def post_install
    ohai "Port Daddy v#{version} installed!"
    ohai "Start daemon:  brew services start port-daddy"
    ohai "Quick start:   pd begin --identity myapp:api --purpose \"my first session\""
    ohai "Dashboard:     http://localhost:9876"
  end

  service do
    # `--foreground` runs the daemon in-process so `brew services` supervises
    # the daemon PID directly. Without it, `pd start` re-execs itself detached
    # and exits, leaving brew-services thinking the service died.
    run [opt_bin/"pd", "start", "--foreground"]
    keep_alive true
    working_dir var/"port-daddy"
    log_path var/"log/port-daddy.log"
    error_log_path var/"log/port-daddy.log"
    # v3.25.0 durable-home cutover (ADR-0090): the daemon defaults the
    # registry to ~/.port-daddy/port-registry.db — a machine-durable home that
    # survives brew upgrades AND is shared with the CLI/dev planes ("daemons
    # must not own different truths"). Do NOT pin PORT_DADDY_DB here anymore:
    # pinning it suppresses the daemon's boot-time legacy rescue
    # (migrateLegacyRegistry only fires on the durable-home default) and
    # strands the registry on a formula-owned path. The old var/ pin — the
    # pre-3.25.0 hardening against the Cellar wipe — is superseded by the
    # in-daemon durable-home default.
    # Match install-daemon.ts safe-mode defaults for the Bun 1.2.21 JSC native
    # crash family seen under production-shaped daemon load. This trades some
    # throughput for removing concurrent GC/JIT from the always-on control-plane
    # process; set PORT_DADDY_JSC_SAFE_MODE=0 only for targeted local testing.
    environment_variables PORT_DADDY_NO_FLEET:      "1",
                          BUN_JSC_useConcurrentGC:  "0",
                          BUN_JSC_useConcurrentJIT: "0"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/pd --version 2>&1")
  end
end
