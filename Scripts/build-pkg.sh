#!/bin/bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/build-app.sh"

if [[ $# -gt 1 || ( $# -eq 1 && $1 != --developer-id ) ]]; then
    echo "Usage: $0 [--developer-id]" >&2
    exit 2
fi

app_identity=-
installer_identity="${CHERRY_INSTALLER_SIGNING_IDENTITY:-}"
app_signing_options=(--timestamp=none)
if [[ $# -eq 1 ]]; then
    app_identity="$signing_identity"
    require_signing_identity 'Developer ID Application' "$app_identity" CHERRY_SIGNING_IDENTITY
    require_signing_identity 'Developer ID Installer' "$installer_identity" CHERRY_INSTALLER_SIGNING_IDENTITY
    app_signing_options=(--options runtime --timestamp)
fi

info_plist="$project_dir/Resources/Info.plist"
version="$(plutil -extract CFBundleShortVersionString raw "$info_plist")"
minimum_os="$(plutil -extract LSMinimumSystemVersion raw "$info_plist")"
bundle_id="$(plutil -extract CFBundleIdentifier raw "$info_plist")"
package_id="$bundle_id.pkg"
package_name="$app_name-$version-macOS-universal.pkg"

mkdir -p "$output_dir"
staging_dir="$(mktemp -d "$output_dir/.cherry-pkg.XXXXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
payload="$staging_dir/payload"
staged_package="$staging_dir/$package_name"
universal_binary="$staging_dir/$product"
build_universal_binary "$universal_binary" "$minimum_os"
stage_app_bundle "$universal_binary" "$payload/$app_name.app" "$app_identity" "${app_signing_options[@]}"

components="$staging_dir/Components.plist"
pkgbuild --analyze --root "$payload" "$components"
plutil -replace 0.BundleIsRelocatable -bool NO "$components"
plutil -replace 0.BundleHasStrictIdentifier -bool YES "$components"
plutil -replace 0.BundleIsVersionChecked -bool YES "$components"
plutil -replace 0.BundleOverwriteAction -string upgrade "$components"
pkgbuild --root "$payload" --component-plist "$components" --install-location /Applications \
    --identifier "$package_id" --version "$version" "$staging_dir/Cherry-component.pkg"

distribution="$staging_dir/Distribution.xml"
cat > "$distribution" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>$app_name</title>
    <options customize="never" hostArchitectures="arm64,x86_64"/>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <volume-check>
        <allowed-os-versions><os-version min="$minimum_os"/></allowed-os-versions>
    </volume-check>
    <choices-outline><line choice="cherry"/></choices-outline>
    <choice id="cherry" title="$app_name" visible="false" start_selected="true">
        <pkg-ref id="$package_id"/>
    </choice>
    <pkg-ref id="$package_id" version="$version">Cherry-component.pkg</pkg-ref>
</installer-gui-script>
EOF

package_options=(--distribution "$distribution" --package-path "$staging_dir")
if [[ $# -eq 1 ]]; then
    package_options+=(--sign "$installer_identity" --timestamp)
fi
productbuild "${package_options[@]}" "$staged_package"
pkgutil --payload-files "$staged_package" >/dev/null
if [[ $# -eq 1 ]]; then
    pkgutil --check-signature "$staged_package"
fi

mv -f "$staged_package" "$output_dir/$package_name"
echo "$output_dir/$package_name"
