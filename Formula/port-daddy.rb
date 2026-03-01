class PortDaddy < Formula
  desc "Authoritative port assignment service for multi-agent development environments"
  homepage "https://github.com/erichowens/port-daddy"
  url "https://github.com/erichowens/port-daddy/archive/refs/tags/v3.3.0.tar.gz"
  sha256 "09b6f02c28651ebb5a27931c2f3cf3b235add929be1952866ccb22f029be3a66"
  license "MIT"

  depends_on "node"

  def install
    system "npm", "install", *std_npm_args
    bin.install_symlink Dir["#{libexec}/bin/*"]
  end

  def post_install
    ohai "Port Daddy v#{version} installed!"
    ohai "Start daemon: port-daddy start"
    ohai "Claim a port: pd claim my-project"
    ohai "Dashboard: http://localhost:9876"
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
