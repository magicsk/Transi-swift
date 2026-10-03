#!/bin/bash
set -euo pipefail

transi_root="$(cd "$(dirname "$0")/.." && pwd)"
transi_test_cache="$(mktemp -d "${TMPDIR:-/tmp}/transi-changelog-check.XXXXXX")"
trap 'rm -r -- "$transi_test_cache"' EXIT

# Exercise the production release-notes parser without loading iOS services.
{
    printf '%s\n' 'import Foundation'
    awk '/^struct Changelog:/,/^}/' "$transi_root/Transi/ChangelogView.swift"
    sed -n '/^\/\/ Swift regression checks/,/^SWIFT$/ { /^SWIFT$/!p; }' "$0"
} | xcrun swift -module-cache-path "$transi_test_cache" -
exit

: <<'SWIFT'
// Swift regression checks
let release = Changelog(version: "0.9.9", markdown: """
## Features
- core models and database
- offline support and UI

## Bugfixes
- timezone bug and `arrival_time` column

## Empty

""")
assert(release.categories.map(\.title) == ["Features", "Bugfixes"], "Headings without items must be dropped")
assert(release.categories[0].items == ["Core models and database", "Offline support and UI"],
       "Bullet markers are stripped and the first letter is capitalized")
assert(release.categories[1].items == ["Timezone bug and `arrival_time` column"], "Inline markdown is kept for rendering")
assert(release.categories.map(\.icon) == ["sparkles", "ladybug"], "Known GitHub release headings get matching icons")

assert(Changelog(version: "1.0", markdown: "Plain note\r\n### Other Changes\r\n- misc").categories.map(\.icon) == ["ellipsis.circle"],
       "Text before the first heading is dropped, CRLF splits lines and unknown headings get a neutral icon")

assert(Changelog(version: "1.0", markdown: "\n## Features\n\n").categories.isEmpty, "Empty notes produce nothing to show")
print("PASS: changelog headings, bullets, icons and empty notes")
SWIFT
