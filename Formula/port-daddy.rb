require "digest"
require "etc"

class PortDaddy < Formula
  desc "Authoritative port manager for multi-agent development"
  homepage "https://github.com/curiositech/port-daddy"
  version "3.30.5"
  license "MIT"

  SYNTHETIC_HOMEBREW_ENTRIES = [".brew_home"].freeze

  def self.release_manifest_entries(staged_entries)
    (staged_entries - SYNTHETIC_HOMEBREW_ENTRIES).sort
  end

  # The compiled semantic runtime loads a packaged ONNX shared library lazily,
  # but dyld/the ELF loader must receive its search path when launchd/systemd
  # admits the daemon process. Keep this pure so tap CI can verify both shipped
  # platforms without booting a service.
  def self.service_environment(prefix:, platform:, home:)
    platform_arch, loader_variable = case platform
    when :darwin_arm64
      ["darwin-arm64", :DYLD_FALLBACK_LIBRARY_PATH]
    when :linux_x64
      ["linux-x64", :LD_LIBRARY_PATH]
    else
      raise ArgumentError, "unsupported Port Daddy service platform: #{platform}"
    end

    prefix = prefix.to_s
    home = Pathname.new(home.to_s)
    unless home.absolute?
      raise ArgumentError, "Port Daddy service home must be an absolute path"
    end

    {
      PORT_DADDY_NO_FLEET: "1",
      PORT_DADDY_DB: (home/".port-daddy/port-registry.db").to_s,
      PORT_DADDY_PLANE: "prod",
      PORT_DADDY_RESOURCE_DIR: File.join(prefix, "share", "port-daddy"),
      BUN_JSC_useConcurrentGC: "0",
      BUN_JSC_useConcurrentJIT: "0",
      loader_variable => File.join(
        prefix, "bin", "native", "onnxruntime-node", platform_arch
      ),
    }
  end

  # Return the versioned install root before the formula is installed. Service
  # metadata is rendered for both installed and uninstalled formulae, so this
  # cannot depend on resolving opt_prefix on disk.
  def self.service_keg_prefix(cellar: HOMEBREW_CELLAR)
    keg_version = (revision.nil? || revision.zero?) ? version.to_s : "#{version}_#{revision}"
    Pathname.new(cellar.to_s)/"port-daddy"/keg_version
  end

  on_macos do
    on_arm do
      url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/pd-darwin-arm64.tar.gz"
      sha256 "9c630f83a172b842b38b00d7eddf704a0b06acd69ac64f1326e05006a845162e"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/pd-linux-x64.tar.gz"
      sha256 "4075adcbe212dc8e9ad54ed757e610b0b0df167f27431c86d5ca968ebda3b60d"
    end
  end

  def install
    # SELF-VERIFYING TARBALL GATE (operator-directed, 2026-07-23): every
    # prior addition to what ships in the release tarball could land there but
    # never be installed into the keg — install() only copies what someone
    # remembered to list, so a new top-level
    # tarball entry can go unshipped for weeks with nothing failing loudly.
    # This hash pins the exact sorted, comma-joined list of top-level
    # tarball entries this Formula has been reviewed against. If
    # release.yml's tar command ever adds/removes/renames a top-level entry,
    # this stops matching and the build fails HERE, loudly, instead of
    # silently dropping a file on the floor.
    #
    # To fix a mismatch: read the printed actual entry list below, decide
    # how the new/changed entry should be installed, update install() for
    # it, then recompute the hash — e.g.
    #   ruby -rdigest -e 'puts Digest::SHA256.hexdigest(Dir.glob("*").sort.join(","))'
    # run from a fresh `tar -xzf <artifact>.tar.gz` extraction directory.
    legacy_tarball_manifest_sha256 =
      "756d34d98e494171139b1fea09874f01f78c0134a4d6faf6ef6afadfa178b366"
    single_supervisor_manifest_sha256 =
      "512cabbb14330d6acdb037c1b02b71dc5b897ab9752bdb801f37ad76f0e958f2"
    known_tarball_manifest_sha256 = if version >= Version.new("3.28.0")
      single_supervisor_manifest_sha256
    else
      legacy_tarball_manifest_sha256
    end
    # Homebrew creates .brew_home inside the formula staging directory before
    # install runs. It is build-environment state, not an archive entry, so it
    # must not participate in the release-owned manifest hash. Keep the ignore
    # list exact: every other unexpected entry still fails closed below.
    staged_entries = Dir.children(".")
    ignored_entries = staged_entries & SYNTHETIC_HOMEBREW_ENTRIES
    actual_entries = self.class.release_manifest_entries(staged_entries)
    actual_hash = Digest::SHA256.hexdigest(actual_entries.join(","))
    if actual_hash != known_tarball_manifest_sha256
      odie <<~EOS
        Release tarball's top-level contents changed and Formula/port-daddy.rb's
        install() was never updated for it — failing closed instead of silently
        dropping a new file.
          expected sha256: #{known_tarball_manifest_sha256}
          actual entries:  #{actual_entries.join(", ")}
          actual sha256:   #{actual_hash}
          ignored Homebrew build entries: #{ignored_entries.empty? ? "(none)" : ignored_entries.join(", ")}
        Update install() to explicitly handle every entry above, then recompute
        the hash from a fresh tarball extraction.
      EOS
    end

    # native/ (port-daddy #3561) ships onnxruntime-node's runtime library
    # (libonnxruntime.*.dylib / libonnxruntime.so.1) as a real sibling file
    # of the pd/port-daddy binaries. bun build --compile extracts the .node
    # N-API binding at runtime but drops this @rpath-linked sibling, so
    # lib/semantic-resolver.ts points DYLD_FALLBACK_LIBRARY_PATH /
    # LD_LIBRARY_PATH at dirname(process.execPath)/native/onnxruntime-node/
    # <platform>-<arch> before loading the embedding model — which resolves
    # to <keg>/bin/native here, hence bin.install (not prefix.install).
    #
    bin.install "pd", "port-daddy", "native"

    if version >= Version.new("3.28.0")
      # Keep one directory-preserving runtime layout from archive to keg. The
      # CLI resolves hooks, public skill content, and canonical Pilot sources
      # from pkgshare; none of these implementation assets belongs on PATH.
      pkgshare.install "bin", "hooks", "skills", "agents"
    else
      # Compatibility for the published 3.27 archive only. Its harness scripts
      # were top-level files and it still carried the retired watchdog.
      bin.install "pd-hook-prompt", "pd-hook-pre-tool", "pd-hook-post-tool",
                  "pd-bosun"
    end

    # port-daddy-manifest.json is build metadata (binary sha256/size and
    # smoke-test results) consumed at release-verification time, not
    # something the daemon or CLI reads at runtime — intentionally not
    # installed into the keg.
  end

  def post_install
    ohai "Port Daddy v#{version} installed!"
    ohai "Homebrew is the sole Port Daddy daemon supervisor."
    ohai "Open FleetBar for daemon health, restart, and the published dashboard endpoint."

    if version >= Version.new("3.28.0")
      # 3.27 and earlier installed a second watchdog that could SIGKILL the
      # Homebrew-owned daemon during a legitimate startup scan. Retire that job
      # only after the single-supervisor runtime is present in the same keg.
      if OS.mac?
        legacy_label = "gui/#{Process.uid}/com.portdaddy.bosun"
        Kernel.system("/bin/launchctl", "bootout", legacy_label,
                      out: File::NULL, err: File::NULL)
        legacy_plist = Pathname.new(Dir.home)/"Library/LaunchAgents/com.portdaddy.bosun.plist"
        legacy_plist.unlink if legacy_plist.exist?
      elsif OS.linux?
        Kernel.system("systemctl", "--user", "disable", "--now", "port-daddy-bosun.service",
                      out: File::NULL, err: File::NULL)
        legacy_unit = Pathname.new(Dir.home)/".config/systemd/user/port-daddy-bosun.service"
        legacy_unit.unlink if legacy_unit.exist?
        Kernel.system("systemctl", "--user", "daemon-reload",
                      out: File::NULL, err: File::NULL)
      end

    elsif !Kernel.system(bin/"port-daddy", "install-bosun")
      # The tap still advertises 3.27 until a signed 3.28 artifact exists. Do
      # not uninstall its only recovery pair before the replacement ships.
      opoo "The legacy Port Daddy recovery pair was not installed cleanly."
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
    # Authority must not depend on a release keg, launchd working directory,
    # shell HOME inheritance, or an ambient override. Pin the production plane
    # and the login user's machine-durable registry explicitly. This path
    # survives brew upgrades and cannot drift into the Cellar or a checkout.
    # Match install-daemon.ts safe-mode defaults for the Bun 1.2.21 JSC native
    # crash family seen under production-shaped daemon load. This trades some
    # throughput for removing concurrent GC/JIT from the always-on control-plane
    # process; set PORT_DADDY_JSC_SAFE_MODE=0 only for targeted local testing.
    service_platform = OS.mac? ? :darwin_arm64 : :linux_x64
    environment_variables(**PortDaddy.service_environment(
      # Homebrew normally delegates stable opt paths into service blocks. The
      # compiled semantic runtime's native admission instead needs the concrete
      # keg containing ONNX. The class helper remains renderable pre-install.
      prefix:   PortDaddy.service_keg_prefix,
      platform: service_platform,
      home:     Etc.getpwuid(Process.euid).dir,
    ))
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/pd --version 2>&1")
  end
end
