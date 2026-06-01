class PortDaddy < Formula
  desc "Authoritative port manager for multi-agent development"
  homepage "https://github.com/curiositech/port-daddy"
  version "3.16.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/pd-darwin-arm64.tar.gz"
      sha256 "c0f7767850f01534ff09fa2e6f068d335cc1f1e50956a1cf893c667d5ed9ed34"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/pd-linux-x64.tar.gz"
      sha256 "5456178db0464f9df4b339cae0a0b0da9c3545f35c1b5bf87e9c1431476455cb"
    end
  end

  def install
    bin.install "pd"
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
