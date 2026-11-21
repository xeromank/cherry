#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_name=Cherry
product=MenuShelf
output_dir="$project_dir/dist"
signing_identity="${CHERRY_SIGNING_IDENTITY:-${MENU_SHELF_SIGNING_IDENTITY:-}}"

build_release_binary() {
    local build_args=(--package-path "$project_dir" --configuration release)
    if [[ $# -eq 2 ]]; then
        local sdk_path
        sdk_path="$(xcrun --sdk macosx --show-sdk-path)" || return
        build_args+=(--triple "$1" --scratch-path "$2" --sdk "$sdk_path")
    fi

    xcrun swift build "${build_args[@]}" --product "$product" >&2 || return
    local binary_dir
    binary_dir="$(xcrun swift build "${build_args[@]}" --show-bin-path)" || return
    printf '%s/%s\n' "$binary_dir" "$product"
}

stage_app_bundle() {
    local binary="$1" app="$2" identity="$3"
    shift 3

    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    install -m 644 "$project_dir/Resources/Info.plist" "$app/Contents/Info.plist"
    install -m 644 "$project_dir/Resources/Cherry.icns" "$app/Contents/Resources/Cherry.icns"
    install -m 644 "$project_dir/LICENSE" "$app/Contents/Resources/LICENSE"
    install -m 755 "$binary" "$app/Contents/MacOS/$product"
    plutil -lint "$app/Contents/Info.plist"
    codesign --force --sign "$identity" "$@" "$app"
    codesign --verify --strict --all-architectures "$app"
}

# build-dmg.sh uses the build and bundle helpers with its own staging directory.
if [[ ${BASH_SOURCE[0]} != "$0" ]]; then
    return
fi

if [[ $# -gt 1 || ( $# -eq 1 && $1 != --zip ) ]]; then
    echo "Usage: $0 [--zip]" >&2
    exit 2
fi

app_path="$output_dir/$app_name.app"
binary="$(build_release_binary)"

mkdir -p "$output_dir"
staging_dir="$(mktemp -d "$output_dir/.cherry.XXXXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
staged_app="$staging_dir/$app_name.app"

stage_app_bundle "$binary" "$staged_app" "${signing_identity:--}" --timestamp=none

rm -rf "$app_path"
mv "$staged_app" "$app_path"
echo "$app_path"

if [[ $# -eq 1 ]]; then
    archive_name="$app_name-macOS-$(uname -m).zip"
    ditto -c -k --keepParent "$app_path" "$staging_dir/$archive_name"
    mv -f "$staging_dir/$archive_name" "$output_dir/$archive_name"
    echo "$output_dir/$archive_name"
fi
