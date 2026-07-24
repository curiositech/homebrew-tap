require "digest"

class PortDaddy < Formula
  desc "Authoritative port manager for multi-agent development"
  homepage "https://github.com/curiositech/port-daddy"
  version "3.27.0"
  license "MIT"
  revision 3

  on_macos do
    on_arm do
      url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/pd-darwin-arm64.tar.gz"
      sha256 "484bb19a83c474ebfeeb8d5ee4b4189ac8cd89d3ece1363e506eb75c8d5adb3f"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/curiositech/port-daddy/releases/download/v#{version}/pd-linux-x64.tar.gz"
      sha256 "b7a570737f16737e288faf4ef402096a4ecbb047e6298c9c8dcdbb76029678fd"
    end
  end

  def install
    # SELF-VERIFYING TARBALL GATE (operator-directed, 2026-07-23): every
    # prior addition to what ships in the release tarball (pd-bosun #2381,
    # native/ onnxruntime dylib #3561, squid tentacles #3628) shipped in the
    # tarball but was silently NEVER installed into the keg — install() only
    # ever copies what someone remembered to list, so a new top-level
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
    known_tarball_manifest_sha256 =
      "756d34d98e494171139b1fea09874f01f78c0134a4d6faf6ef6afadfa178b366"
    actual_entries = Dir.glob("*")
    actual_hash = Digest::SHA256.hexdigest(actual_entries.join(","))
    if actual_hash != known_tarball_manifest_sha256
      odie <<~EOS
        Release tarball's top-level contents changed and Formula/port-daddy.rb's
        install() was never updated for it — failing closed instead of silently
        dropping a new file (see PR #3628 / #3561, which this gate exists to
        stop recurring).
          expected sha256: #{known_tarball_manifest_sha256}
          actual entries:  #{actual_entries.join(", ")}
          actual sha256:   #{actual_hash}
        Update install() to explicitly handle every entry above, then recompute
        the hash from a fresh tarball extraction.
      EOS
    end

    # pd-bosun (ADR-0036) is the daemon's out-of-process watchdog — the
    # 2026-07-14 daemon-down-hard-stop mandate requires it ship alongside the
    # daemon so a killed/wedged process gets restarted instead of silently
    # staying dead. release.yml packages it into the same tarball as pd/
    # port-daddy (PR #2381); installing it here is what actually makes it
    # part of the brew keg instead of being dropped on the floor.
    #
    # native/ (port-daddy #3561) ships onnxruntime-node's runtime library
    # (libonnxruntime.*.dylib / libonnxruntime.so.1) as a real sibling file
    # of the pd/port-daddy binaries. bun build --compile extracts the .node
    # N-API binding at runtime but drops this @rpath-linked sibling, so
    # lib/semantic-resolver.ts points DYLD_FALLBACK_LIBRARY_PATH /
    # LD_LIBRARY_PATH at dirname(process.execPath)/native/onnxruntime-node/
    # <platform>-<arch> before loading the embedding model — which resolves
    # to <keg>/bin/native here, hence bin.install (not prefix.install).
    #
    # pd-hook-prompt / pd-hook-pre-tool / pd-hook-post-tool (port-daddy
    # #3628, ADR-0091 Giant Squid Harness) are the UserPromptSubmit /
    # PreToolUse / PostToolUse tentacle scripts `pd squid hooks` wires into
    # Claude Code / Codex / Gemini config. release.yml has packaged them
    # into the tarball since #3628, but nothing ever installed them into the
    # keg until this fix — every install/upgrade since #3628 shipped left
    # `pd squid hooks` failing with "missing tentacle binary".
    bin.install "pd", "port-daddy", "pd-bosun", "native",
                "pd-hook-prompt", "pd-hook-pre-tool", "pd-hook-post-tool"

    # port-daddy-manifest.json is build metadata (binary sha256/size and
    # smoke-test results) consumed at release-verification time, not
    # something the daemon or CLI reads at runtime — intentionally not
    # installed into the keg.
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
    unless Kernel.system(bin/"port-daddy", "install-bosun")
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
