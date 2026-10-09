# Kế hoạch bộ theme Console — giao diện riêng cho App Management Center

Ngày: 2026-09-19. Trạng thái: thiết kế, chưa triển khai. Nhánh khảo sát: `feature/flowfin-module-rebrand`.

Thêm theme thứ ba mang bản sắc của một trung tâm điều hành release, giữ nguyên Default và Cyber. Phần lớn khối lượng công việc không nằm ở bảng màu mà ở việc gỡ bỏ giả định nhị phân đang khóa hệ theme lại ở đúng hai lựa chọn.

## 1. Mục tiêu và phạm vi

App Management Center là bảng điều khiển dày đặc thông tin, dùng liên tục nhiều giờ: pipeline release, đối chiếu phiên bản CH Play/App Store, Fastlane, API tool, giám sát, FlowFin, dọn hộp thư, Plan Studio. Hai theme hiện có đều không phục vụ đúng bối cảnh đó. Cyber là neon trên nền gần đen, thiên về trình diễn hơn là đọc lâu. Default là xám trắng phẳng, không có hệ màu ngữ nghĩa nên mọi trạng thái đều phải tự bịa màu tại chỗ.

Theme mới tên **Console** (phụ đề tiếng Việt "Điều hành"): nền graphite hơi ngả lam, một màu nhấn xanh thép, và một hệ màu ngữ nghĩa thật sự cho thành công / cảnh báo / lỗi / thông tin — vốn là thứ giao diện này dùng nhiều nhất.

Trong phạm vi: hệ token, ba phase refactor dọn đường, bảng màu Console, bộ chọn theme ba lựa chọn, test.

Ngoài phạm vi bản này: biến thể sáng của Console, đổi typography (giữ Segoe UI Variable + JetBrains Mono), và vẽ lại layout. Đây là lựa chọn phạm vi đề xuất để bản đầu gọn, không phải giới hạn kỹ thuật.

**Không đổi trải nghiệm người dùng cũ.** Khóa `theme_choice` trong SharedPreferences đã lưu thì giữ nguyên; chỉ máy cài mới mới vào thẳng Console.

## 2. Hiện trạng đã kiểm tra

| Thành phần | Hiện trạng | Hướng xử lý |
|---|---|---|
| `lib/app/theme/cyber_theme.dart` | 468 dòng. `AppThemeChoice` hai giá trị; `AppCyberTheme` là class static giữ hai bộ hằng số `_cyberX` / `_defaultX` chọn theo `_activeChoice` | Giữ nguyên API công khai, thay ruột bằng palette |
| `AppCyberTheme.isCyber` | Getter boolean, dùng 116 lượt: 46 trong chính file theme, **70 ở tầng view** | Đây là nút thắt — xem mục 3 |
| Tầng view | 38 file gọi `AppCyberTheme.*`, khoảng 810 lượt. Gọi thẳng biến static, không qua `Theme.of(context)` | Không sửa call site nhờ giữ nguyên tên getter |
| `lib/app/services/theme_service.dart` | GetxService, lưu SharedPreferences, gọi `Get.changeTheme`. Fallback về `cyber` | Chỉ đổi giá trị fallback |
| Màu ngữ nghĩa | Không tồn tại token nào. Hardcode rải rác: màu HTTP method, màu status code, ramp trạng thái Kanban, chip xanh/lá của panel phiên bản | Gom về `AppPalette` ở phase 2 |
| Bộ chọn theme | Một mục menu tự lật hai chiều trong `flow_panel.dart`; command palette Ctrl+K chưa có lệnh đổi theme | Chuyển thành submenu radio, bổ sung vào palette |
| `panelDecoration` / `gridShellDecoration` | Chỉ 5 và 2 nơi dùng; phần lớn panel tự dựng `BoxDecoration` tại chỗ | Chấp nhận, không gom trong bản này |
| Test | `mail_cleaner_widget_test.dart` lặp `AppThemeChoice.values`; `plan_studio_widget_test.dart` giả định nhị phân sáng/tối | Cái đầu cover miễn phí, cái sau phải sửa |

Phân bố 70 nhánh `isCyber` ở tầng view — 41 trong số đó nằm gọn ở hai file, nên khối lượng tập trung chứ không rải đều:

| File | Số nhánh |
|---|---|
| `lib/app/views/home_widgets/shared_widgets.dart` | 21 |
| `lib/app/views/home_widgets/ch_play_versions_panel.dart` | 20 |
| `lib/app/views/home_widgets/flow_panel.dart` | 8 |
| `lib/app/views/home_widgets/options_panel.dart` | 5 |
| `lib/app/views/home_widgets/release_workflow_dialog.dart` | 4 |
| `api_tool/api_tool_components.dart` | 3 |
| `project_panel.dart`, `api_tool_dialog.dart`, `api_monitor_dialog.dart` | 2 mỗi file |
| `log_panel.dart`, `command_palette.dart`, `api_tool/api_tool_omnibar.dart` | 1 mỗi file |

