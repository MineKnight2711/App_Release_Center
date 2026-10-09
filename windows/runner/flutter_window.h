#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project, FlutterWindow* main = nullptr);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> reminders_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> windows_;
  std::unique_ptr<FlutterWindow> popup_;
  FlutterWindow* main_ = nullptr;
  flutter::EncodableValue snapshot_;
  bool popup_ready_ = false;
  bool background_ = false;
  bool tray_added_ = false;
  bool session_locked_ = false;
  bool topmost_ = true;
  void ShowReminder();
  bool SetTray(bool enabled);
  void RestoreMain();
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
