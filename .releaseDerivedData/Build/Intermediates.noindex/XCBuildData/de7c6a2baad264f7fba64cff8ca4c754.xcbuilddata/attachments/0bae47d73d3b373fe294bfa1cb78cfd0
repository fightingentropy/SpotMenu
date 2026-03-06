#!/bin/sh
# Keep Sparkle's build version aligned with the shipped appcast version.
build_version="${MARKETING_VERSION:-$CURRENT_PROJECT_VERSION}"

if [ -z "$build_version" ]; then
    echo "warning: Unable to determine build version"
    exit 0
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_version" "${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

echo "Build number set to: $build_version"