## 3. Vấn đề chặn: `isCyber` là công tắc nhị phân

Hệ theme hiện tại không phải hệ token mà là một cặp hằng số cộng một công tắc. Tầng view viết dày đặc dạng:

```dart
color: AppCyberTheme.isCyber
    ? AppCyberTheme.electricBlue.withValues(alpha: 0.16)
    : const Color(0xFFEFF8FF),
```

Thêm thẳng giá trị thứ ba vào enum sẽ khiến Console rơi hết vào nhánh `else`, tức **nhận toàn bộ style của theme sáng**: nền trắng trong `panelDecoration`, chip `0xFFEFF8FF` / `0xFFEFF8F0` / `0xFFBFD7F5`, viền `0xFF1570EF`. Trên nền graphite đó là chữ trắng trên chip trắng.

Nghiêm trọng hơn, một số nhánh không chọn **màu** mà chọn **cấu trúc widget**:

- `shared_widgets.dart:335` — `_Panel` trả về `Container` phẳng nếu không phải Cyber, bỏ luôn `BackdropFilter`.
- `shared_widgets.dart:411` — chỉ vẽ `_ScanlinePainter` và `_CornerBracketPainter` cho Cyber.
- `shared_widgets.dart:402` — `_PulseGlow` chỉ bật cho Cyber.

Console không cần scanline hay corner bracket, nhưng cần `BackdropFilter` để phân tầng bề mặt. Với công tắc nhị phân thì không diễn đạt được "có blur, không có scanline" — phải tách thành cờ năng lực riêng.

Kết luận: **không thể thêm theme thứ ba trước khi thay công tắc bằng hệ token.**

## 4. Kiến trúc đề xuất: `AppPalette`

Một class immutable `lib/app/theme/app_palette.dart` gom toàn bộ quyết định thị giác của một theme. Mỗi theme là một `const AppPalette(...)` trong `lib/app/theme/palettes/`.

Nhóm token:

| Nhóm | Token |
|---|---|
| Bề mặt | `base`, `panel`, `panelStrong`, `surfaceHighest`, `backdropGradient` |
| Đường nét | `line`, `lineStrong`, `focusRing` |
| Nhấn | `accent`, `accentSoft`, `accentBorder`, `accentAlt` |
| Ngữ nghĩa | `success` / `successSoft` / `successBorder`, `warning`, `danger`, `info` / `infoSoft` / `infoBorder`, `idle` |
| Chữ | `textPrimary`, `textMuted`, `textFaint` |
| Năng lực hiển thị | `hasGlow`, `hasScanlines`, `hasCornerBrackets`, `backdropBlurSigma`, `pulseOnActive`, `scrimAlpha` |

Nhóm ngữ nghĩa và nhóm năng lực là phần mới hoàn toàn. Nhóm còn lại chỉ là đổi tên những gì đã có.

`AppCyberTheme` **giữ nguyên tên lớp và toàn bộ getter công khai**, chỉ đổi thân hàm thành uỷ quyền:

```dart
static Color get electricBlue => _active.accent;   // thay cho: isCyber ? _cyberX : _defaultX
```

Nhờ vậy khoảng 810 call site ở tầng view không phải sửa dòng nào.

## 5. Bảng màu Console

| Token | Giá trị | Tương phản trên `base` |
|---|---|---|
| `base` | `#12151C` | — |
| `panel` | `#1A1F29` | — |
| `panelStrong` | `#212836` | — |
| `surfaceHighest` | `#262E3D` | — |
| `line` | `#2C3441` | — |
| `lineStrong` | `#3A4553` | — |
| `accent` | `#5B8DEF` | 5.7:1 |
| `success` | `#3DBE8B` | 7.9:1 |
| `warning` | `#E0A73B` | 8.6:1 |
| `danger` | `#E5556E` | 5.2:1 |
| `info` | `#6FA8FF` | 7.7:1 |
| `textPrimary` | `#E6EAF2` | 15.6:1 |
| `textMuted` | `#94A0B4` | 7.0:1 |
| `textFaint` | `#6B7688` | **4.0:1** |

Các biến thể `*Soft` dùng màu gốc ở alpha 0.14, `*Border` ở alpha 0.42.

