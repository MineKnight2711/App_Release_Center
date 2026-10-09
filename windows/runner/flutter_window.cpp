#include "flutter_window.h"

#include <algorithm>
#include <optional>
#include <shellapi.h>
#include <wtsapi32.h>
#include <flutter/standard_method_codec.h>
#include <flutter/method_result_functions.h>
#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
using Value = flutter::EncodableValue;
constexpr UINT kTray = WM_APP + 70;
constexpr UINT kRestore = WM_APP + 71;
const UINT kTaskbarCreated = RegisterWindowMessage(L"TaskbarCreated");

std::wstring ExecutableDirectory() {
  wchar_t path[32768] = {};
  const DWORD length = GetModuleFileNameW(nullptr, path, 32768);
  if (length == 0 || length >= 32768) return {};
  const std::wstring executable(path, length);
  const size_t separator = executable.find_last_of(L"\\/");
  return separator == std::wstring::npos ? std::wstring() : executable.substr(0, separator);
}
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project, FlutterWindow* main)
    : project_(project), main_(main) {}
FlutterWindow::~FlutterWindow() { OnDestroy(); }

bool FlutterWindow::SetTray(bool enabled) {
  NOTIFYICONDATA data{};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = 1;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kTray;
  data.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(data.szTip, L"AMC - Plan Studio reminders");
  if (enabled && !tray_added_) tray_added_ = Shell_NotifyIcon(NIM_ADD, &data) != FALSE;
  if (!enabled && tray_added_) { Shell_NotifyIcon(NIM_DELETE, &data); tray_added_ = false; }
  return !enabled || tray_added_;
}

void FlutterWindow::RestoreMain() {
  ShowWindow(GetHandle(), IsIconic(GetHandle()) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(GetHandle());
}

void FlutterWindow::ShowReminder() {
  if (!main_ || !popup_ready_ || main_->session_locked_ || std::holds_alternative<std::monostate>(main_->snapshot_)) return;
  const HWND window = GetHandle();
  // Clamp to the current work area, including after a monitor is removed.
  RECT rect{}; GetWindowRect(window, &rect);
  MONITORINFO info{}; info.cbSize = sizeof(info);
  GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &info);
  const int width = std::min(static_cast<int>(rect.right - rect.left), static_cast<int>(info.rcWork.right - info.rcWork.left));
  const int height = std::min(static_cast<int>(rect.bottom - rect.top), static_cast<int>(info.rcWork.bottom - info.rcWork.top));
  const int x = std::clamp(static_cast<int>(rect.left), static_cast<int>(info.rcWork.left), static_cast<int>(info.rcWork.right) - width);
  const int y = std::clamp(static_cast<int>(rect.top), static_cast<int>(info.rcWork.top), static_cast<int>(info.rcWork.bottom) - height);
  SetWindowPos(window, topmost_ ? HWND_TOPMOST : HWND_NOTOPMOST, x, y, width, height, SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) return false;
  const RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) return false;
  // Popup is a renderer only. It needs no Firebase, SQLite, webview or other plugins.
  if (!main_) RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow(), main_ == nullptr);
  reminders_ = std::make_unique<flutter::MethodChannel<Value>>(flutter_controller_->engine()->messenger(),
      "amc/plan_reminders", &flutter::StandardMethodCodec::GetInstance());
  reminders_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto& method = call.method_name();
    const Value args = call.arguments() ? *call.arguments() : Value();
    if (main_) {
      if (method == "ready") { popup_ready_ = true; result->Success(main_->snapshot_); return; }
      if (method == "rendered") {
        ShowReminder();
        main_->reminders_->InvokeMethod("presented", std::make_unique<Value>(args));
        result->Success(); return;
      }
      if (method == "topmost") {
        topmost_ = std::get<bool>(args); ShowReminder(); result->Success(); return;
      }
      if (method == "action") {
        auto reply = std::shared_ptr<flutter::MethodResult<Value>>(result.release());
        main_->reminders_->InvokeMethod("action", std::make_unique<Value>(args),
          std::make_unique<flutter::MethodResultFunctions<Value>>(
            [reply](const Value* value) { if (value) reply->Success(*value); else reply->Success(); },
            [reply](const std::string& code, const std::string& message, const Value*) { reply->Error(code, message); },
            [reply]() { reply->NotImplemented(); }));
        return;
      }
    } else {
      if (method == "show") {
        snapshot_ = args;
        if (!popup_) {
          auto popup_project = project_;
          popup_project.set_dart_entrypoint_arguments({"--plan-reminder-window"});
          popup_ = std::make_unique<FlutterWindow>(popup_project, this);
          if (!popup_->Create(L"Plan Studio - Nhac hen", Point(80, 80), Size(720, 540))) {
            popup_.reset(); result->Error("window", "Cannot create reminder window"); return;
          }
          popup_->SetQuitOnClose(false);
        } else if (popup_->popup_ready_) {
          popup_->reminders_->InvokeMethod("snapshot", std::make_unique<Value>(snapshot_));
        }
        result->Success(); return;
      }
      if (method == "hide") {
        snapshot_ = Value();
        if (popup_) ShowWindow(popup_->GetHandle(), SW_HIDE);
        result->Success(); return;
      }
      if (method == "restore") { RestoreMain(); result->Success(); return; }
      if (method == "background") {
        const bool enabled = std::get<bool>(args);
        if (!SetTray(enabled)) { result->Error("tray", "Cannot create system tray icon"); return; }
        background_ = enabled;
        result->Success(); return;
      }

    }
    result->NotImplemented();
  });
  if (!main_) {
    windows_ = std::make_unique<flutter::MethodChannel<Value>>(
        flutter_controller_->engine()->messenger(), "amc/windows",
        &flutter::StandardMethodCodec::GetInstance());
    windows_->SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() != "installRemoteUnlock") {
        result->NotImplemented();
        return;
      }
      const std::wstring directory = ExecutableDirectory();
      if (directory.empty()) {
        result->Error("installer_path", "Cannot resolve the application directory.");
        return;
      }
      const std::wstring script = directory + L"\\install_remote_unlock.ps1";
      if (GetFileAttributesW(script.c_str()) == INVALID_FILE_ATTRIBUTES) {
        result->Error("installer_missing", "install_remote_unlock.ps1 is missing beside the app.");
        return;
      }
      const std::wstring parameters = L"-NoProfile -ExecutionPolicy Bypass -File \"" +
                                      script + L"\" -Elevated";
      SHELLEXECUTEINFOW execute = {};
      execute.cbSize = sizeof(execute);
      execute.fMask = SEE_MASK_NOCLOSEPROCESS;
      execute.hwnd = GetHandle();
      execute.lpVerb = L"runas";
      execute.lpFile = L"powershell.exe";
      execute.lpParameters = parameters.c_str();
      execute.nShow = SW_SHOWNORMAL;
      if (!ShellExecuteExW(&execute)) {
        const DWORD error = GetLastError();
        result->Error(error == ERROR_CANCELLED ? "uac_cancelled" : "installer_launch",
                      error == ERROR_CANCELLED
                          ? "Administrator approval was cancelled."
                          : "Cannot start the remote unlock installer (Windows error " +
                                std::to_string(error) + ").");
        return;
      }
      if (execute.hProcess != nullptr) CloseHandle(execute.hProcess);
      result->Success();
    });
    WTSRegisterSessionNotification(GetHandle(), NOTIFY_FOR_THIS_SESSION);
    flutter_controller_->engine()->SetNextFrameCallback([this]() { Show(); });
  }
  flutter_controller_->ForceRedraw();
  return true;
}

