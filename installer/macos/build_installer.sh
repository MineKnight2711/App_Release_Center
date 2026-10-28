#!/bin/bash
# Builds the macOS DMG.
#
# Without signing settings the staged app gets a fresh ad-hoc signature. It runs
# on this Mac, but Gatekeeper blocks it on every other Mac ("Apple could not
# verify..."), and each user has to allow it by hand. To ship a DMG that opens
# normally, sign with a Developer ID and notarize:
#
#   AMC_MACOS_SIGN_IDENTITY  "Developer ID Application: Name (TEAMID)". Only the
#                            team's Account Holder can create this certificate.
#   AMC_NOTARY_PROFILE       a notarytool keychain profile, created once with
#                            xcrun notarytool store-credentials <name> ...
set -euo pipefail

project_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$project_root"
if [[ "${1:-}" != "--skip-build" ]]; then
  flutter build macos --release
fi

sign_identity="${AMC_MACOS_SIGN_IDENTITY:-}"
notary_profile="${AMC_NOTARY_PROFILE:-}"
if [[ -n "$notary_profile" && -z "$sign_identity" ]]; then
  echo "AMC_NOTARY_PROFILE needs AMC_MACOS_SIGN_IDENTITY: Apple only notarizes Developer ID signed apps." >&2
  exit 1
fi

app_path="$project_root/build/macos/Build/Products/Release/App Management Center.app"
if [[ ! -d "$app_path" ]]; then
  echo "macOS release is missing. Run flutter build macos --release first." >&2
  exit 1
fi
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Contents/Info.plist")
architectures=$(lipo -archs "$app_path/Contents/MacOS/App Management Center")
case "$architectures" in
  *x86_64*arm64*|*arm64*x86_64*) platform=macOS-universal ;;
  *arm64*) platform=macOS-arm64 ;;
  *x86_64*) platform=macOS-x64 ;;
  *) echo "Unsupported architectures: $architectures" >&2; exit 1 ;;
esac
output_dir="$project_root/build/installer"
mkdir -p "$output_dir"
stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/amc-dmg.XXXXXX")
trap 'rm -rf "$stage_dir"' EXIT
staged_app="$stage_dir/App Management Center.app"
ditto "$app_path" "$staged_app"

if [[ -n "$sign_identity" ]]; then
  # Inside out, with the hardened runtime and a secure timestamp: notarization
  # requires both. Re-signing also drops get-task-allow, which Xcode adds to
  # ad-hoc builds and notarization rejects.
  while IFS= read -r -d '' code; do
    codesign --force --timestamp --options runtime --sign "$sign_identity" "$code"
  done < <(find "$staged_app/Contents/Frameworks" -depth \
    \( -name '*.framework' -o -name '*.dylib' \) -print0)
  codesign --force --timestamp --options runtime \
    --entitlements "$project_root/macos/Runner/Release.entitlements" \
    --sign "$sign_identity" "$staged_app"
else
  # Incremental Flutter builds may update App.framework without refreshing
  # the outer app's resource seal. Keep a valid ad-hoc signature in the DMG.
  codesign --force --sign - \
    --entitlements "$project_root/macos/Runner/Release.entitlements" "$staged_app"
fi
codesign --verify --deep --strict "$staged_app"

ln -s /Applications "$stage_dir/Applications"
cp "$project_root/installer/swiftdesk-quickstart.txt" "$stage_dir/SwiftDesk-huong-dan.txt"
if [[ -n "$notary_profile" ]]; then
  cat > "$stage_dir/Huong-dan-cai-dat.txt" <<'EOF'
CÀI ĐẶT APP MANAGEMENT CENTER

1. Kéo App Management Center.app vào thư mục Applications bên cạnh.
2. Mở Applications rồi chạy App Management Center.
3. Sau khi sao chép xong, eject ổ đĩa cài đặt.

Bản này đã được ký Developer ID và Apple notarize, macOS mở bình thường.

Máy nhận không cần Flutter để mở ứng dụng. Các tác vụ build dự án trong
AMC vẫn cần Flutter/Xcode và các công cụ tương ứng trên máy nhận.
EOF
else
  cat > "$stage_dir/Huong-dan-cai-dat.txt" <<'EOF'
CÀI ĐẶT APP MANAGEMENT CENTER

1. Kéo App Management Center.app vào thư mục Applications bên cạnh.
2. Mở Applications rồi chạy App Management Center.
3. Sau khi sao chép xong, eject ổ đĩa cài đặt.

LẦN MỞ ĐẦU TIÊN
Bản này chưa được Apple notarize nên macOS sẽ báo "Apple could not verify
App Management Center is free of malware" và chỉ có nút Done / Move to Trash.
Đó là chặn của Gatekeeper, không phải ứng dụng hỏng. Chỉ làm tiếp nếu bạn
tin cậy nguồn file:

  1. Bấm Done (không bấm Move to Trash).
  2. Mở System Settings > Privacy & Security, cuộn xuống mục Security.
  3. Bấm "Open Anyway" cạnh dòng App Management Center, nhập mật khẩu máy.
  4. Bấm "Open Anyway" lần nữa. Từ lần sau ứng dụng mở bình thường.

Nút Open Anyway chỉ hiện khoảng một giờ sau lần mở bị chặn; nếu không thấy,
mở lại ứng dụng một lần rồi quay lại bước 2. Từ macOS 15, chuột phải > Open
không còn bỏ qua được bước này.

Nếu macOS báo ứng dụng "is damaged", chạy lệnh sau trong Terminal rồi mở lại
(lệnh chỉ gỡ cờ "tải từ Internet" của đúng ứng dụng này):

  xattr -dr com.apple.quarantine "/Applications/App Management Center.app"

Hướng dẫn chính thức: https://support.apple.com/en-us/102445

Máy nhận không cần Flutter để mở ứng dụng. Các tác vụ build dự án trong
AMC vẫn cần Flutter/Xcode và các công cụ tương ứng trên máy nhận.
EOF
fi

dmg_path="$output_dir/AppManagementCenter_v${version}_${platform}.dmg"
hdiutil create -volname 'App Management Center' -srcfolder "$stage_dir" \
  -ov -format UDZO "$dmg_path"
hdiutil verify "$dmg_path"

if [[ -n "$sign_identity" ]]; then
  codesign --force --timestamp --sign "$sign_identity" "$dmg_path"
fi
if [[ -n "$notary_profile" ]]; then
  # Notarizing the DMG covers the app inside it; stapling lets Gatekeeper
  # accept it offline.
  submission=$(xcrun notarytool submit "$dmg_path" \
    --keychain-profile "$notary_profile" --wait --output-format json) || true
  status=$(plutil -extract status raw -o - - <<<"$submission" 2>/dev/null) || true
  if [[ "$status" != Accepted ]]; then
    echo "Notarization was not accepted: $submission" >&2
    echo "Details: xcrun notarytool log <id> --keychain-profile $notary_profile" >&2
    exit 1
  fi
  xcrun stapler staple "$dmg_path"
  spctl --assess --type open --context context:primary-signature --verbose "$dmg_path"
else
  echo "Warning: this DMG is not notarized. Other Macs block the app until each user allows it in System Settings > Privacy & Security (see Huong-dan-cai-dat.txt in the DMG)." >&2
fi

(cd "$output_dir" && shasum -a 256 "$(basename "$dmg_path")" > "$(basename "$dmg_path").sha256")
echo "Installer created: $dmg_path"
