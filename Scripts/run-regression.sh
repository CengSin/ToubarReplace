#!/bin/zsh
set -euo pipefail

cache_root=/private/tmp/ToubarReplaceRegressionCache
mkdir -p "$cache_root/clang-module-cache"
mkdir -p "$cache_root/swiftpm-module-cache"

export CLANG_MODULE_CACHE_PATH="$cache_root/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$cache_root/swiftpm-module-cache"

legacy_sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
if [[ -z "${SDKROOT:-}" && -d "$legacy_sdk" ]]; then
    export SDKROOT="$legacy_sdk"
fi

exec swift run --disable-sandbox ToubarReplace --smoke-test
