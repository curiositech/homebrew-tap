class PortDaddy < Formula
  desc "Authoritative port manager for multi-agent development"
  homepage "https://github.com/curiositech/port-daddy"
  version "3.25.2"
  license "MIT"
  revision 2

  on_macos do
    on_arm do
      url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/pd-darwin-arm64.tar.gz"
      sha256 "d4bd836ed1cf7ae3b58bb47bb0dd9017e6dd7d0ef7d7eb42b06d62e1f93d08d8"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/pd-linux-x64.tar.gz"
      sha256 "b6adea7833aed01f20f6e9668a7f34e14706ef06f0bbee0c73c33192939eedad"
    end
  end

  def install
    # pd-bosun (ADR-0036) is the daemon's out-of-process watchdog — the
    # 2026-07-14 daemon-down-hard-stop mandate requires it ship alongside the
    # daemon so a killed/wedged process gets restarted instead of silently
    # staying dead. release.yml packages it into the same tarball as pd/
    # port-daddy (PR #2381); installing it here is what actually makes it
    # part of the brew keg instead of being dropped on the floor.
    bin.install "pd", "port-daddy", "pd-bosun"
  end

  def post_install
    ohai "Port Daddy v#{version} installed!"
    ohai "Start daemon:  brew services start port-daddy"
    ohai "Quick start:   pd begin --identity myapp:api --purpose \"my first session\""
    ohai "Dashboard:     http://localhost:9876"

    # Wire the Bosun watchdog against the brew-managed daemon label
    # (homebrew.mxcl.port-daddy). `install-bosun` (port-daddy >= 3.25.1) is
    # deliberately narrower than the full `port-daddy install`: it only ever
    # touches the Bosun + freshness launchd jobs, never the main daemon plist,
    # so it is safe to call here regardless of whether `brew services start
    # port-daddy` has run yet — the full `install` path would otherwise race
    # brew's own service for :9876 if called before that (post_install always
    # runs before the operator's first `brew services start`, and Homebrew
    # restarts an already-running service AFTER this hook, not before).
    # Best-effort: a failure here must never fail the whole brew install/
    # upgrade — the daemon itself is unaffected either way.
    Kernel.system(bin/"port-daddy", "install-bosun")
    unless $?&.success?
      opoo "Bosun watchdog install did not complete cleanly — daemon crashes " \
           "won't auto-restart until you run `port-daddy install-bosun` by hand."
    end
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
