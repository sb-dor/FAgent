import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// The window was closed (the app is quitting).
  private(set) var isClosed = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Answers to a quit request (see AppDelegate.applicationShouldTerminate).
    FlutterMethodChannel(
      name: "flutter_code_agent/app_close",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    ).setMethodCallHandler { call, result in
      let delegate = NSApp.delegate as? AppDelegate
      switch call.method {
      case "quit":
        result(nil)
        delegate?.quit()
      case "cancelQuit":
        delegate?.cancelQuit()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  override func close() {
    isClosed = true
    super.close()
    (NSApp.delegate as? AppDelegate)?.windowDidClose()
  }
}