`textFaint` **không đạt AA 4.5:1**. Chỉ dùng cho nhãn trang trí không mang thông tin bắt buộc — ví dụ gợi ý phím tắt trong command palette — không dùng cho nội dung người dùng cần đọc.

Năng lực hiển thị: `hasGlow: false`, `hasScanlines: false`, `hasCornerBrackets: false`, `pulseOnActive: false`, `backdropBlurSigma: 8`. Console phân tầng bằng lớp bề mặt chứ không bằng đổ bóng phát sáng; đây là khác biệt cốt lõi so với Cyber.

Bán kính bo góc giữ như hiện tại: panel 8, control 6.

## 6. Thứ tự thực hiện

Ba phase đầu **không đổi một pixel nào** của Default và Cyber. Đây là điều kiện để review từng phase độc lập và để golden test làm trọng tài.

### Phase 1 — Tách palette khỏi công tắc

Tạo `app_palette.dart`, `palettes/cyber.dart`, `palettes/default.dart`, chép nguyên xi giá trị từ `cyber_theme.dart:26-44`. Đổi ruột `AppCyberTheme` sang uỷ quyền. Chốt phase: toàn bộ test xanh, golden của mail cleaner không đổi byte.

### Phase 2 — Thay 70 nhánh `isCyber` bằng token

Phase nặng nhất và là phần thật sự mở khóa cho theme thứ ba.

Bổ sung nhóm ngữ nghĩa và nhóm năng lực vào `AppPalette`, điền cho Cyber và Default sao cho render **y hệt hiện tại**. Gom về đây các hằng số đang hardcode: màu HTTP method và màu status code trong `api_tool_components.dart`, ramp trạng thái trong `plan_studio/widgets/kanban_column.dart`, chip xanh/lá trong `ch_play_versions_panel.dart` và `shared_widgets.dart`.

Sửa theo thứ tự tập trung: `shared_widgets.dart` → `ch_play_versions_panel.dart` (41/70 nhánh) → `flow_panel.dart` → `options_panel.dart` → `release_workflow_dialog.dart` → nhóm api_tool → các file lẻ.

Kéo các alpha lặp đi lặp lại (`0.34/0.82`, `0.12/0.08`, `0.16/0.09`) vào token thay vì để rải rác tại chỗ gọi.

Kết phase: `isCyber` đánh `@Deprecated`, sau đó xóa.

### Phase 3 — Bảng màu Console

Thêm `AppThemeChoice.console`, nhãn "Console", icon `Icons.space_dashboard_outlined`, file `palettes/console.dart`.

Về tên: repo đã có command palette Ctrl+K trong `home_widgets/command_palette.dart`, nên đặt tên theme là "Command" sẽ gây nhầm mỗi lần trao đổi về code. Chọn "Console" vì lý do đó.

Đổi giá trị mặc định ở ba chỗ: `cyber_theme.dart:24` (`_activeChoice`), `cyber_theme.dart:70` (tham số mặc định của `themeData`), `theme_service.dart:35` (fallback của `_choiceFromKey`).

### Phase 4 — Bộ chọn theme ba lựa chọn

Mục menu hiện tại ở `flow_panel.dart:854-864` tự lật hai chiều nên không mở rộng được. Chuyển thành submenu radio; gộp `_AutomationMenuAction.themeDefault` và `themeCyber` thành một action mang tham số. Bổ sung lệnh đổi theme vào command palette Ctrl+K.

### Phase 5 — Đổi tên, tùy chọn

`AppCyberTheme` → `AppTheme`, `cyber_theme.dart` → `app_theme.dart`. Thuần cơ học, 38 file, một lần thay chuỗi. Để cuối cho khỏi nhiễu diff các phase trước.

## 7. Backlog triển khai dạng ticket

| Mã | Nội dung | Ưu tiên | Phụ thuộc | Tiêu chí chấp nhận |
|---|---|---|---|---|
| THM-001 | `AppPalette` và hai palette hiện có | P0 | — | API công khai `AppCyberTheme` không đổi; test xanh; golden không đổi byte |
| THM-002 | Bổ sung token ngữ nghĩa và cờ năng lực | P0 | 001 | Cyber/Default điền đủ, render không đổi |
| THM-003 | Gỡ `isCyber` khỏi `shared_widgets` và `ch_play_versions_panel` | P0 | 002 | 41 nhánh biến mất; golden không đổi |
| THM-004 | Gỡ `isCyber` khỏi 11 file còn lại, xóa getter | P0 | 003 | `grep isCyber lib/` không còn kết quả |
| THM-005 | Palette Console và giá trị mặc định | P0 | 004 | Mở app mới vào Console; user cũ giữ nguyên lựa chọn |
| THM-006 | Bộ chọn theme ba lựa chọn + lệnh Ctrl+K | P0 | 005 | Đổi qua lại ba theme không cần khởi động lại |
| THM-007 | Test palette và tương phản | P0 | 005 | Mọi `AppThemeChoice` đủ token; `textPrimary`/`textMuted` ≥ 4.5:1 |
| THM-008 | Sửa giả định nhị phân trong `plan_studio_widget_test` | P1 | 005 | Nhận thẳng `AppThemeChoice` thay vì `Brightness` |
| THM-009 | Đổi tên `AppCyberTheme` → `AppTheme` | P2 | 006 | Analyze sạch, test xanh |

