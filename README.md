# App Management Center

Desktop release automation console with an Android remote-control surface.

## Plan Studio

**Reminders:** open any Plan, Task, or Note → **Nhắc hẹn**. Choose a date/time,
a delay, or a repeating interval in minutes/hours/days, then **Lưu nhắc hẹn**.
A day means a fixed 24-hour interval. The editor previews the first occurrence;
saved schedules and board cards show the next reminder. **Đã xem** advances a
repeating schedule to its next future interval; snooze postpones the current
occurrence without shifting the cadence. Completing, archiving, or deleting the
item stops its reminders. Up to three active schedules per item are supported.
Use **Cài đặt nhắc hẹn** for tray/background operation and quiet hours. The app
must be running; reminders missed while asleep or fully exited are recovered on
return. This requires the newly built Windows executable, not an older installed
copy. Imported schedules are paused. Calendar weekday/timezone recurrence is
not yet included.


Open **Plan Studio · Công việc** in the Project panel or search for Plan Studio
in the command palette. Select a project folder, then create a Plan, Task, or
Note. The board has six status columns; drag tickets between columns or use a
card's status menu. Drop between cards to reorder. Filters disable reordering
within a column; the all-projects view is for browsing.

**Tạo hàng loạt** (the arrow next to **Tạo task**, the command palette, or
Shift+N) adds many tasks at once: one per line, each with the quick-add syntax
(`!p1`, `#nhãn`, `^mai 17h`). A pasted status report keeps its priorities:
a leading `🔴 Cao –`, `🟡 Trung bình –` or `Thấp:` sets P1/P2/P3 (`Khẩn cấp`
is P0, the word wins over the dot), and `⏳ Chờ phản hồi –` puts the task in
**Bị chặn** with that reason. List markers (including `➡️`), checkboxes and
Markdown headings are ignored. Pick the column and an optional parent plan,
whose deadline can fill lines that have none. The preview skips repeated lines
and flags titles already on the board. The batch is saved in one transaction,
up to 200 tasks.

Ticket details include priority, labels, checklist, notes, parent plan, history,
and archive/restore. Edits autosave after 700 ms of inactivity. Plan progress is
calculated from active child tasks. A plan cannot finish while a child is
unfinished; reopening a child reopens a completed plan.

The trash icon in ticket details permanently deletes a Plan, Task, or Note after
confirmation. Deleting a plan keeps its child tasks (including archived tasks)
and removes their parent/revision links. Deleting a task updates its parent's
history. A ticket's own notes, checklist and saved versions are deleted with it.

For AI planning, choose **Tạo plan bằng AI**, connect to an existing local Ollama
instance using the model refresh button, enter the requirement/context, answer
clarifying questions, and generate the plan. The model endpoint is
`http://127.0.0.1:11434`. Repository paths are context only; the model does not
automatically read code. Requests can be canceled, old content is versioned
before regeneration, and drafts retain their answers after reopening the app.
Use **Tạo task** in a plan's details to review and enter one task title per line.
Task extraction is manual in this version.

Data is local to this machine, independent of team accounts. SQLite is stored
under the platform application-support directory in `plan_studio/studio.sqlite`.
The overflow menu exports/imports JSON backups, imports Markdown plans, and
relinks a moved project directory without changing ticket identities. JSON
import adds missing IDs only; existing records are preserved. Project identity
conflicts abort the entire import. Keep the complete Windows release folder
together, including its native assets, when running the built executable.

Module tests:

```powershell
flutter test test/plan_studio_repository_test.dart test/plan_studio_ai_test.dart test/plan_studio_widget_test.dart
```

Set `STUDIO_SCREENSHOTS` to an output directory when running the widget test to
capture the board with sample data in both app themes on Windows. These are test
fixtures, not records inserted into the user's database.

## Kiểm tra AAB

Open **Kiểm tra AAB** from the command palette or the automation overflow menu,
then drop an `.aab` onto the page or pick one. The bundle is read in place —
nothing is extracted to disk or sent anywhere — and the report answers three
questions:

