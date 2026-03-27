#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"

# Find dart — prefer FLUTTER_ROOT, then flutter on PATH
if [[ -n "${FLUTTER_ROOT:-}" ]]; then
  dart_bin="$FLUTTER_ROOT/bin/dart"
elif command -v flutter &>/dev/null; then
  dart_bin="$(dirname "$(command -v flutter)")/dart"
elif command -v dart &>/dev/null; then
  dart_bin="$(command -v dart)"
else
  echo "Error: dart not found. Install Flutter SDK and ensure 'flutter' is on your PATH." >&2
  exit 1
fi

if [[ ! -x "$dart_bin" ]]; then
  echo "Error: dart not executable at $dart_bin" >&2
  exit 1
fi

echo "Using dart: $dart_bin"
echo "Fetching dependencies..."
"$dart_bin" pub get

echo "Compiling binary..."
"$dart_bin" compile exe bin/server.dart -o bin/flutter_devtools_mcp_server

binary_path="$PWD/bin/flutter_devtools_mcp_server"
echo ""
echo "Done! Binary compiled to:"
echo "  $binary_path"
echo ""
echo "Add this to your editor's MCP config (mcp.json / settings.json):"
echo ""
echo '  {'
echo '    "servers": {'
echo '      "flutter": {'
echo "        \"command\": \"$binary_path\","
echo '        "args": []'
echo '      }'
echo '    }'
echo '  }'
echo ""
