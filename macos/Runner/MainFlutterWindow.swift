import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let enforcedMinContentSize = NSSize(width: 1280, height: 800)

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

    super.awakeFromNib()
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
