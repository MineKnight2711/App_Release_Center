#!/bin/bash
# Builds AMC and installs it straight onto this Mac, the way the Windows
# installer does, without packaging a DMG:
#
#   installer/macos/install_local.sh [--skip-build] [--no-launch]
#
# The app goes to /Applications (or ~/Applications when /Applications is not
# writable; AMC_INSTALL_DIR overrides both). Every running AMC, a debug run from
# build/ included, is asked to quit, then stopped. The previous version comes
# back if anything fails before the new one is in place.
set -euo pipefail

app_name='App Management Center'
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$project_root"

skip_build=false
launch=true
for argument in "$@"; do
  case "$argument" in
    --skip-build) skip_build=true ;;
    --no-launch) launch=false ;;
    *) echo "Unknown option: $argument" >&2; exit 2 ;;
  esac
done

if [[ "$skip_build" == false ]]; then
  flutter build macos --release
fi

app_path="$project_root/build/macos/Build/Products/Release/$app_name.app"
if [[ ! -d "$app_path" ]]; then
  echo "macOS release is missing. Run flutter build macos --release first." >&2
  exit 1
fi
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Contents/Info.plist")

install_dir="${AMC_INSTALL_DIR:-}"
if [[ -z "$install_dir" ]]; then
  if [[ -w /Applications ]]; then
    install_dir=/Applications
  else
    install_dir="$HOME/Applications"
  fi
fi
mkdir -p "$install_dir"
installed_app="$install_dir/$app_name.app"

# Staged next to the destination so the swap below is a rename on one volume.
stage_dir=$(mktemp -d "$install_dir/.amc-install.XXXXXX")
moved_aside=false
replaced=false
cleanup() {
  if [[ "$moved_aside" == true && "$replaced" == false ]]; then
    rm -rf "$installed_app"
    mv "$stage_dir/previous.app" "$installed_app"
    echo "Install failed; the previous version was kept." >&2
  fi
  rm -rf "$stage_dir"
}
trap cleanup EXIT

staged_app="$stage_dir/$app_name.app"
ditto "$app_path" "$staged_app"
# Incremental Flutter builds may update App.framework without refreshing the
# outer app's resource seal, which the same ad-hoc signature as the DMG fixes.
codesign --force --sign - \
  --entitlements "$project_root/macos/Runner/Release.entitlements" "$staged_app"
codesign --verify --deep --strict "$staged_app"

# Every build counts, as on Windows: release builds allow one instance per
# bundle ID (MainFlutterWindow), so a debug run would keep the new copy closed.
running_pids() {
  pgrep -f "^/.*/$app_name\.app/Contents/MacOS/$app_name( |$)" || true
}
if [[ -n "$(running_pids)" ]]; then
  echo "Quitting running $app_name..."
  # A normal quit, sent to each process rather than the shared bundle ID, lets
  # AMC stop its remote agent and background host itself.
  for pid in $(running_pids); do
    osascript -l JavaScript -e "ObjC.import('AppKit');
      \$.NSRunningApplication.runningApplicationWithProcessIdentifier($pid).terminate" \
      >/dev/null 2>&1 || true
  done
  for _ in {1..20}; do
    [[ -z "$(running_pids)" ]] && break
    sleep 1
  done
  if [[ -n "$(running_pids)" ]]; then
    kill $(running_pids) 2>/dev/null || true
    sleep 3
    if [[ -n "$(running_pids)" ]]; then
      kill -9 $(running_pids) 2>/dev/null || true
      sleep 1
    fi
  fi
fi

if [[ -e "$installed_app" ]]; then
  mv "$installed_app" "$stage_dir/previous.app"
  moved_aside=true
fi
mv "$staged_app" "$installed_app"
replaced=true

# Launch Services otherwise keeps showing the old version and icon for a while.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$installed_app" >/dev/null 2>&1 || true

echo "Installed $app_name $version into $installed_app"
if [[ "$launch" == true ]]; then
  open "$installed_app"
fi
