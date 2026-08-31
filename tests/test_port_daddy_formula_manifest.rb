require "digest"
require "formula"

require_relative "../Formula/port-daddy"

EXPECTED_MANIFEST_SHA256 =
  "512cabbb14330d6acdb037c1b02b71dc5b897ab9752bdb801f37ad76f0e958f2"
RELEASE_ENTRIES = %w[agents bin hooks native pd port-daddy port-daddy-manifest.json skills].freeze

def assert(condition, message)
  raise message unless condition
end

def manifest_hash(entries)
  Digest::SHA256.hexdigest(entries.join(","))
end

entries = PortDaddy.release_manifest_entries(RELEASE_ENTRIES + [".brew_home"])
assert(PortDaddy.version.to_s == "3.30.5", "formula did not target the published daemon release")
assert(PortDaddy.revision.nil?, "upstream version promotion retained the old Homebrew revision")
assert(
  PortDaddy.service_keg_prefix(cellar: HOMEBREW_CELLAR).to_s.end_with?("/port-daddy/3.30.5"),
  "version promotion did not render the unrevisioned Homebrew keg path",
)
assert(entries == RELEASE_ENTRIES.sort, ".brew_home changed the release entry set")
assert(
  manifest_hash(entries) == EXPECTED_MANIFEST_SHA256,
  ".brew_home changed the release manifest hash",
)
assert(!entries.include?(".brew_home"), ".brew_home remained release-owned")

entries = PortDaddy.release_manifest_entries([])
assert(entries.empty?, "empty staging did not normalize to an empty entry set")
assert(
  manifest_hash(entries) != EXPECTED_MANIFEST_SHA256,
  "empty staging unexpectedly matched the release manifest",
)

unexpected_entries = %w[.DS_Store .git .npmrc]
entries = PortDaddy.release_manifest_entries(
  RELEASE_ENTRIES + unexpected_entries + [".brew_home"],
)
unexpected_entries.each do |entry|
  assert(entries.include?(entry), "#{entry} was incorrectly treated as synthetic")
end
assert(
  manifest_hash(entries) != EXPECTED_MANIFEST_SHA256,
  "unexpected hidden entries did not fail the release manifest",
)

formula_source = File.read(File.expand_path("../Formula/port-daddy.rb", __dir__))
assert(
  !formula_source.include?(%q{"install-freshness"}),
  "post_install invokes the removed install-freshness command",
)

darwin_environment = PortDaddy.service_environment(
  prefix:   "/opt/homebrew/Cellar/port-daddy/3.30.5",
  platform: :darwin_arm64,
  home:     "/Users/port-daddy-test",
)
assert(
  darwin_environment[:PORT_DADDY_RESOURCE_DIR] ==
    "/opt/homebrew/Cellar/port-daddy/3.30.5/share/port-daddy",
  "macOS service did not publish the packaged resource root",
)
assert(
  darwin_environment[:DYLD_FALLBACK_LIBRARY_PATH] ==
    "/opt/homebrew/Cellar/port-daddy/3.30.5/bin/native/onnxruntime-node/darwin-arm64",
  "macOS service did not publish the packaged ONNX loader path",
)
assert(
  !darwin_environment.key?(:LD_LIBRARY_PATH),
  "macOS service published the Linux loader variable",
)

linux_environment = PortDaddy.service_environment(
  prefix:   "/home/linuxbrew/.linuxbrew/Cellar/port-daddy/3.30.5",
  platform: :linux_x64,
  home:     "/home/port-daddy-test",
)
assert(
  linux_environment[:LD_LIBRARY_PATH] ==
    "/home/linuxbrew/.linuxbrew/Cellar/port-daddy/3.30.5/bin/native/onnxruntime-node/linux-x64",
  "Linux service did not publish the packaged ONNX loader path",
)
assert(
  !linux_environment.key?(:DYLD_FALLBACK_LIBRARY_PATH),
  "Linux service published the macOS loader variable",
)
assert(
  darwin_environment.values_at(
    :PORT_DADDY_NO_FLEET,
    :PORT_DADDY_PLANE,
    :BUN_JSC_useConcurrentGC,
    :BUN_JSC_useConcurrentJIT,
  ) == %w[1 prod 0 0],
  "semantic launch variables regressed the existing safe-mode contract",
)
assert(
  darwin_environment[:PORT_DADDY_DB] ==
    "/Users/port-daddy-test/.port-daddy/port-registry.db",
  "macOS service DB is not pinned to the durable login-user path",
)
assert(
  linux_environment[:PORT_DADDY_DB] ==
    "/home/port-daddy-test/.port-daddy/port-registry.db",
  "Linux service DB is not pinned to the durable login-user path",
)

begin
  PortDaddy.service_environment(prefix: "/opt/port-daddy", platform: :windows_x64, home: "/home/test")
  raise "unsupported service platform was accepted"
rescue ArgumentError => e
  assert(e.message.include?("unsupported"), "unsupported platform error was not actionable")
end

begin
  PortDaddy.service_environment(prefix: "/opt/port-daddy", platform: :darwin_arm64, home: "relative/home")
  raise "relative service home was accepted"
rescue ArgumentError => e
  assert(e.message.include?("absolute"), "relative home error was not actionable")
end

formula = PortDaddy.new(
  "port-daddy",
  Pathname.new(File.expand_path("../Formula/port-daddy.rb", __dir__)),
  :stable,
)
rendered_environment = formula.service.to_hash.fetch(:environment_variables)
expected_keg = PortDaddy.service_keg_prefix(cellar: HOMEBREW_CELLAR)
assert(
  expected_keg == Pathname.new(HOMEBREW_CELLAR)/"port-daddy/3.30.5",
  "service keg helper did not resolve the exact current Cellar install root",
)
assert(
  rendered_environment[:PORT_DADDY_RESOURCE_DIR] == (expected_keg/"share/port-daddy").to_s,
  "rendered service resource root is not bound to the versioned keg",
)
assert(
  rendered_environment[:PORT_DADDY_DB] ==
    File.join(Etc.getpwuid(Process.euid).dir, ".port-daddy", "port-registry.db"),
  "rendered service DB is not bound to the login user's durable home",
)
assert(
  rendered_environment[:PORT_DADDY_PLANE] == "prod",
  "rendered service did not declare the production plane",
)
assert(
  rendered_environment[:DYLD_FALLBACK_LIBRARY_PATH] ==
    (expected_keg/"bin/native/onnxruntime-node/darwin-arm64").to_s,
  "rendered service loader path is not bound to the versioned keg",
)
assert(
  rendered_environment[:DYLD_FALLBACK_LIBRARY_PATH] !=
    (formula.opt_prefix/"bin/native/onnxruntime-node/darwin-arm64").to_s,
  "rendered service loader path regressed to the stable opt symlink",
)

puts "formula manifest tests PASS: release entries and semantic service environment fail closed"
