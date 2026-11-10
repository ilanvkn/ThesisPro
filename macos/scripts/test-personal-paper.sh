#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build
swiftc -parse-as-library Sources/ScholarForge/PersonalPaperDraft.swift Tests/ScholarForgeTests/PersonalPaperTests.swift -o .build/personal-paper-checks
.build/personal-paper-checks
