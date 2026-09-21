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
(cd "$work_dir/project" && "$DUB" lint --skip-registry=all)
test "$(cat "$work_dir/project/lint-ran")" = "native tool executed"
