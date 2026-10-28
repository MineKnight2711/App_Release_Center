import Cocoa
import FlutterMacOS
import ServiceManagement

@main
class AppDelegate: FlutterAppDelegate {
  var backgroundEnabled = false
  private var statusItem: NSStatusItem?
  private var backgroundChannel: FlutterMethodChannel?
  private var terminating = false
  private var quitting = false
  var isQuitting: Bool { quitting }
  private var backgroundActivity: NSObjectProtocol?
  func installBackground(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "amc/background", binaryMessenger: messenger)
    backgroundChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "configure":
        let args = call.arguments as? [String: Any] ?? [:]
        self.backgroundEnabled = args["enabled"] as? Bool == true
        if self.backgroundEnabled {
          if self.backgroundActivity == nil { self.backgroundActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "AMC background host") }
          if self.statusItem == nil {
            self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            self.statusItem?.button?.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "App Management Center")
          }
          let menu = NSMenu()
          for (title, selector) in [("Mở AMC", #selector(self.restoreAMC)), ("SwiftDesk", #selector(self.openRemote)), ("Thoát AMC", #selector(self.quitAMC))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self; menu.addItem(item)
          }
          self.statusItem?.menu = menu
        } else {
          if let activity = self.backgroundActivity { ProcessInfo.processInfo.endActivity(activity) }
          self.backgroundActivity = nil
          if let item = self.statusItem { NSStatusBar.system.removeStatusItem(item) }
          self.statusItem = nil
          if NSApp.windows.allSatisfy({ !$0.isVisible }) { self.restoreAMC() }
        }
        result(nil)
      case "restore": self.restoreAMC(); result(nil)
      case "state": result(["enabled": self.backgroundEnabled, "statusItem": self.statusItem != nil,
                            "windowClass": self.mainFlutterWindow.map { String(describing: type(of: $0)) } ?? "none"])
      case "quitNow":
        self.quitting = true; result(nil)
        if self.terminating { NSApp.reply(toApplicationShouldTerminate: true) }
        else { NSApp.terminate(nil) }
      case "autostart":
        if #available(macOS 13.0, *) { result(SMAppService.mainApp.status == .enabled) }
        else { result(false) }
      case "setAutostart":
        let path = Bundle.main.bundleURL.path
        if call.arguments as? Bool == true && !path.hasPrefix("/Applications/") && !path.hasPrefix(NSHomeDirectory() + "/Applications/") {
          result(FlutterError(code: "autostart", message: "Cài AMC vào Applications trước khi bật khởi động cùng máy.", details: nil)); return
        }
        if #available(macOS 13.0, *) {
          do {
            if call.arguments as? Bool == true { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            result(nil)
          } catch { result(FlutterError(code: "autostart", message: error.localizedDescription, details: nil)) }
        } else { result(FlutterError(code: "autostart", message: "Cần macOS 13 trở lên.", details: nil)) }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  @objc private func restoreAMC() {
    NSApp.activate(ignoringOtherApps: true)
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
  }
  @objc private func openRemote() { restoreAMC(); backgroundChannel?.invokeMethod("open", arguments: "remoteHost") }
  @objc private func quitAMC() { NSApp.terminate(nil) }
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if quitting || backgroundChannel == nil { return .terminateNow }
    if terminating { return .terminateLater }
    terminating = true
    backgroundChannel?.invokeMethod("quit", arguments: nil) { [weak self] _ in
      guard let self = self, !self.quitting else { return }
      self.quitting = true; NSApp.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    // Refresh the Dock icon even when Launch Services cached an older build.
    if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
       let icon = NSImage(contentsOf: iconURL) {
      NSApplication.shared.applicationIconImage = icon
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return !backgroundEnabled
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
