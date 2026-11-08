#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025-2026 Kaptain contributors (Fred Cooke)
#
# Bats runner baked into test images. Expands globs inside the
# container shell and runs all .bats files from the mounted test directory.
set -euo pipefail

if [[ $# -gt 0 ]]; then
  exec bats "$@"
else
  exec bats /kd/test/*.bats
fi
