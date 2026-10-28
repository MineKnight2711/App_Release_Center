import Cocoa
import ApplicationServices

final class RemoteMacInput {
  private var keys = Set<CGKeyCode>()
  private var buttons = Set<String>()
  private var lastClickAt = 0.0
  private var lastClickPoint = CGPoint.zero
  private var clickCount: Int64 = 0
  private let letters: [CGKeyCode] = [0,11,8,2,14,3,5,4,34,38,40,37,46,45,31,35,12,15,1,17,32,9,13,7,16,6]
  private let digits: [CGKeyCode] = [18,19,20,21,23,22,26,28,25,29]
  private let special: [Int: CGKeyCode] = [
    0x28:36, 0x29:53, 0x2a:51, 0x2b:48, 0x2c:49, 0x2d:27, 0x2e:24,
    0x2f:33, 0x30:30, 0x31:42, 0x32:42, 0x33:41, 0x34:39, 0x35:50,
    0x36:43, 0x37:47, 0x38:44, 0x39:57,
    0x3a:122, 0x3b:120, 0x3c:99, 0x3d:118, 0x3e:96, 0x3f:97,
    0x40:98, 0x41:100, 0x42:101, 0x43:109, 0x44:103, 0x45:111,
    0x46:105, 0x47:107, 0x48:113, 0x49:114, 0x4a:115, 0x4b:116,
    0x4c:117, 0x4d:119, 0x4e:121, 0x4f:124, 0x50:123, 0x51:125, 0x52:126,
    0x53:71, 0x54:75, 0x55:67, 0x56:78, 0x57:69, 0x58:76, 0x59:83,
    0x5a:84, 0x5b:85, 0x5c:86, 0x5d:87, 0x5e:88, 0x5f:89, 0x60:91,
    0x61:92, 0x62:82, 0x63:65, 0x64:50,
    0xe0:59, 0xe1:56, 0xe2:58, 0xe3:55, 0xe4:62, 0xe5:60, 0xe6:61, 0xe7:54
  ]
  private var flags: CGEventFlags {
    var value: CGEventFlags = []
    if keys.contains(59) || keys.contains(62) { value.insert(.maskControl) }
    if keys.contains(56) || keys.contains(60) { value.insert(.maskShift) }
    if keys.contains(58) || keys.contains(61) { value.insert(.maskAlternate) }
    if keys.contains(55) || keys.contains(54) { value.insert(.maskCommand) }
    return value
  }
  private func keyCode(_ usage: Int) -> CGKeyCode? {
    guard usage >> 16 == 7 else { return nil }
    let key = usage & 0xffff
    if (4...29).contains(key) { return letters[key - 4] }
    if (0x1e...0x27).contains(key) { return digits[key - 0x1e] }
    return special[key]
  }
  private func point(_ args: [String: Any], _ display: CGDirectDisplayID) -> CGPoint? {
    guard let x = args["x"] as? Double, let y = args["y"] as? Double,
          x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else { return nil }
    let r = CGDisplayBounds(display)
    return CGPoint(x: r.minX + x * max(0, r.width - 1), y: r.minY + y * max(0, r.height - 1))
  }
  func apply(_ args: [String: Any], display: CGDirectDisplayID) -> Bool {
    switch args["type"] as? String {
    case "release": releaseAll(); return true
    case "pointer":
      guard let p = point(args, display) else { return false }
      let type: CGEventType = buttons.contains("left") ? .leftMouseDragged : buttons.contains("right") ? .rightMouseDragged : buttons.contains("middle") ? .otherMouseDragged : .mouseMoved
      let button: CGMouseButton = buttons.contains("right") ? .right : buttons.contains("middle") ? .center : .left
      guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return false }
      event.flags = flags; event.post(tap: .cghidEventTap); return true
    case "button":
      guard let p = point(args, display), let name = args["button"] as? String,
            let down = args["down"] as? Bool, ["left", "right", "middle"].contains(name) else { return false }
      let button: CGMouseButton = name == "left" ? .left : name == "right" ? .right : .center
      let type: CGEventType = name == "left" ? (down ? .leftMouseDown : .leftMouseUp) : name == "right" ? (down ? .rightMouseDown : .rightMouseUp) : (down ? .otherMouseDown : .otherMouseUp)
      guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return false }
      if down {
        let now = ProcessInfo.processInfo.systemUptime
        let close = hypot(p.x - lastClickPoint.x, p.y - lastClickPoint.y) < 4
        clickCount = close && now - lastClickAt < NSEvent.doubleClickInterval ? min(clickCount + 1, 3) : 1
        lastClickAt = now; lastClickPoint = p; buttons.insert(name)
      } else { buttons.remove(name) }
      event.setIntegerValueField(.mouseEventClickState, value: max(1, clickCount))
      event.flags = flags; event.post(tap: .cghidEventTap); return true
    case "wheel":
      guard let dx = args["dx"] as? Double, let dy = args["dy"] as? Double,
            dx.isFinite, dy.isFinite, abs(dx) <= 2400, abs(dy) <= 2400,
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
              wheel1: -Int32(dy), wheel2: -Int32(dx), wheel3: 0) else { return false }
      event.flags = flags; event.post(tap: .cghidEventTap); return true
    case "key":
      guard let usage = args["usage"] as? Int, let down = args["down"] as? Bool,
            let code = keyCode(usage), let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { return false }
      let repeatKey = down && keys.contains(code)
      if down { keys.insert(code) } else { keys.remove(code) }
      if (0xe0...0xe7).contains(usage & 0xffff) { event.type = .flagsChanged }
      event.flags = flags
      if repeatKey { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
      event.post(tap: .cghidEventTap); return true
    case "text":
      guard let text = args["text"] as? String, !text.isEmpty, text.utf16.count <= 1024,
            !text.contains("\0"), text.allSatisfy({ String($0).utf16.count <= 20 }) else { return false }
      var chunk: [UniChar] = []
      func post() {
        guard !chunk.isEmpty else { return }
        for down in [true, false] {
          if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) {
            chunk.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: $0.baseAddress) }
            event.post(tap: .cghidEventTap)
          }
        }
        chunk.removeAll(keepingCapacity: true)
      }
      for character in text {
        let units = Array(String(character).utf16)
        if chunk.count + units.count > 20 { post() }
        chunk.append(contentsOf: units)
      }
      post(); return true
    default: return false
    }
  }
  func releaseAll() {
    let held = keys.sorted { a, b in
      let modifiers: Set<CGKeyCode> = [59,62,56,60,58,61,55,54]
      return !modifiers.contains(a) && modifiers.contains(b)
    }
    for code in held {
      keys.remove(code)
      if let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) {
        if [59,62,56,60,58,61,55,54].contains(code) { event.type = .flagsChanged }
        event.flags = flags; event.post(tap: .cghidEventTap)
      }
    }
    keys.removeAll()
    let location = CGEvent(source: nil)?.location ?? .zero
    for button in buttons {
      let mouse: CGMouseButton = button == "left" ? .left : button == "right" ? .right : .center
      let type: CGEventType = button == "left" ? .leftMouseUp : button == "right" ? .rightMouseUp : .otherMouseUp
      CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: mouse)?.post(tap: .cghidEventTap)
    }
    buttons.removeAll()
  }
}
