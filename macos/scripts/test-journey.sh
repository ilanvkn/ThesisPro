#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build
swiftc -parse-as-library Sources/ScholarForge/Models.swift Sources/ScholarForge/AcademicJourney.swift Sources/ScholarForge/ThesisMap.swift Tests/ScholarForgeTests/JourneyTests.swift -o .build/journey-checks
.build/journey-checks
