import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    #if !DEBUG
    let diagnostic = CommandLine.arguments.contains { $0.hasPrefix("--swiftdesk-") || $0 == "web_view_title_bar" }
    if !diagnostic, let identifier = Bundle.main.bundleIdentifier,
       let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
      existing.activate(options: [.activateAllWindows])
      NSApp.terminate(nil)
      return
    }
    #endif
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    (NSApp.delegate as? AppDelegate)?.installBackground(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
    DispatchQueue.main.async { [weak self] in self?.delegate = self }
    self.zoom(nil)
  }
  // Flutter's window controller can replace the delegate after nib loading.
  // Own close itself so the policy remains effective in a packaged app.
  override func performClose(_ sender: Any?) { close() }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    close()
    return false
  }
  override func close() {
    guard let owner = NSApp.delegate as? AppDelegate else { super.close(); return }
    if owner.isQuitting { super.close() }
    else if owner.backgroundEnabled { orderOut(nil) }
    else { NSApp.terminate(nil) }
  }
}
