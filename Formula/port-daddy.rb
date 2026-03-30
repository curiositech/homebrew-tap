
class PortDaddy < Formula
  desc "Authoritative port manager for multi-agent development"
  homepage "https://github.com/curiositech/port-daddy"
  url "https://github.com/curiositech/port-daddy/archive/refs/tags/v3.8.1.tar.gz"
  sha256 "4138fb41536eadef97783896664aa4c4e416ca00c0f31a0e63814ded25979db9"
  license "MIT"

  depends_on "node"

  def install
    system "npm", "install", *std_npm_args
    bin.install_symlink Dir["#{libexec}/bin/*"]
  end

  def post_install
    ohai "Port Daddy v#{version} installed!"
    ohai "Start daemon: pd start"
    ohai "Quick start:  pd begin --identity myapp:api --purpose \"my first session\""
    ohai "Dashboard:    http://localhost:9876"
  end

  service do
    run [opt_bin/"port-daddy", "start"]
    keep_alive true
    working_dir var/"port-daddy"
    log_path var/"log/port-daddy.log"
    error_log_path var/"log/port-daddy.log"
  end

  test do
    assert_match "port-daddy", shell_output("#{bin}/port-daddy --version 2>&1")
  end
end
