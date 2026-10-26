import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  // ⌘Q goes through the window's close button, so the app can ask first while
  // agents work (window_manager's prevent-close). Once the window is closed
  // the app quits for real.
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if let window = mainFlutterWindow, window.isVisible || window.isMiniaturized {
      window.performClose(nil)
      return .terminateCancel
    }
    return .terminateNow
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
