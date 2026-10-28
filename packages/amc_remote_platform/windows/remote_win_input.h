#ifndef AMC_REMOTE_WIN_INPUT_H_
#define AMC_REMOTE_WIN_INPUT_H_
#include <flutter/encodable_value.h>
#include <windows.h>
#include <shellscalingapi.h>
#include <cmath>
#include <set>
#include <string>
#include <vector>

namespace amc_remote {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
inline std::string Text(const Map& args, const char* key) {
  auto it = args.find(Value(key));
  const auto* v = it == args.end() ? nullptr : std::get_if<std::string>(&it->second);
  return v ? *v : std::string();
}
inline double Number(const Map& args, const char* key) {
  auto it = args.find(Value(key));
  const auto* v = it == args.end() ? nullptr : std::get_if<double>(&it->second);
  return v ? *v : NAN;
}
inline int Integer(const Map& args, const char* key) {
  auto it = args.find(Value(key));
  if (it == args.end()) return -1;
  if (const auto* n = std::get_if<int32_t>(&it->second)) return *n;
  return -1;
}
inline bool Boolean(const Map& args, const char* key, bool* value) {
  auto it = args.find(Value(key));
  if (it == args.end()) return false;
  if (const auto* b = std::get_if<bool>(&it->second)) { *value = *b; return true; }
  return false;
}
inline bool UserDesktop() {
  HDESK desktop = OpenInputDesktop(0, FALSE, DESKTOP_READOBJECTS);
  if (!desktop) return false;
  wchar_t name[128]{}; DWORD needed = 0;
  bool ok = GetUserObjectInformationW(desktop, UOI_NAME, name, sizeof(name), &needed) && _wcsicmp(name, L"Default") == 0;
  CloseDesktop(desktop); return ok;
}
struct Monitor { std::wstring name; RECT rect{}; HMONITOR handle = nullptr; };
inline BOOL CALLBACK FindMonitor(HMONITOR handle, HDC, LPRECT, LPARAM parameter) {
  auto* monitor = reinterpret_cast<Monitor*>(parameter);
  MONITORINFOEXW info{}; info.cbSize = sizeof(info);
  if (GetMonitorInfoW(handle, reinterpret_cast<MONITORINFO*>(&info)) && monitor->name == info.szDevice) {
    monitor->rect = info.rcMonitor; monitor->handle = handle; return FALSE;
  }
  return TRUE;
}
inline bool ResolveMonitor(const std::string& id, Monitor* monitor) {
  try {
    size_t parsed = 0; int index = std::stoi(id, &parsed);
    if (index < 0 || parsed != id.size()) return false;
    DISPLAY_DEVICEW device{}; device.cb = sizeof(device);
    if (!EnumDisplayDevicesW(nullptr, static_cast<DWORD>(index), &device, 0) || !(device.StateFlags & DISPLAY_DEVICE_ACTIVE)) return false;
    monitor->name = device.DeviceName;
    EnumDisplayMonitors(nullptr, nullptr, FindMonitor, reinterpret_cast<LPARAM>(monitor));
    return monitor->handle != nullptr;
  } catch (...) { return false; }
}
inline flutter::EncodableList Displays() {
  flutter::EncodableList values;
  for (DWORD index = 0;; ++index) {
    DISPLAY_DEVICEW device{}; device.cb = sizeof(device);
    if (!EnumDisplayDevicesW(nullptr, index, &device, 0)) break;
    Monitor monitor;
    if (!ResolveMonitor(std::to_string(index), &monitor)) continue;
    double scale = 1.0;
    UINT x = 96, y = 96;
    if (SUCCEEDED(GetDpiForMonitor(monitor.handle, MDT_EFFECTIVE_DPI, &x, &y))) scale = x / 96.0;
    values.emplace_back(Map{{Value("id"), Value(std::to_string(index))},
      {Value("width"), Value(static_cast<int>(monitor.rect.right - monitor.rect.left))},
      {Value("height"), Value(static_cast<int>(monitor.rect.bottom - monitor.rect.top))},
      {Value("scaleFactor"), Value(scale)}});
  }
  return values;
}

class InputState {
 public:
  ~InputState() { Release(); }
  void Release() {
    for (WORD scan : keys_) SendKey(scan, false);
    keys_.clear();
    for (const auto& button : buttons_) SendMouse(button, false);
    buttons_.clear();
  }
  bool Apply(const Map& args, const RECT& rect) {
    auto type = Text(args, "type");
    if (type == "release") { Release(); return true; }
    if (type == "pointer" || type == "button") {
      double x = Number(args, "x"), y = Number(args, "y");
      if (!std::isfinite(x) || !std::isfinite(y) || x < 0 || x > 1 || y < 0 || y > 1) return false;
      if (!SetCursorPos(rect.left + static_cast<int>(x * (rect.right - rect.left - 1)),
                        rect.top + static_cast<int>(y * (rect.bottom - rect.top - 1)))) return false;
      if (type == "pointer") return true;
      const auto button = Text(args, "button"); bool down = false;
      if ((button != "left" && button != "right" && button != "middle") || !Boolean(args, "down", &down)) return false;
      if (!SendMouse(button, down)) return false;
      if (down) buttons_.insert(button); else buttons_.erase(button);
      return true;
    }
    if (type == "wheel") {
      double dx = Number(args, "dx"), dy = Number(args, "dy");
      if (!std::isfinite(dx) || !std::isfinite(dy) || std::abs(dx) > 2400 || std::abs(dy) > 2400) return false;
      for (int direction = 0; direction < 2; ++direction) {
        INPUT event{}; event.type = INPUT_MOUSE;
        event.mi.dwFlags = direction == 0 ? MOUSEEVENTF_WHEEL : MOUSEEVENTF_HWHEEL;
        event.mi.mouseData = static_cast<DWORD>(static_cast<LONG>(direction == 0 ? -dy : dx));
        if (SendInput(1, &event, sizeof(INPUT)) != 1) return false;
      }
      return true;
    }
    if (type == "key") {
      const int usage = Integer(args, "usage"); bool down = false;
      if ((usage >> 16) != 7 || !Boolean(args, "down", &down)) return false;
      WORD scan = Scan(usage & 0xffff);
      if (!scan || !SendKey(scan, down)) return false;
      if (down) keys_.insert(scan); else keys_.erase(scan);
      return true;
    }
    if (type == "text") {
      const auto text = Text(args, "text");
      int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0);
      if (count < 1 || count > 1024 || text.find('\0') != std::string::npos) return false;
      std::wstring wide(count, L'\0');
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), wide.data(), count);
      std::vector<INPUT> events;
      for (wchar_t unit : wide) {
        INPUT event{}; event.type = INPUT_KEYBOARD; event.ki.wScan = unit; event.ki.dwFlags = KEYEVENTF_UNICODE;
        events.push_back(event); event.ki.dwFlags |= KEYEVENTF_KEYUP; events.push_back(event);
      }
      const auto size = static_cast<UINT>(events.size());
      if (SendInput(size, events.data(), sizeof(INPUT)) == size) return true;
      for (auto& event : events) event.ki.dwFlags |= KEYEVENTF_KEYUP;
      SendInput(size, events.data(), sizeof(INPUT)); return false;
    }
    return false;
  }
 private:
  std::set<WORD> keys_;
  std::set<std::string> buttons_;
  static bool SendKey(WORD scan, bool down) {
    INPUT event{}; event.type = INPUT_KEYBOARD; event.ki.wScan = scan & 0xff;
    event.ki.dwFlags = KEYEVENTF_SCANCODE | ((scan & 0xe000) ? KEYEVENTF_EXTENDEDKEY : 0) | (down ? 0 : KEYEVENTF_KEYUP);
    return SendInput(1, &event, sizeof(INPUT)) == 1;
  }
  static bool SendMouse(const std::string& button, bool down) {
    INPUT event{}; event.type = INPUT_MOUSE;
    event.mi.dwFlags = button == "left" ? (down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP) :
      button == "right" ? (down ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP) : (down ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP);
    return SendInput(1, &event, sizeof(INPUT)) == 1;
  }
  static WORD Scan(int usage) {
    const WORD letters[] = {0x1e,0x30,0x2e,0x20,0x12,0x21,0x22,0x23,0x17,0x24,0x25,0x26,0x32,0x31,0x18,0x19,0x10,0x13,0x1f,0x14,0x16,0x2f,0x11,0x2d,0x15,0x2c};
    if (usage >= 4 && usage <= 29) return letters[usage - 4];
    if (usage >= 0x1e && usage <= 0x26) return static_cast<WORD>(usage - 0x1e + 2);
    if (usage == 0x27) return 0x0b;
    if (usage >= 0x3a && usage <= 0x43) return static_cast<WORD>(usage - 0x3a + 0x3b);
    const std::pair<int, WORD> special[] = {
      {0x28,0x1c},{0x29,1},{0x2a,0xe},{0x2b,0xf},{0x2c,0x39},{0x2d,0xc},{0x2e,0xd},{0x2f,0x1a},{0x30,0x1b},
      {0x31,0x2b},{0x32,0x2b},{0x33,0x27},{0x34,0x28},{0x35,0x29},{0x36,0x33},{0x37,0x34},{0x38,0x35},{0x39,0x3a},
      {0x44,0x57},{0x45,0x58},{0x46,0xe037},{0x47,0x46},{0x49,0xe052},{0x4a,0xe047},{0x4b,0xe049},
      {0x4c,0xe053},{0x4d,0xe04f},{0x4e,0xe051},{0x4f,0xe04d},{0x50,0xe04b},{0x51,0xe050},{0x52,0xe048},
      {0x53,0x45},{0x54,0xe035},{0x55,0x37},{0x56,0x4a},{0x57,0x4e},{0x58,0xe01c},{0x59,0x4f},
      {0x5a,0x50},{0x5b,0x51},{0x5c,0x4b},{0x5d,0x4c},{0x5e,0x4d},{0x5f,0x47},{0x60,0x48},{0x61,0x49},{0x62,0x52},{0x63,0x53},{0x64,0x56},{0x65,0xe05d},
      {0xe0,0x1d},{0xe1,0x2a},{0xe2,0x38},{0xe3,0xe05b},{0xe4,0xe01d},{0xe5,0x36},{0xe6,0xe038},{0xe7,0xe05c}};
    for (const auto& entry : special) if (entry.first == usage) return entry.second;
    return 0;
  }
};
}  // namespace amc_remote
#endif
