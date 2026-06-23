class PortDaddy < Formula
  desc "Authoritative port manager for multi-agent development"
  homepage "https://github.com/curiositech/port-daddy"
  version "3.21.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/pd-darwin-arm64.tar.gz"
      sha256 "3c9a7f2e368d0adec0731be1b77f6f7eb239424eca1625e081cdacc80ef1c0f1"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/pd-linux-x64.tar.gz"
      sha256 "6045427f94f68fd187ecd7e3abfe8d84eff553ffd294cbcb5c5b4fb4d5288621"
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
    # Without these, the bun-compiled binary's __dirname resolves inside
    # /opt/homebrew/Cellar/port-daddy/<version>/bin and the DB lands inside
    # the version-pinned Cellar dir — the next `brew upgrade` deletes it.
    # Pin the DB and runtime home under var/ so they survive upgrades.
    environment_variables PORT_DADDY_DB:   var/"port-daddy/port-registry.db",
                          PORT_DADDY_HOME: var/"port-daddy"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/pd --version 2>&1")
  end
end
