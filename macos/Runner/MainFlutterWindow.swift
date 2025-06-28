import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
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
    self.setFrameAutosaveName("Main Window")
    
    // Window appearance settings
    self.titlebarAppearsTransparent = false
    self.titleVisibility = .visible
    self.title = "Quick Cap"
    self.isMovableByWindowBackground = false
    
    // Set minimum window size to prevent UI breaking
    self.minSize = NSSize(width: 1200, height: 800)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
