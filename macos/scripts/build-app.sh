#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_name="ThesisPro"
bundle_dir="$project_dir/dist/$app_name.app"

cd "$project_dir"
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"

mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Resources"
cp "$bin_dir/ScholarForge" "$bundle_dir/Contents/MacOS/ScholarForge"
ditto "$bin_dir/ScholarForge_ScholarForge.bundle" "$bundle_dir/Contents/Resources/ScholarForge_ScholarForge.bundle"
cp "$project_dir/Support/Info.plist" "$bundle_dir/Contents/Info.plist"
cp "$project_dir/Sources/ScholarForge/Resources/seed-thesis.json" "$bundle_dir/Contents/Resources/seed-thesis.json"
if [[ -f "$project_dir/Support/ThesisPlus.icns" ]]; then
    cp "$project_dir/Support/ThesisPlus.icns" "$bundle_dir/Contents/Resources/ThesisPlus.icns"
fi
codesign --force --sign - --entitlements "$project_dir/Support/ScholarForge.entitlements" "$bundle_dir"
codesign --verify --strict --verbose=2 "$bundle_dir"

print "$bundle_dir"
