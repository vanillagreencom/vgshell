#!/usr/bin/env bash
# Safe terminal fixture. The row supplies a private gate.
set -euo pipefail
if [[ $# -eq 0 ]]; then exit 0; fi
n=0
while [[ -e $1 && $n -lt 400 ]]; do sleep 0.05; n=$((n + 1)); done
