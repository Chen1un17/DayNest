#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
swiftc -parse-as-library Sources/DayNest/Models.swift Sources/DayNest/Store.swift Tests/DayNestTests/DayNestTests.swift -o .build/checks/DayNestChecks
.build/checks/DayNestChecks
