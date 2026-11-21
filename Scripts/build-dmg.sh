#!/bin/bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/build-app.sh"

if [[ $# -gt 1 || ( $# -eq 1 && $1 != --developer-id ) ]]; then
    echo "Usage: $0 [--developer-id]" >&2
    exit 2
fi

identity=-
signature_options=(--timestamp=none)
if [[ $# -eq 1 ]]; then
    identity="$signing_identity"
    if [[ -z "$identity" ]] || ! security find-identity -v -p codesigning | awk -v selected="$identity" '
        /"Developer ID Application:/ && (toupper($2) == toupper(selected) || index($0, "\"" selected "\"") > 0) { found = 1 }
        END { exit !found }
    '; then
        echo 'Set CHERRY_SIGNING_IDENTITY to the name or SHA-1 of an available Developer ID Application identity.' >&2
        exit 1
    fi
    signature_options=(--options runtime --timestamp)
fi

info_plist="$project_dir/Resources/Info.plist"
version="$(plutil -extract CFBundleShortVersionString raw "$info_plist")"
minimum_os="$(plutil -extract LSMinimumSystemVersion raw "$info_plist")"
dmg_name="$app_name-$version-macOS-universal.dmg"

mkdir -p "$output_dir"
staging_dir="$(mktemp -d "$output_dir/.cherry-dmg.XXXXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
payload="$staging_dir/payload"
staged_dmg="$staging_dir/$dmg_name"

arm_binary="$(build_release_binary "arm64-apple-macosx$minimum_os" "$project_dir/.build/dmg-arm64")"
intel_binary="$(build_release_binary "x86_64-apple-macosx$minimum_os" "$project_dir/.build/dmg-x86_64")"
universal_binary="$staging_dir/$product"
xcrun lipo -create "$arm_binary" "$intel_binary" -output "$universal_binary"
xcrun lipo "$universal_binary" -verify_arch arm64 x86_64

stage_app_bundle "$universal_binary" "$payload/$app_name.app" "$identity" "${signature_options[@]}"
ln -s /Applications "$payload/Applications"
hdiutil create -quiet -format UDZO -volname "$app_name" -srcfolder "$payload" "$staged_dmg"

if [[ $# -eq 1 ]]; then
    bundle_id="$(plutil -extract CFBundleIdentifier raw "$info_plist")"
    codesign --sign "$identity" --timestamp --identifier "$bundle_id.dmg" "$staged_dmg"
    codesign --verify --strict "$staged_dmg"
fi
hdiutil verify "$staged_dmg"

mv -f "$staged_dmg" "$output_dir/$dmg_name"
echo "$output_dir/$dmg_name"
