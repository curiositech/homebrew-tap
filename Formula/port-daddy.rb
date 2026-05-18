class PortDaddy < Formula
  desc "Authoritative port manager for multi-agent development"
  homepage "https://github.com/curiositech/port-daddy"
  version "3.8.2"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/pd-darwin-arm64.tar.gz"
      sha256 "PLACEHOLDER_DARWIN_ARM64"
    end

    on_intel do
      url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/pd-darwin-x64.tar.gz"
      sha256 "PLACEHOLDER_DARWIN_X64"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/pd-linux-x64.tar.gz"
      sha256 "PLACEHOLDER_LINUX_X64"
    end
  end

  def install
    bin.install "pd"
  end

  def post_install
    ohai "Port Daddy v#{version} installed!"
    ohai "Start daemon:  pd start"
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
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/pd --version 2>&1")
  end
end
