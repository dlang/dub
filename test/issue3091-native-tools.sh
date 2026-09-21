#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
export DUB_HOME="$work_dir/dub-home"
mkdir -p "$DUB_HOME" "$work_dir/project/source" "$work_dir/dscanner/source"

cat > "$work_dir/project/dub.json" <<'EOF'
{"name":"cross-project","targetType":"library"}
EOF
cat > "$work_dir/project/dub.settings.json" <<'EOF'
{"defaultArchitecture":"wasm32-unknown-unknown-wasm"}
EOF
echo 'module example;' > "$work_dir/project/source/example.d"

# A local tool avoids fetching dscanner and its dependencies from the registry.
cat > "$work_dir/dscanner/dub.json" <<'EOF'
{"name":"dscanner","targetType":"executable"}
EOF
cat > "$work_dir/dscanner/source/app.d" <<'EOF'
import std.file : write;
void main() { write("lint-ran", "native tool executed"); }
EOF

"$DUB" add-local "$work_dir/dscanner"
# Package setup also resolves its target before lint builds the tool. Override
# that target so DMD (which cannot target wasm) can reach makeAppSettings. The
# project's default remains wasm and must not leak into the tool settings.
native_arch=$(uname -m)
case "$native_arch" in
    arm64) native_arch=aarch64 ;;
    i?86) native_arch=x86 ;;
esac
(cd "$work_dir/project" && "$DUB" lint --arch="$native_arch" --skip-registry=all)
test "$(cat "$work_dir/project/lint-ran")" = "native tool executed"
