import Cocoa
import FlutterMacOS
import ApplicationServices

public class AmcRemotePlatformPlugin: NSObject, FlutterPlugin {
  private var sessionId: String?
  private var displayId: CGDirectDisplayID?
  private let input = RemoteMacInput()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = AmcRemotePlatformPlugin()
    let channel = FlutterMethodChannel(name: "amc/remote_platform", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }
  deinit { input.releaseAll() }
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "permissions":
      let request = args["request"] as? Bool == true
      if request && !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
      if request && !AXIsProcessTrusted() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
      }
      result(["screen": CGPreflightScreenCaptureAccess(), "input": AXIsProcessTrusted()])
    case "displays":
      var count: UInt32 = 0
      CGGetActiveDisplayList(0, nil, &count)
      var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
      CGGetActiveDisplayList(count, &displays, &count)
      result(displays.prefix(Int(count)).map { display -> [String: Any] in
        let bounds = CGDisplayBounds(display)
        return ["id": String(display), "width": CGDisplayPixelsWide(display),
                "height": CGDisplayPixelsHigh(display),
                "scaleFactor": Double(CGDisplayPixelsWide(display)) / max(1, bounds.width)]
      })
    case "beginInput":
      guard AXIsProcessTrusted(), let id = args["sessionId"] as? String, !id.isEmpty,
            let raw = args["displayId"] as? String, let display = UInt32(raw), CGDisplayIsActive(display) != 0 else {
        result(FlutterError(code: "permission", message: "Cần quyền Accessibility và màn hình còn hoạt động.", details: nil)); return
      }
      guard sessionId == nil || sessionId == id else {
        result(FlutterError(code: "busy", message: "Máy đang nhận input từ phiên khác.", details: nil)); return
      }
      input.releaseAll(); sessionId = id; displayId = display; result(nil)
    case "endInput", "releaseInputs":
      if args["sessionId"] as? String == sessionId {
        input.releaseAll()
        if call.method == "endInput" { sessionId = nil; displayId = nil }
      }
      result(nil)
    case "input":
      guard let id = sessionId, args["sessionId"] as? String == id,
            AXIsProcessTrusted(), let display = displayId, CGDisplayIsActive(display) != 0 else {
        input.releaseAll()
        result(FlutterError(code: "session", message: "Phiên nhập liệu chưa được cấp quyền hoặc đã mất quyền.", details: nil)); return
      }
      if input.apply(args, display: display) { result(nil) }
      else { input.releaseAll(); result(FlutterError(code: "input", message: "Phím hoặc sự kiện không được hỗ trợ.", details: nil)) }
    default: result(FlutterMethodNotImplemented)
    }
  }
}
