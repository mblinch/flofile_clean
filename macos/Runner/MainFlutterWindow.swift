import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let enforcedMinContentSize = NSSize(width: 1280, height: 800)
  private static var jerseyChannel: FlutterMethodChannel?
  private var jerseyMonitor: Any?
  static var jerseyShortcutsEnabled = true

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    
    // Set specific window size for the app
    let windowSize = NSSize(width: 1400, height: 900)
    let screenSize = NSScreen.main?.frame.size ?? NSSize(width: 1920, height: 1080)
    let windowOrigin = NSPoint(
      x: (screenSize.width - windowSize.width) / 2,
      y: (screenSize.height - windowSize.height) / 2
    )
    
    self.setFrame(NSRect(origin: windowOrigin, size: windowSize), display: true)
    
    // Window appearance settings
    self.titlebarAppearsTransparent = false
    self.titleVisibility = .visible
    self.title = "Quick Cap"
    self.isMovableByWindowBackground = false
    
    // Enforce minimum supported resolution for the app UI.
    // Convert a 1280x800 content rect into frame size so title bar/chrome are
    // accounted for and the actual Flutter content never drops below 1280x800.
    self.contentMinSize = enforcedMinContentSize
    let minFrame = self.frameRect(
      forContentRect: NSRect(origin: .zero, size: enforcedMinContentSize)
    )
    self.minSize = minFrame.size
    _enforceMinimumFrameNow(minFrame.size)

    RegisterGeneratedPlugins(registry: flutterViewController)

    ColorManagedPreviewPlugin.register(
      with: flutterViewController.registrar(forPlugin: "ColorManagedPreviewPlugin"))

    _installJerseyShortcutChannel(flutterViewController)
    _installJerseyEventMonitor()

    super.awakeFromNib()
  }

  private func _installJerseyShortcutChannel(_ flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "caption_writer/jersey_shortcuts",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    MainFlutterWindow.jerseyChannel = channel
    channel.setMethodCallHandler { call, result in
      if call.method == "setEnabled" {
        MainFlutterWindow.jerseyShortcutsEnabled = (call.arguments as? Bool) ?? true
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func _installJerseyEventMonitor() {
    // The returned token must be retained, otherwise the monitor is removed.
    jerseyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
      if MainFlutterWindow.consumeOptionDigit(event) { return nil }
      return event
    }
  }

  /// Swallow modifier+digit before AppKit can beep or insert ¡™£ / !@#.
  /// Ctrl = home jersey, Cmd or Option = away jersey, Shift = verb number.
  @discardableResult
  static func consumeOptionDigit(_ event: NSEvent) -> Bool {
    guard jerseyShortcutsEnabled else { return false }
    guard event.type == .keyDown else { return false }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let option = flags.contains(.option)
    let control = flags.contains(.control)
    let command = flags.contains(.command)
    let shift = flags.contains(.shift)
    guard let digit = digitFromEvent(event) else { return false }

    // Shift+# (alone) → verb by assigned number in current category.
    if shift && !option && !control && !command {
      // Swallow repeats so holding the key doesn't toggle the verb.
      if event.isARepeat { return true }
      jerseyChannel?.invokeMethod("verbDigit", arguments: ["digit": digit])
      return true
    }

    // Exactly one of option/control/command → jersey shortcut.
    guard [option, control, command].filter({ $0 }).count == 1 else { return false }
    if event.isARepeat { return true }
    jerseyChannel?.invokeMethod(
      "jerseyDigit",
      arguments: ["digit": digit, "isHome": control]
    )
    return true
  }

  private static func digitFromEvent(_ event: NSEvent) -> String? {
    if let chars = event.charactersIgnoringModifiers {
      let trimmed = chars.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.count == 1, let ch = trimmed.first, ch >= "0", ch <= "9" {
        return String(ch)
      }
    }
    switch event.keyCode {
    case 29, 82: return "0"
    case 18, 83: return "1"
    case 19, 84: return "2"
    case 20, 85: return "3"
    case 21, 86: return "4"
    case 23, 87: return "5"
    case 22, 88: return "6"
    case 26, 89: return "7"
    case 28, 91: return "8"
    case 25, 92: return "9"
    default: return nil
    }
  }

  override func sendEvent(_ event: NSEvent) {
    if MainFlutterWindow.consumeOptionDigit(event) { return }
    super.sendEvent(event)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if MainFlutterWindow.consumeOptionDigit(event) { return true }
    return super.performKeyEquivalent(with: event)
  }

  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    var constrained = super.constrainFrameRect(frameRect, to: screen)
    let minFrame = self.frameRect(
      forContentRect: NSRect(origin: .zero, size: enforcedMinContentSize)
    ).size
    constrained.size.width = max(constrained.size.width, minFrame.width)
    constrained.size.height = max(constrained.size.height, minFrame.height)
    return constrained
  }

  private func _enforceMinimumFrameNow(_ minFrameSize: NSSize) {
    var current = self.frame
    let targetWidth = max(current.size.width, minFrameSize.width)
    let targetHeight = max(current.size.height, minFrameSize.height)
    guard targetWidth != current.size.width || targetHeight != current.size.height else {
      return
    }
    current.origin.y -= (targetHeight - current.size.height)
    current.size.width = targetWidth
    current.size.height = targetHeight
    self.setFrame(current, display: true)
  }
}