void FlutterWindow::OnDestroy() {
  if (!main_) { SetTray(false); WTSUnRegisterSessionNotification(GetHandle()); }
  popup_.reset();
  if (windows_) { windows_->SetMethodCallHandler(nullptr); windows_.reset(); }
  if (reminders_) { reminders_->SetMethodCallHandler(nullptr); reminders_.reset(); }
  flutter_controller_.reset();
  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) noexcept {
  if (message == WM_CLOSE) {
    if (main_) {
      if (reminders_) reminders_->InvokeMethod("dismiss", nullptr);
      return 0;
    }
    if (background_ && tray_added_) { ShowWindow(hwnd, SW_HIDE); return 0; }
  }
  if (!main_ && message == kRestore) { RestoreMain(); return 0; }
  if (!main_ && message == kTaskbarCreated && background_) { tray_added_ = false; if (!SetTray(true)) RestoreMain(); return 0; }
  if (!main_ && message == kTray) {
    if (lparam == WM_LBUTTONDBLCLK) RestoreMain();
    if (lparam == WM_RBUTTONUP) {
      HMENU menu = CreatePopupMenu();
      AppendMenu(menu, MF_STRING, 1, L"Mo App Management Center");
      AppendMenu(menu, MF_STRING, 2, L"Hom nay");
      AppendMenu(menu, MF_STRING, 3, L"Tam ngung / Tiep tuc nhac");
      AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
      AppendMenu(menu, MF_STRING, 4, L"Thoat hoan toan");
      POINT point; GetCursorPos(&point); SetForegroundWindow(hwnd);
      const int selected = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, point.x, point.y, 0, hwnd, nullptr);
      DestroyMenu(menu);
      if (selected == 1) RestoreMain();
      if (selected == 2) { RestoreMain(); reminders_->InvokeMethod("today", nullptr); }
      if (selected == 3) reminders_->InvokeMethod("pause", nullptr);
      if (selected == 4) { background_ = false; PostMessage(hwnd, WM_CLOSE, 0, 0); }
    }
    return 0;
  }
  if (!main_ && message == WM_WTSSESSION_CHANGE) {
    if (wparam == WTS_SESSION_LOCK) { session_locked_ = true; if (popup_) ShowWindow(popup_->GetHandle(), SW_HIDE); }
    if (wparam == WTS_SESSION_UNLOCK) { session_locked_ = false; reminders_->InvokeMethod("wake", nullptr); }
  }
  if (!main_ && (message == WM_TIMECHANGE || (message == WM_POWERBROADCAST && (wparam == PBT_APMRESUMEAUTOMATIC || wparam == PBT_APMRESUMESUSPEND)))) {
    reminders_->InvokeMethod("wake", nullptr);
  }
  if (main_ && message == WM_DISPLAYCHANGE) { if (IsWindowVisible(hwnd)) ShowReminder(); }
  if (flutter_controller_) {
    auto result = flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    if (result) return *result;
  }
  if (message == WM_FONTCHANGE && flutter_controller_) flutter_controller_->engine()->ReloadSystemFonts();
  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
