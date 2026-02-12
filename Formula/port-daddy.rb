class PortDaddy < Formula
  desc "Authoritative port assignment service for multi-agent development environments"
  homepage "https://github.com/erichowens/port-daddy"
  url "https://github.com/erichowens/port-daddy/archive/refs/tags/v1.2.0.tar.gz"
  sha256 "92149f7a9f003e08beb33d42bac0d2c8f2f89bed8cf8b3276ba4f9acde978cba"
  license "MIT"

  depends_on "node"

  def install
    system "npm", "install", *std_npm_args
    bin.install_symlink Dir["#{libexec}/bin/*"]
  end

  def post_install
    ohai "Port Daddy installed!"
    ohai "To start the daemon: port-daddy install"
    ohai "To get a port: get-port my-project"
  end

  service do
    run [opt_bin/"port-daddy", "start"]
    keep_alive true
    working_dir var/"port-daddy"
    log_path var/"log/port-daddy.log"
    error_log_path var/"log/port-daddy.log"
  end

  test do
    # Test that CLI tools exist
    assert_match "Usage:", shell_output("#{bin}/get-port 2>&1", 1)
    assert_match "Usage:", shell_output("#{bin}/release-port 2>&1", 1)
  end
end
