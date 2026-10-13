#!/bin/zsh
set -eu
project_dir=${0:A:h}
build_dir=$(mktemp -d /private/tmp/conexao-tests.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT
mkdir -p "$build_dir/module-cache"
swiftc -swift-version 5 -O -module-cache-path "$build_dir/module-cache" "$project_dir/Sources/Core.swift" "$project_dir/Sources/Store.swift" "$project_dir/Tests/main.swift" -o "$build_dir/tests" -lsqlite3
test_dir=$(mktemp -d "$build_dir/test.XXXXXX")
"$build_dir/tests" "$test_dir"
