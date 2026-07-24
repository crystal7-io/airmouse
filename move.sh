#!/usr/bin/env bash
set -e

# Ensure we are inside the parent 'airmouse' directory containing 'air_mouse_app'
if [ ! -d "air_mouse_app" ]; then
    echo "Error: 'air_mouse_app' directory not found in the current folder!"
    exit 1
fi

echo "=== Moving files to root directory ==="
# Move all hidden and visible files from air_mouse_app to current directory
mv air_mouse_app/* .
mv air_mouse_app/.* . 2>/dev/null || true

echo "=== Cleaning up empty folder ==="
rmdir air_mouse_app

echo "=== Cleaning build artifacts ==="
flutter clean
flutter pub get

echo "=== Regenerating FFI Bindings ==="
export PATH="$HOME/.cargo/bin:$PATH"
flutter_rust_bridge_codegen generate

echo "=== Done! You can now run your app directly in this folder using: ==="
echo "flutter run"
