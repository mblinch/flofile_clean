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
