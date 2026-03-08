#!/bin/zsh

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
project_file="$project_root/SpotMenu.xcodeproj/project.pbxproj"

sparkle_private_key="${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY is required}"
github_repository="${GITHUB_REPOSITORY:-fightingentropy/SpotMenu}"
repo_name="${github_repository##*/}"
current_marketing="$(sed -n 's/.*MARKETING_VERSION = \([0-9.]*\);/\1/p' "$project_file" | head -1)"
tag_name="${TAG_NAME:-v${current_marketing}}"
release_version="${tag_name#v}"
sparkle_feed_url="${SPARKLE_FEED_URL:-https://raw.githubusercontent.com/${github_repository}/main/appcast.xml}"
sparkle_key_account="${SPARKLE_KEY_ACCOUNT:-${repo_name}-sparkle}"
build_root="${BUILD_ROOT:-$project_root/.codex-build/sparkle-release}"
derived_data_path="$build_root/deriveddata"
spm_path="$build_root/spm"
dist_path="$build_root/dist"
archive_name="SpotMenu-${release_version}.app.zip"
archive_output_path="$dist_path/$archive_name"

if [[ "$current_marketing" != "$release_version" ]]; then
    echo "Tag version $release_version does not match project MARKETING_VERSION $current_marketing" >&2
    exit 1
fi

if [[ -n "${APPLE_CODESIGN_IDENTITY:-}" ]]; then
    codesign_identity="${APPLE_CODESIGN_IDENTITY}"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q '"SpotMenu"'; then
    codesign_identity="SpotMenu"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q 'Developer ID Application'; then
    codesign_identity="Developer ID Application"
else
    echo "Could not find a code-signing identity. Set APPLE_CODESIGN_IDENTITY to continue." >&2
    exit 1
fi

rm -rf "$build_root"
mkdir -p "$dist_path"

xcodebuild \
    -project "$project_root/SpotMenu.xcodeproj" \
    -scheme SpotMenu \
    -resolvePackageDependencies \
    -clonedSourcePackagesDirPath "$spm_path" >/dev/null

sparkle_bin_dir="$(find "$spm_path" -path '*/artifacts/sparkle/Sparkle/bin' -type d | head -1)"
if [[ -z "$sparkle_bin_dir" ]]; then
    echo "Could not locate Sparkle binaries under $spm_path" >&2
    exit 1
fi

sparkle_private_key_file="$(mktemp "${TMPDIR:-/tmp}/spotmenu-sparkle-key.XXXXXX")"
cleanup() {
    rm -f "$sparkle_private_key_file"
}
trap cleanup EXIT
printf '%s' "$sparkle_private_key" > "$sparkle_private_key_file"

"$sparkle_bin_dir/generate_keys" --account "$sparkle_key_account" -f "$sparkle_private_key_file" >/dev/null
sparkle_public_key="$("$sparkle_bin_dir/generate_keys" --account "$sparkle_key_account" -p | tr -d '\n')"

if [[ -z "$sparkle_public_key" ]]; then
    echo "Could not derive Sparkle public key" >&2
    exit 1
fi

xcodebuild_args=(
    -project "$project_root/SpotMenu.xcodeproj"
    -scheme SpotMenu
    -configuration Release
    -derivedDataPath "$derived_data_path"
    -clonedSourcePackagesDirPath "$spm_path"
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$codesign_identity"
    SPARKLE_FEED_URL="$sparkle_feed_url"
    SPARKLE_PUBLIC_ED_KEY="$sparkle_public_key"
    build
)

if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
    xcodebuild_args+=(DEVELOPMENT_TEAM="$APPLE_TEAM_ID")
fi

if [[ -n "${KEYCHAIN_PATH:-}" ]]; then
    xcodebuild_args+=(OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_PATH")
fi

xcodebuild "${xcodebuild_args[@]}"

app_path="$derived_data_path/Build/Products/Release/SpotMenu.app"
if [[ ! -d "$app_path" ]]; then
    echo "Expected built app at $app_path" >&2
    exit 1
fi

rm -f "$archive_output_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_output_path"

"$sparkle_bin_dir/generate_appcast" \
    --ed-key-file "$sparkle_private_key_file" \
    --download-url-prefix "https://github.com/${github_repository}/releases/download/${tag_name}/" \
    --link "https://github.com/${github_repository}" \
    "$dist_path"

cat <<EOF
ARCHIVE_PATH=$archive_output_path
APPCAST_PATH=$dist_path/appcast.xml
DIST_PATH=$dist_path
SPARKLE_PUBLIC_ED_KEY=$sparkle_public_key
EOF
