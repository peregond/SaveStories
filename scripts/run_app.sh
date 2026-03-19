#!/bin/zsh

set -euo pipefail

export CLANG_MODULE_CACHE_PATH="$(pwd)/beta-build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$(pwd)/beta-build/swiftpm-module-cache"

swift run DimaSave
