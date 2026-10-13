#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$project_root"
if [[ "${1:-}" != "--skip-build" ]]; then
  flutter build macos --release
fi

app_path="$project_root/build/macos/Build/Products/Release/App Management Center.app"
if [[ ! -d "$app_path" ]]; then
  echo "macOS release is missing. Run flutter build macos --release first." >&2
  exit 1
fi
codesign --verify --deep --strict "$app_path"
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
ditto "$app_path" "$stage_dir/App Management Center.app"
ln -s /Applications "$stage_dir/Applications"
cat > "$stage_dir/Huong-dan-cai-dat.txt" <<'EOF'
CÀI ĐẶT APP MANAGEMENT CENTER

1. Kéo App Management Center.app vào thư mục Applications bên cạnh.
2. Mở Applications rồi chạy App Management Center.
3. Sau khi sao chép xong, eject ổ đĩa cài đặt.

Bản này dùng chữ ký ad-hoc, chưa được Apple notarize. Nếu macOS chặn mở
ứng dụng vì không xác minh được nhà phát triển, vào System Settings >
Privacy & Security > Open Anyway sau khi đã thử mở ứng dụng.
Chỉ cấp ngoại lệ nếu bạn tin cậy nguồn file. Hướng dẫn chính thức:
https://support.apple.com/en-us/102445

Máy nhận không cần Flutter để mở ứng dụng. Các tác vụ build dự án trong
AMC vẫn cần Flutter/Xcode và các công cụ tương ứng trên máy nhận.
EOF
dmg_path="$output_dir/AppManagementCenter_v${version}_${platform}.dmg"
hdiutil create -volname 'App Management Center' -srcfolder "$stage_dir" \
  -ov -format UDZO "$dmg_path"
hdiutil verify "$dmg_path"
shasum -a 256 "$dmg_path" > "$dmg_path.sha256"
echo "Installer created: $dmg_path"