- **Build đúng không:** package vs the project's applicationId, versionCode vs
  pubspec and the CH Play version checked this session, the signing key (a
  release silently signed with the Android debug key fails), debuggable,
  Flutter AOT release, ABIs, 16 KB page alignment of 64-bit libraries, the Play
  targetSdk requirement, new permissions and size growth since the last check
  of the same package.
- **Đủ env không:** the bundled `.env` against the keys the project's code
  reads, its `.env.example` and the key names in its `.env`; values pointing at
  a dev machine; which Firebase project is compiled in versus the one the
  production flavor's `google-services.json` names; empty manifest meta-data;
  secrets shipped in assets.

- **Chạy được không:** pick a device under the report and press **Chạy thử**.
  AMC builds the APKs Play would serve that device (`bundletool build-apks
  --connected-device`), installs them, opens the launcher activity, watches
  the process for 10–60 seconds, and reads logcat for crashes, ANRs and
  uncaught Flutter errors with their stack. Screenshots at 3 seconds and at the
  end are kept, and a near-single-colour final screen is flagged. A switched-off
  AVD is started first. Emulators are preferred by default; on an emulator any
  installed copy is removed first for a clean install, while on a physical
  device AMC never uninstalls without asking. The APKs are re-signed with the
  project's upload key (or bundletool's debug key), not Play's app signing key,
  so features pinned to that SHA-1 may fail locally.

The bundle is matched to a project by package name, using CH Play entries and
recent project folders. **Contract env** adds required keys, strings that must
(or must not) appear in the compiled Dart code, and the expected Firebase
project. **Ghim chữ ký** accepts the current signing key, so a later bundle
signed with anything else fails. Env values are always shown masked. Reports
live under the app-support folder in `bundle_check/`, newest 20 kept.

**Tải bundletool** fetches `bundletool-all-1.18.3.jar` from Google's GitHub
release and checks its SHA-256; it enables `bundletool validate`, **Chạy thử**
and **Xuất APK universal**, which signs with the project's keystore when one is
configured and bundletool's debug key otherwise.

### Telegram bot

**Bot Telegram** on the checker page runs the same checks from a group chat,
using the Telegram bot configured under Options. Every `.aab` posted in an
allowed chat is remembered; `/aab` lists the newest as buttons, and pressing
one makes the bot say "I'm downloading and checking the aab" (editable), fetch
the file, check it, optionally run it on an emulator, and reply under the file
with the verdict and a screenshot. `/check` in reply to a file checks it
directly; `/status` shows what the bot is doing. The bot only sees files posted
after it joined, with privacy mode disabled in BotFather or as an admin.

AABs are larger than the 20 MB the cloud Bot API lets bots download, so the bot
is meant to run through a local `telegram-bot-api` server in `--local` mode.
Point AMC at `telegram-bot-api.exe` and enter the api_id / api_hash from
my.telegram.org; AMC starts the server on 127.0.0.1 when needed. **Chuyển bot
sang server local** logs the bot out of the cloud and into the local server;
from then on release notifications go through it too, and Telegram will not
take the bot back to the cloud for 10 minutes. Build the server on Windows with
Visual Studio 2022 following https://tdlib.github.io/telegram-bot-api/build.html.

Module tests:

```powershell
flutter test test/bundle_check_parsers_test.dart test/bundle_check_checks_test.dart test/bundle_check_service_test.dart test/bundle_check_device_test.dart test/bundle_check_widget_test.dart test/bundle_check_telegram_test.dart test/bundle_check_telegram_dialog_test.dart
```

Set `AAB_CHECK_FIXTURE` to a real `.aab` to run the whole pipeline on it, and
`BUNDLE_CHECK_SCREENSHOTS` to an output folder to capture the page in each
theme.

## Mail Cleaner

Open **Dọn hộp thư** from the automation overflow menu in the flow header, or
search for it in the command palette. The module clears a mailbox that has run
out of quota by deleting whole families of machine-generated mail at once.

Connect with one of the server presets (Email Pro GTEL, Gmail) or **Tùy chỉnh**
for any other IMAP host; the connection is always TLS. Gmail rejects account
passwords and needs a 16-character App Password. Host, port, address and folder
are remembered for next time. The password is *not* stored unless **Nhớ mật khẩu
trên máy này** is ticked, in which case it goes to Windows secure storage and is
forgotten the moment the option is switched off.

