#!/usr/bin/env bash
# Prepares the Android gradle export: SDK packages, debug keystore, editor settings, gradle build template.
# Run from the repository root; JDK 17 set up by actions/setup-java; godot on PATH.
set -euo pipefail
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"
SDKM="$(ls "$SDK"/cmdline-tools/*/bin/sdkmanager 2>/dev/null | head -1 || true)"
if [ -z "$SDKM" ]; then echo "::error::sdkmanager not found under $SDK"; exit 1; fi
yes | "$SDKM" --licenses >/dev/null || true
"$SDKM" "platforms;android-36" "build-tools;36.0.0" "cmdline-tools;latest" "ndk;28.1.13356709" >/dev/null
keytool -genkey -v -keystore "$HOME/debug.keystore" -alias androiddebugkey -storepass android -keypass android \
  -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null
mkdir -p "$HOME/.config/godot"
cat > "$HOME/.config/godot/editor_settings-4.7.tres" <<EOT
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$SDK"
export/android/java_sdk_path = "${JAVA_HOME}"
export/android/debug_keystore = "$HOME/debug.keystore"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
EOT
# gradle build template (what "Install Android Build Template" does in the editor)
tpl="$HOME/.local/share/godot/export_templates/4.7.2.stable/android_source.zip"
mkdir -p godot/android/build
unzip -q -o "$tpl" -d godot/android/build
echo "4.7.2.stable" > godot/android/.build_version
touch godot/android/build/.gdignore
echo "android setup done"
