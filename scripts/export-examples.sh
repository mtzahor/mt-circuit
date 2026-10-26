#!/bin/bash
# Exports the built-in example circuits as .mtcircuit documents (default: Examples/).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -O Sources/CircuitCore/*.swift scripts/export-examples/main.swift -o build/export-examples
build/export-examples "${1:-Examples}"