Scanning fetches only the UID, size and `Subject` header of every message, then
piles them into groups by bracketed label (`[GTEL-VOICE]`) or, failing that, the
first three words. Matching happens on this machine because Email Pro encodes
subjects and cannot search accented keywords; subjects are compared with accents
stripped, so `[YÊU CẦU MỞ]` and `[YEU CAU MO]` are the same rule. Groups are
sorted by total size, which is what actually frees quota.

Tick groups in the table and add subject patterns (starts with / contains /
regex) in the left panel; the two combine. **Giữ lại thư trả lời** is on by
default and spares `Re:` / `Fwd:` messages, which are usually real conversations.
The bottom bar always shows how many messages and how much space the current
selection would remove.

Deletion follows what the server supports:

- With `MOVE` and a `\Trash` folder (Gmail), messages move to Trash in one step
  and stay recoverable. Space is only freed once Trash is emptied.
- Without them (Email Pro), deletion is split in two. Step one sets `\Deleted`,
  which **Gỡ cờ** undoes. Step two expunges and cannot be undone, so it requires
  typing `XOA <số thư>` to confirm. When the server also lacks UIDPLUS, that
  expunge removes *every* flagged message in the folder, including any flagged
  before this session — the panel warns about this.

The IMAP session lives exactly as long as the page: leaving logs out, and leaving
while a scan or deletion is running asks first. Flagged messages keep their flags
either way.

`enough_mail` requires `xml <7`, so this app pins `xml: ^6.6.1`; the only other
`xml` consumer is the resource-catalog Excel service, which uses APIs present in
both majors.

Module tests:

```powershell
flutter test test/mail_cleaner_matching_test.dart test/mail_cleaner_controller_test.dart test/mail_cleaner_widget_test.dart
```

## QA Desk

Open **QA Desk · Kiểm thử** from **Công cụ dự án** in the project panel, the
automation overflow menu, or the command palette. It runs the automation suites
of several projects (Flutter, Node/Vite, Playwright) and turns failures into
tasks. It replaces the standalone Fiza QA Desk app.

**Chạy test** is one screen for one run:

- **Thêm nguồn…** offers the project open in AMC and the recent projects first,
  then any folder. Suites come from the project's `.fiza-qa/project.yaml`, or
  safe defaults are inferred when it has none. Only `flutter`, `dart`, `node`,
  `npm`, `npx`, `adb` and `appium` can run.
- Tick suites in the tree; ticking a source takes all of it. Each source's
  environment is chosen on its own row, and 🔑 shows whether the environment's
  secrets have been entered for this session.
- The **Thiết bị**, **Mạng** and **Appium** chips open the sheets that change
  them. The bar at the bottom says what blocks the run (no device, a hardware
  suite on an emulator, missing secrets, no Appium) with a button to fix each.
- Sources run in parallel, the suites of one source in order. Mobile suites
  queue on the app-wide device lock shared with **Kiểm tra AAB** and its
  Telegram bot, so two of them never drive the same emulator at once.
- When AMC is releasing the project under test, the run warns that both will
  use the project's `build/` folder.
- Closing the page does not stop the run. The chip at the right of the bottom
  progress bar follows it, and keeps the result until QA Desk is opened again.
  Quitting AMC stops the suites' process trees and Appium.

When a run ends, its card offers **Báo cáo issue**: one suggested task per
failed suite, with reproduction steps, command, environment, Git state and a
log excerpt, ready for **Copy task** or **Copy báo cáo**. The summary is read
from the log, not a diagnosis.

**Kịch bản** holds each source's test cases, linked to the suite that checks
them, and its environments: variables passed to the suite process, plus the
names of secrets whose values are asked for each session and never written to
disk. Both live in the project's `.fiza-qa/scenarios.json`.

**Kết quả** keeps every run: each suite's log and failure screenshot, a
comparison with the run before, trends, **Chạy lại suite lỗi**, and export to
HTML, JUnit XML (with the logs, for CI) or JSON.

