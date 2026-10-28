#include "include/amc_remote_platform/amc_remote_platform_plugin_c_api.h"
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <memory>
#include "remote_win_input.h"

namespace {
using namespace amc_remote;
class RemotePlugin : public flutter::Plugin {
 public:
  explicit RemotePlugin(flutter::PluginRegistrarWindows* registrar) {
    channel_ = std::make_unique<flutter::MethodChannel<Value>>(
        registrar->messenger(), "amc/remote_platform", &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      Map empty;
      const Map* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
      if (!args) args = &empty;
      const auto method = call.method_name();
      if (method == "permissions") {
        const bool desktop = UserDesktop();
        result->Success(Value(Map{{Value("screen"), Value(desktop)}, {Value("input"), Value(desktop)}}));
      } else if (method == "displays") {
        result->Success(Value(Displays()));
      } else if (method == "beginInput") {
        const auto id = Text(*args, "sessionId");
        const auto display = Text(*args, "displayId");
        if (!session_.empty() && session_ != id) {
          result->Error("busy", "Máy đang nhận input từ phiên khác."); return;
        }
        Monitor monitor;
        if (id.empty() || !UserDesktop() || !ResolveMonitor(display, &monitor)) {
          result->Error("display", "Màn hình hoặc desktop nhận input không còn hoạt động."); return;
        }
        input_.Release(); session_ = id; display_ = display; result->Success();
      } else if (method == "endInput" || method == "releaseInputs") {
        if (Text(*args, "sessionId") == session_) {
          input_.Release();
          if (method == "endInput") { session_.clear(); display_.clear(); }
        }
        result->Success();
      } else if (method == "input") {
        Monitor monitor;
        if (session_.empty() || Text(*args, "sessionId") != session_ ||
            !UserDesktop() || !ResolveMonitor(display_, &monitor)) {
          input_.Release();
          result->Error("session", "Phiên nhập liệu chưa được cấp quyền hoặc đã mất quyền."); return;
        }
        if (input_.Apply(*args, monitor.rect)) result->Success();
        else {
          input_.Release();
          result->Error("input", "Windows từ chối phím hoặc sự kiện (có thể do UIPI).");
        }
      } else {
        result->NotImplemented();
      }
    });
  }
 private:
  std::unique_ptr<flutter::MethodChannel<Value>> channel_;
  InputState input_;
  std::string session_, display_;
};
}  // namespace
void AmcRemotePlatformPluginCApiRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
  auto* windows = flutter::PluginRegistrarManager::GetInstance()
      ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  windows->AddPlugin(std::make_unique<RemotePlugin>(windows));
}
