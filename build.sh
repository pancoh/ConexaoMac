#!/bin/zsh
set -eu
project_dir=${0:A:h}
app_version=$(<"$project_dir/VERSION")
app_build=$(<"$project_dir/BUILD_NUMBER")
if [[ ! "$app_version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' || ! "$app_build" =~ '^[1-9][0-9]*$' ]]; then
    echo "VERSION ou BUILD_NUMBER inválido." >&2
    exit 1
fi
stage_dir=$(mktemp -d /private/tmp/conexao-build.XXXXXX)
trap 'rm -rf "$stage_dir"' EXIT
build_dir="$stage_dir/build"
app_dir="$stage_dir/Conexão.app"
mkdir -p "$build_dir/module-cache" "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
swiftc -swift-version 5 -O -module-cache-path "$build_dir/module-cache" -target arm64-apple-macosx13.0 "$project_dir"/Sources/*.swift -o "$app_dir/Contents/MacOS/ConexaoMac" -lsqlite3
cp "$project_dir/Assets/Icon.icns" "$app_dir/Contents/Resources/Icon.icns"
cat > "$app_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Conexão</string>
<key>CFBundleDisplayName</key><string>Conexão</string>
<key>CFBundleIdentifier</key><string>br.local.ConexaoMac</string>
<key>CFBundleExecutable</key><string>ConexaoMac</string>
<key>CFBundleIconFile</key><string>Icon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$app_version</string>
<key>CFBundleVersion</key><string>$app_build</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
ditto -c -k --norsrc --keepParent "$app_dir" "$project_dir/ConexaoMac.zip"
echo "Aplicativo compilado e empacotado: $project_dir/ConexaoMac.zip"