**Mạng yếu** slows traffic through a local proxy (0,5 to 32 KB/s per
connection and direction, with added latency). Suites receive it as
`FIZA_QA_PROXY`, `HTTP_PROXY` and `HTTPS_PROXY`; only clients that use the
proxy are slowed. The sheet can also probe an API through it.

The palette also has **QA: chạy các suite đã chọn**, **QA: chạy lại suite lỗi
của lượt gần nhất** and **QA: báo cáo issue của lượt gần nhất**.

### Demo accounts and test cases QA Desk runs itself

A test case can be **QA Desk tự thao tác** instead of linked to a suite: a list
of steps (open the app, log in, tap, type, see, wait, scroll, back, screenshot,
sub-flow) that QA Desk runs with [Maestro](https://maestro.mobile.dev) on an
emulator, a phone or a browser, logged in with a demo account. The project
needs no test code: QA Desk writes each test case's steps to
`.fiza-qa/flows/<id>.yaml`, readable and runnable without it.

1. **Tài khoản demo** (title bar) → **Tải Maestro** downloads Maestro 2.11.0
   from GitHub, checks its SHA-256 and unpacks it under the app-support folder
   (`qa_desk_tools/maestro`); PATH is left alone. Maestro needs Java 17+,
   which Android Studio already has.
2. Open the vault. Signed in to a team, accounts are shared with it and
   encrypted on the machine with the team's passphrase (Argon2id + AES-GCM);
   the amc-api Worker only holds ciphertext. An Admin creates the vault and adds,
   edits or reveals accounts; each member types the passphrase once per
   machine. Without a team, accounts stay in this machine's secure storage,
   and **Chép từ kho trên máy này** later copies them into the team's.
3. Declare the app in the project's `.fiza-qa/project.yaml`, with a login
   flow that types `${MAESTRO_QA_USERNAME}` and `${MAESTRO_QA_PASSWORD}`:

   ```yaml
   apps:
     - id: shop
       name: Shop
       platform: android          # or web, with url instead of appId
       login: flows/login.yaml
       cleanup: flows/cleanup.yaml   # optional, after writing test cases
       productionGuard: [Xoá, Thanh toán]
       environments:
         staging:
           appId: vn.example.shop
           build: build/app/outputs/flutter-apk/app-staging.apk  # optional
         production:
           appId: vn.example.shop
           production: true
   ```

   A project may declare apps and no suites. When an environment has a
   `build`, QA Desk installs it (an AAB through bundletool) unless that build
   is already on the device; without one it uses the installed app.
4. Add accounts by app, environment and role (for example *Chủ shop*), then
   **Thử đăng nhập** runs the login flow alone on the selected device.
5. In **Kịch bản**, create a test case, choose **QA Desk tự thao tác**, the app
   and the role, and add steps; **Xem flow Maestro sẽ ghi ra** shows the YAML.
   Labels match the text on screen exactly; tick **Tìm theo id** for an
   accessibility id (`Semantics(identifier: …)` in Flutter).

Automated test cases are ticked in the **Chạy test** tree under their source,
next to its suites. The **Môi trường app** chip picks the environment for the
whole run (staging first) and **Tài khoản demo** shows whether Maestro and the
vault are ready. Each run borrows an account of the role for the run, so two
people never log the same account in at once, and waits up to five minutes
when every account of the role is taken. Account values reach Maestro only as
environment variables and are masked as `••••` in the log, the report,
`commands.json` and every other text file the run leaves.

On **Kết quả**, **Các bước** shows each step Maestro ran, the one that failed
and its screenshot. A failure inside the login flow marks the account as
*Đăng nhập lỗi* for the team and skips it for the rest of the run.

Production is guarded three ways: a test case that writes data never runs
there, an account on a production environment is always read-only, and a
flow that taps a `productionGuard` label is refused. Running there asks for
confirmation. QA Desk cannot see everything an app does on a tap, so the
production account must also lack write permission in the backend.

The vault's tables and permissions live in the amc-api Worker
(`cloudflare/amc-api/src/qaVault.ts`, migration `0002_qa_vault.sql`): members
read the vault and record login results, only Admins change it, and a lease is
taken atomically in the caller's own name against server time. They are tested
with `npm test` in `cloudflare/amc-api`.

A mobile suite in a project manifest:

```yaml
- id: android-launch-smoke
  name: Android Launch Smoke
  executable: flutter
  arguments: [run, -d, "{deviceId}", --debug, --no-resident]
  requiresDevice: true
  captureScreenshotOnFailure: true
```

`requiresPhysicalDevice` is for hardware-only flows such as NFC, and
`requiresAppium` starts the managed Appium server on port 4723. A failure
screenshot is only taken for a suite that ran on the device.

Data lives in `qa_desk/` under the app-support folder: `sources.json`,
`qa_desk.db` and `artifacts/`. The first time QA Desk opens, the standalone
app's data (`%APPDATA%\vn.fizahub.qa\Fiza QA Desk`) is copied in, never moved,
and the log paths in its history are rewritten. The standalone app keeps
writing to its own folder, so stop using it after the import.

Check manifests and catalogs without opening the app:

```powershell
dart run tool/qa_validate_sources.dart ..\fizahub_app ..\fizahub_miniapp
dart run tool/qa_validate_catalogs.dart ..\fizahub_app ..\fizahub_miniapp
```

Module tests:

```powershell
flutter test (Get-ChildItem test\qa_desk_*_test.dart)
```

Set `QA_DESK_SCREENSHOTS` to an output folder to capture every section and
sheet in each theme.

## Remote Control Flow

The relay runs on Cloudflare Workers at
`https://amc-relay.huynhphuocdat2.workers.dev`, backed by the `amc-relay` D1
database. See `serverless/notifications/worker/README.md` for deploying and
verifying it.

1. Deploy the relay (`cd serverless/notifications && npm run deploy`) and set
   `DESKTOP_API_TOKEN` with `wrangler secret put`.
2. In the Windows desktop app, set the relay endpoint
   (`https://amc-relay.huynhphuocdat2.workers.dev/api`) and desktop token in
   Notifications. The phone must use the same endpoint: a pairing code only
   works on the relay that issued it.
3. Enable Options > Remote Control > Phone command relay.
4. Use Pair control app to create a pairing code.
5. Install/run the Android app, enter the relay endpoint and pairing code, then
   run scripts, Fastlane lanes, or shell commands against allowed project roots.

Remote shell execution is constrained to recent project folders plus any roots
saved in Remote Control > Allowed roots.

### What a paired phone is allowed to do

A phone's permissions are fixed when it is paired, not when it sends a command.
The desktop attaches scopes to the pairing it creates and the relay copies them
onto the device; scopes a phone asks for are ignored, and a command outside its
scopes is rejected with 403.

Every phone gets `run` (scripts, Fastlane lanes, shell in allowed roots). The
machine-level scopes come from Options > Điều khiển and are off by default:

- **Cho phép tắt, khởi động lại, ngủ, khóa máy** adds the `power` scope.
- **Cho phép điều khiển cửa sổ và ứng dụng** adds the `window` scope, limited
  to the executables listed under Ứng dụng cho phép.

Turning a switch on does not widen a phone that is already paired — re-pair it
to change what it can do. Phones paired before scopes existed keep `run` only.

The phone's control token is held in `flutter_secure_storage`. A token written
to preferences by an older build is moved there and scrubbed on first launch.

### Controlling the machine from the phone

The Máy tính tab can lock, sleep, restart and shut the desktop down. These
travel on a separate control lane that the desktop drains even while a release
is running — locking your machine is most wanted exactly then.

- Shutting down or restarting asks twice, then counts down for 15 seconds. Both
  the phone and the desktop show a cancel button during the countdown; the
  desktop's banner sits above everything else on screen.
- While a release is running, a disruptive action is refused unless you pick
  "Vẫn tắt" in the confirmation. Nothing is ever forced closed by default.
- Restart uses `shutdown /g` rather than `/r` so Windows signs back in and
  reopens the app. On a machine with a PIN this is what brings the agent back;
  it depends on Automatic Restart Sign-On being enabled, so verify it on the
  machine rather than assuming it.
- "Ngủ" renames itself to "Ngủ đông" when `powercfg /a` says the machine has no
  real standby state and would hibernate instead.
- The phone shows **Đang mở**, **Đang khóa** or **Offline**. A locked machine
  still takes every command.

### Waking the machine

The phone sends the Wake-on-LAN magic packet itself, because a magic packet is
a broadcast inside your home network and does not route over the internet. So
this only works while the phone is on the same Wi-Fi as the machine.

The desktop publishes what it knows about its own wake readiness in every
heartbeat — MAC address, subnet broadcast, adapter type, Wake on Magic Packet,
Fast Startup, restart sign-on policy, BitLocker pre-boot PIN — because by the
time you need any of it the machine is asleep and cannot be asked. When a wake
attempt gets no heartbeat within 90 seconds, the phone lists what is standing
in the way and what to do about each one.

Run `installer/windows/configure_wake.ps1` once before relying on this; it
asks for elevation itself. It turns off **Wake on Pattern Match** and leaves **Wake on Magic
Packet** on, then reports what is set and lists any pending wake timers.

Pattern match is the setting that bites: left on, the card wakes the machine
for ordinary network traffic, and a home network broadcasts constantly — so the
machine wakes a few seconds after every sleep. That reads as "sleep is broken",
and it makes any wake test meaningless, because the magic packet arrives at a
machine that is already awake. `-ReadOnly` reports without changing anything
and needs no elevation. The elevated run also prints what is holding the
machine awake (`powercfg -requests`), which devices may wake it, and any
pending wake timers — a driver holding a power request produces the same
symptom as a stray wake signal.

A USB-connected phone is worth unplugging while testing, for the same reason:
USB devices are a common wake source.

**The app answers the first question itself.** While awake, the desktop listens
on UDP 9 and 7 for magic packets aimed at its own MAC and reports the last one
in its heartbeat, so the phone's wake panel says whether the packet can reach
the machine at all. Tap wake with the machine on: if the panel confirms a
packet arrived, the network path is fine and any sleep failure is the card or
the router. Nothing is observed while asleep — the app is not running then — so
the panel is careful to say what it does and does not prove.

`watch_wake_packet.ps1` does the same from the command line, with the source
address of every datagram. Run it while
the machine is awake and press the phone's wake button: nothing in a sleeping
machine is observable, so listening while awake is what separates "the packet
never arrives" from "the sleeping card ignores it".

```powershell
powershell -ExecutionPolicy Bypass -File "$PWD\installer\windows\watch_wake_packet.ps1"
```

Both scripts here take a path, so run them from the repository root or pass the
full path — a relative one fails from anywhere else, `C:\Windows\System32`
included.

It reports each datagram's source and whether it is a magic packet for this
machine's MAC, and needs no elevation.

**A wireless card can pass every Windows check and still never wake.** On the
machine this was developed against, Wake on Magic Packet was Enabled, the card
was armed, pattern match was off, the packet demonstrably reached the machine
while awake, and the keyboard woke it from sleep — but the phone never could.
Most laptops cut power to the Wi-Fi radio in sleep regardless of the driver
setting, and only a firmware option keeps it alive. Look for **Wake on WLAN**
in BIOS (HP puts it under Advanced > Built-in Device Options). Without it,
remote wake needs the Ethernet port.

**The probe needs a firewall rule; waking does not.** Windows Firewall drops
inbound UDP to an app with no rule, so the probe reports "no packet arrived"
for a reason that has nothing to do with the network — which is exactly how a
debugging round gets spent on the wrong thing. Waking from sleep never touches
the firewall: the network card acts on the magic packet while the OS is down.
Run the script with `-AllowWakeProbe` before trusting a negative result.

Four switches handle what turns up in that report:

- `-FixWakeTasks` clears **Wake the computer to run this task** from every
  scheduled task that has it. Vendor health-check tasks routinely set it, and a
  task waking a sleeping laptop shows up as a wake with no device to blame.
- `-IsolateWake` leaves only the network card armed to wake the machine. This
  is the decisive test when the machine still will not stay asleep: if it
  sleeps through with everything else disarmed, one of those devices was doing
  it. The trade-off is that a keypress or mouse move no longer wakes the
  machine — `powercfg -deviceenablewake "<device>"` puts one back.
- `-AllowWakeProbe` adds an inbound rule for UDP 9 and 7 so the probe can see
  the packets. Remove it with
  `Remove-NetFirewallRule -DisplayName "App Management Center wake probe"`.
- `-MaxWifiPower` stops the wireless radio entering low-power states, in both
  the power plan and the driver. A card can only act on a magic packet while it
  is still powered and still associated. Costs battery, and resets the adapter
  briefly when applied.

What matters is the state the machine is in, not whether it is on Wi-Fi:

| From | Wi-Fi | Ethernet |
|---|---|---|
| Sleep or hibernate | Works if the card supports magic packets and Windows has it armed | Works |
| Full shutdown | Almost never — the card loses power | Works with Fast Startup off and `S5WakeOnLan` on |

So on a laptop, **use Sleep rather than Shut down** when you still want to wake
it remotely. The diagnostics compute `canWakeFromSleep` and
`canWakeFromShutdown` separately and say which one applies.

Capability is read from the driver keyword `*WakeOnMagicPacket` plus
`powercfg -devicequery wake_armed` — supporting magic packets and being allowed
to wake the machine are different things, and `Get-NetAdapterPowerManagement`
fails outright on some Wi-Fi cards that work fine.

A setting the desktop could not read is reported as unknown, never as off — so
the phone will not send you into a BIOS for something it never actually checked.

Enable **Tự khởi động cùng Windows** in Options > Điều khiển. Without it the
agent does not come back after a reboot, because nothing starts the app until
someone opens it by hand — which makes remote restart a one-way trip. The
installer adds the Startup entry and the uninstaller removes it.

## Accounts and Teams (Cloudflare Worker + D1)

Team login and shared HTTP Tools are served by the `amc-api` Cloudflare Worker
in `cloudflare/amc-api`, backed by the `amc-relay` D1 database (the Worker owns
only the tables in `cloudflare/amc-api/migrations`).

1. Start the app. The first user can register and create a team as Admin.
2. Admin users can open the Team menu in the app header to create invite codes
   for Admin or Dev members.

HTTP Tool collections, folders, requests, and environments, and the QA Desk
demo-account vault, are shared per team.
Quick Requests can be configured once and run directly from the HTTP Tool;
they follow the active local or team workspace and may require confirmation
for reset or other destructive calls.
HTTP response history stays local on each machine.

The app talks to `BackendConfig.defaultApiBaseUrl`. To point it elsewhere (for
example a local `wrangler dev`), set `AMC_API_BASE_URL` with
`--dart-define=AMC_API_BASE_URL=http://localhost:8787`, the process
environment, or `.env`. Plain `http` is accepted only for localhost.

Passwords never leave the machine: the app sends a PBKDF2-SHA256 key derived
from the password and email, and the Worker stores an HMAC of that key with a
per-user salt and the `PASSWORD_PEPPER` secret. Sessions are opaque 30-day
tokens kept in the OS secure store; the Worker stores only their SHA-256.

### Worker development and deploy

```sh
cd cloudflare/amc-api
npm install
npx wrangler login
cp .dev.vars.example .dev.vars        # set a random PASSWORD_PEPPER
npx wrangler d1 migrations apply amc-relay --local
npm test
npx wrangler dev                      # http://localhost:8787
```

Production (run once per change as needed):

```sh
npx wrangler secret put PASSWORD_PEPPER   # first deploy only; never rotate casually
npx wrangler d1 migrations apply amc-relay --remote
npx wrangler deploy
```

Rotating `PASSWORD_PEPPER` invalidates every stored password.

## Telegram Release Notes

1. Create a bot with `@BotFather` by running `/newbot` and keep its token
   private.
2. Add the bot to the target Telegram group and allow it to send messages.
3. Send a command that mentions the bot in the group, such as
   `/start@your_bot_name`.
4. Open `https://api.telegram.org/bot<BOT_TOKEN>/getUpdates` and copy the
   group's `message.chat.id`. Supergroup IDs commonly start with `-100`.
5. In Options > AI Release Notes > Telegram, enter the bot token and chat ID,
   then select Save and Test.
6. Enable Auto send release updates. Generate a release note and verify the
   group receives the app name, full pubspec version, and notes.
7. Run Deploy and choose Upload for CH Play. After the AAB/CH Play command
   succeeds, the app builds a release APK, renames it as
   `<AppName>_v<VersionName>_<dd_MM_yyyy>.apk`, and sends it to the same group.

The APK remains under `build/app/outputs/flutter-apk` if Telegram auto send is
disabled or delivery fails. Telegram's hosted Bot API accepts documents up to
50 MB; larger APKs can be delivered through the Google Drive fallback below.

## Google Drive APK fallback

Use this only when you want APKs larger than Telegram's 50 MB Bot API document
limit to be uploaded to Drive and sent as a Telegram link.

1. In Google Cloud Console, enable Google Drive API for the project.
2. Configure the OAuth consent screen for the Google account that will upload
   release APKs.
3. Create an OAuth Client ID with application type Desktop app. Copy the
   Client ID. If Google also shows or downloads a Client Secret for that
   client, keep it private; some Google OAuth clients require it during the
   token exchange.
4. In Options > AI Release Notes > Telegram > Google Drive APK fallback, enter
   the OAuth Client ID. If Connect Drive previously failed with
   `client_secret is missing`, also enter the OAuth Client Secret, then select
   Save Drive.
5. Select Connect Drive, sign in with the browser, and allow the narrow
   `drive.file` scope.
6. Select Test Drive. The app creates or reuses a folder named
   `App Management Center APKs`.
7. Enable Use Drive for APKs over 50 MB. The switch is available only when the
   Telegram config is complete and Drive is connected.
8. To upload an APK to Drive without running a CH Play deploy, select
   Build/Upload APK. The app reuses the latest release APK in
   `build/app/outputs/flutter-apk` when one exists; otherwise it builds a new
   release APK first, renames it with the standard
   `<AppName>_v<VersionName>_<dd_MM_yyyy>.apk` format, uploads it to Drive, and
   shows the resulting link in the status/log.

Drive credentials are stored with the platform secure credential store. The app
does not log Google access tokens or refresh tokens. Uploaded APKs are shared as
Anyone with link / reader so the Telegram group can download them.

The bot token is stored with the platform secure credential store and must not
be committed or placed in project files. If it is exposed, revoke and replace
it through `@BotFather`.

The command progress bar in the application header covers standalone commands
and multi-step workflows such as Play image validation, deploy, release APK
build, and Telegram upload.

## Windows Installer

Build the release application and package it as one per-user installer EXE:

```powershell
flutter build windows --release
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File installer\windows\build_installer.ps1
```

The installer is written to `build\installer`. It installs the complete Flutter
runtime under `%LOCALAPPDATA%\Programs\App Management Center`, creates Desktop and
Start Menu shortcuts, and registers an uninstall entry without requiring
administrator permission.

To build and deliver the installer from the app, select this App Management Center
repo in the Project panel, configure Telegram, then use Options > Telegram >
Windows installer > Build/Send Installer. Installers up to Telegram's 50 MB Bot
API document limit are uploaded directly. Larger installers are uploaded with
the existing Google Drive connection and sent to Telegram as a Drive link.

## Checks

```powershell
flutter analyze
flutter test
flutter build windows --release
flutter build apk --debug
cd serverless\notifications
npm test -- --runInBand
npm run lint
cd ..\..\cloudflare\amc-api
npm test
npm run typecheck
```

### `No target "app_release_center"` when building Windows

Seen after pulling the App Management Center rename onto a working copy that
already has a `build\` directory:

```
CMake Error: Error evaluating generator expression:
    $<TARGET_FILE_DIR:app_release_center>
  No target "app_release_center"
```

The CMake target is named after `BINARY_NAME` in `windows\CMakeLists.txt`, and
renaming it leaves the cached `CMakeCache.txt`, `.sln` and `.vcxproj` files in
`build\windows` pointing at a target that no longer exists. The source tree is
fine; only the build directory is stale.

```powershell
flutter clean
flutter pub get
```

Any future change to `BINARY_NAME` needs the same clean.
