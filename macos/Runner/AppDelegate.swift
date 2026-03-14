import Cocoa
import FlutterMacOS
import Sparkle

@main
class AppDelegate: FlutterAppDelegate {
  private let updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
  )

  @IBAction func checkForUpdates(_ sender: Any?) {
    updaterController.checkForUpdates(sender)
  }

  @IBAction func openPreferences(_ sender: Any?) {
    guard let window = mainFlutterWindow as? MainFlutterWindow,
          let flutterVC = window.contentViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(
      name: "caption_writer/preferences",
      binaryMessenger: flutterVC.engine.binaryMessenger
    )
    channel.invokeMethod("openPreferences", arguments: nil)
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    // Check for updates shortly after launch so the window is up first
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.updaterController.checkForUpdates(nil)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
