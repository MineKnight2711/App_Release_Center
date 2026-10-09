#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {
struct InstanceGuard {
  HANDLE handle = nullptr;
  ~InstanceGuard() { if (handle) CloseHandle(handle); }
};
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // A debug launch must start its own engine for Flutter to attach, even when
  // the installed app (or a previous debug session) is still running.
#ifndef _DEBUG
  // Auxiliary webview processes have their own arguments and must remain free
  // to start. Only the normal application owns the reminder scheduler.
  InstanceGuard guard;
  if (command_line_arguments.empty() || command_line_arguments.front() != "web_view_title_bar") {
    guard.handle = CreateMutex(nullptr, FALSE, L"Local\\AMC.PlanStudio.Main");
    if (!guard.handle) return EXIT_FAILURE;
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
      HWND existing = FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", L"App Management Center");
      if (existing) PostMessage(existing, WM_APP + 71, 0, 0);
      return EXIT_SUCCESS;
    }
  }
#endif

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"App Management Center", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