Mốc A: 001–004 → hệ token xong, vẫn hai theme. Mốc B: 005–007 → Console dùng được. Mốc C: 008–009 → dọn nợ. Chưa ước lượng ngày công trước khi làm xong THM-003, vì phase 2 là ẩn số lớn nhất.

## 8. Kiểm chứng trước khi bàn giao

- Golden làm trọng tài cho phase 1–2: `mail_cleaner_widget_test.dart` render lại và so byte. Nếu ảnh đổi ở hai phase này thì refactor đã sai, không phải thiết kế đổi.
- `mail_cleaner_widget_test.dart` lặp `AppThemeChoice.values` nên Console được cover tự động và tự sinh `mail-cleaner-*-console.png`. Xem mắt cả ba theme sau THM-005.
- Test mới `test/theme_palette_test.dart`: mọi giá trị enum trả palette đủ token; tương phản `textPrimary` và `textMuted` trên `base` ≥ 4.5:1; không token nào của theme này vô tình trỏ sang hằng số của theme khác.
- `plan_studio_widget_test.dart:149-157` đang `brightness == dark ? cyber : defaultTheme` — sửa ở THM-008.
- `options_panel_layout_test.dart:2852` khởi tạo `ThemeService` thật, đọc SharedPreferences — kiểm tra fallback mới không làm lệch test này.
- Thử tay: đổi theme khi đang mở dialog (API Tool, FlowFin, Plan Studio) và khi release đang chạy, xem có widget nào giữ màu cũ.
- Analyze sạch và build Windows release. Kiểm tra build Android để palette mới không kéo theo lỗi import ở `mobile_control_view.dart`.

## 9. Rủi ro đã nhận diện

**210 lượt `withValues(alpha:)` nằm ngoài file theme.** Các alpha này được chọn bằng mắt trên nền gần đen `#0B0E14` của Cyber. Nền graphite `#12151C` sáng hơn nên cùng alpha sẽ cho overlay nhạt hơn dự kiến. Phase 2 phải kéo các alpha lặp lại vào token, phần còn lại chấp nhận lệch nhẹ và chỉnh sau khi xem ảnh thật.

**Theme là biến static toàn cục**, không đi qua `Theme.of(context)`. `Get.changeTheme` vẽ lại cây widget, nhưng widget nào cache màu trong `initState` hoặc trong hằng số `const` sẽ giữ màu cũ tới lần rebuild sau. Không có cách phát hiện tự động; phải thử tay như mục 8.

**Phase 2 không có lưới an toàn cho file không nằm trong golden test.** `ch_play_versions_panel.dart` (20 nhánh) không có widget test. Cần xem mắt panel phiên bản ở cả ba theme trước khi đóng THM-003.

**Cờ năng lực dễ bị hiểu sai thành cờ "là Cyber".** Nếu phase 2 chỉ đổi `isCyber` thành `hasGlow` một cách máy móc thì không giải quyết được gì — mỗi nhánh phải hỏi "nhánh này thật sự phụ thuộc vào điều gì" rồi mới chọn cờ. Đây là lý do phase 2 không tự động hóa được bằng thay chuỗi.

## 10. Câu chưa trả lời

- Console có cần biến thể sáng không? Hiện Default đang gánh vai trò theme sáng, nhưng nó không cùng ngôn ngữ thiết kế với Console. Nếu sau này muốn bộ sáng + tối đồng nhất thì Default nên bị thay chứ không nên tồn tại song song.
- Ramp trạng thái Kanban trong `kanban_column.dart` hiện độc lập với theme. Có nên cho nó theo palette, hay giữ cố định để màu trạng thái không đổi khi đổi theme? Giữ cố định dễ nhận diện hơn nhưng sẽ chỏi trên nền graphite.
- Có giữ Cyber lâu dài không? Nếu Console thành mặc định và không ai dùng Cyber thì toàn bộ `_ScanlinePainter`, `_CornerBracketPainter`, `_PulseGlow` là code chết nên xóa.
