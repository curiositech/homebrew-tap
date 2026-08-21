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

puts "formula manifest tests PASS: .brew_home ignored; empty and unexpected entries fail closed"
