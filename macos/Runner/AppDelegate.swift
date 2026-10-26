import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// A quit (⌘Q, the Dock, logout) is waiting for the app's answer: while
  /// agents work it asks the user first.
  private var terminationPending = false

  /// The app stopped its agents and may quit.
  private var quitConfirmed = false

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Every quit goes through the window's close button (window_manager's
  // prevent-close), shown to the user even when hidden or minimised. The app
  // answers with quit() or cancelQuit().
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !quitConfirmed, let window = mainFlutterWindow as? MainFlutterWindow, !window.isClosed
    else {
      return .terminateNow
    }
    terminationPending = true
    NSApp.unhide(nil)
    window.deminiaturize(nil)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window.performClose(nil)
    return .terminateLater
  }

  /// The agents are stopped: quit, answering a pending quit if there is one.
  func quit() {
    quitConfirmed = true
    if terminationPending {
      terminationPending = false
      NSApp.reply(toApplicationShouldTerminate: true)
    } else {
      NSApp.terminate(nil)
    }
  }

  /// The user kept the app open.
  func cancelQuit() {
    guard terminationPending else { return }
    terminationPending = false
    NSApp.reply(toApplicationShouldTerminate: false)
  }

  /// The window closed without asking (before the app intercepts closing).
  func windowDidClose() {
    guard terminationPending else { return }
    terminationPending = false
    NSApp.reply(toApplicationShouldTerminate: true)
  }
}
