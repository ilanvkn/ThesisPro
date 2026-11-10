#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build
bin_dir="$(swift build --show-bin-path)"
swift Tests/ScholarForgeTests/ShowcaseResourceChecks.swift "$bin_dir/ScholarForge_ScholarForge.bundle"
