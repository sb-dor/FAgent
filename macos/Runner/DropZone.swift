import Cocoa
import FlutterMacOS

/// The window's drop zone: a transparent view over the Flutter view that takes files dragged onto
/// the window and reports the drag to Dart over the `flutter_code_agent/drop_zone` event channel
/// (`lib/src/common/drop_zone/`).
///
/// Events are `{type: enter|over|leave|drop, dx, dy}` in points from the top-left corner of the
/// Flutter view; a drop adds `paths` (absolute, in drop order) and `failed` (items that could not
/// be received). A drop sends no `leave`: the order is enter, over…, drop.
///
/// It takes file URLs (Finder), file promises (Safari, Photos, Mail) and image data (`.png`,
/// `.tiff`). Promised files and image data are saved under
/// `NSTemporaryDirectory()/flutter_code_agent/drops/<uuid>/` (image data as `.png`), and the drop
/// is sent once every promise has arrived or failed.
///
/// `hitTest` returns nil, so clicks, scrolls and hovers go through to the Flutter view; AppKit
/// finds drag destinations by their registered types.
final class DropZoneView: NSView, FlutterStreamHandler {
  static let channelName = "flutter_code_agent/drop_zone"

  /// How long a drop waits for its promised files before the missing ones count as failed.
  private static let promiseTimeout: DispatchTimeInterval = .seconds(30)

  private var sink: FlutterEventSink?

  /// A drag is over the view: entered and neither left nor dropped yet.
  private var dragging = false

  /// The last position sent, so a drag that does not move sends nothing more.
  private var lastPoint: NSPoint?

  private lazy var promiseQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.qualityOfService = .userInitiated
    return queue
  }()

  /// Puts a drop zone over the view of [controller] and opens its event channel.
  @discardableResult
  static func install(on controller: FlutterViewController) -> DropZoneView {
    let view = DropZoneView(frame: controller.view.bounds)
    view.autoresizingMask = [.width, .height]
    controller.view.addSubview(view, positioned: .above, relativeTo: nil)
    FlutterEventChannel(name: channelName, binaryMessenger: controller.engine.binaryMessenger)
      .setStreamHandler(view)
    return view
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    registerForDraggedTypes(
      [.fileURL, .png, .tiff]
        + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  // MARK: FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  // MARK: NSDraggingDestination

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    dragging = true
    lastPoint = nil
    send("enter", at: sender.draggingLocation)
    return .copy
  }

  override func wantsPeriodicDraggingUpdates() -> Bool { false }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    if sender.draggingLocation != lastPoint { send("over", at: sender.draggingLocation) }
    return .copy
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    leave(at: sender?.draggingLocation)
  }

  /// A drag cancelled over the view; after a drop [dragging] is already false.
  override func draggingEnded(_ sender: NSDraggingInfo) {
    leave(at: sender.draggingLocation)
  }

  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    dragging = false
    let point = topLeft(sender.draggingLocation)
    let collector = DropCollector()
    let group = DispatchGroup()
    var destination: URL?
    func folder() throws -> URL {
      if let destination { return destination }
      let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("flutter_code_agent/drops/\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      destination = url
      return url
    }
    var images = 0

    // One slot per dragged item, in drop order; the first class an item can be read as wins.
    sender.enumerateDraggingItems(
      options: [],
      for: nil,
      classes: [NSURL.self, NSFilePromiseReceiver.self, NSPasteboardItem.self],
      searchOptions: [.urlReadingFileURLsOnly: true]
    ) { draggingItem, _, _ in
      switch draggingItem.item {
      case let url as URL:
        let path = ((url as NSURL).filePathURL ?? url).path
        collector.add(path.isEmpty ? nil : [path])
      case let receiver as NSFilePromiseReceiver:
        guard let destination = try? folder() else {
          collector.add(nil)
          return
        }
        let expected = max(receiver.fileNames.count, 1)
        let slot = collector.addPending(expected)
        for _ in 0..<expected { group.enter() }
        receiver.receivePromisedFiles(
          atDestination: destination, options: [:], operationQueue: self.promiseQueue
        ) { url, error in
          if collector.receive(slot, path: error == nil ? url.path : nil) { group.leave() }
        }
      case let item as NSPasteboardItem:
        images += 1
        collector.add(Self.writeImage(item, index: images, folder: folder).map { [$0] })
      default:
        collector.add(nil)
      }
    }

    DispatchQueue.global(qos: .userInitiated).async {
      _ = group.wait(timeout: .now() + Self.promiseTimeout)
      let (paths, failed, outstanding) = collector.finish()
      // A group released with enters left over traps; late readers no longer leave.
      for _ in 0..<outstanding { group.leave() }
      DispatchQueue.main.async {
        self.sink?([
          "type": "drop", "dx": Double(point.x), "dy": Double(point.y), "paths": paths,
          "failed": failed,
        ])
      }
    }
    return true
  }

  // MARK: Helpers

  private func leave(at location: NSPoint?) {
    guard dragging else { return }
    dragging = false
    send("leave", at: location ?? lastPoint ?? .zero)
  }

  private func send(_ type: String, at location: NSPoint) {
    lastPoint = location
    let point = topLeft(location)
    sink?(["type": type, "dx": Double(point.x), "dy": Double(point.y)])
  }

  /// [location] (window coordinates, bottom-left origin) in points from the view's top-left corner.
  private func topLeft(_ location: NSPoint) -> NSPoint {
    let local = convert(location, from: nil)
    return NSPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)
  }

  /// Saves the PNG or TIFF data of [item] as a PNG in the drop's folder; nil when it has neither
  /// or cannot be saved.
  private static func writeImage(_ item: NSPasteboardItem, index: Int, folder: () throws -> URL)
    -> String?
  {
    let png: Data?
    if let data = item.data(forType: .png) {
      png = data
    } else if let tiff = item.data(forType: .tiff) {
      png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    } else {
      png = nil
    }
    guard let png, let url = try? folder().appendingPathComponent("image-\(index).png") else {
      return nil
    }
    do {
      try png.write(to: url)
      return url.path
    } catch {
      return nil
    }
  }
}

/// The paths of one drop, slot by slot in drop order; promise readers fill theirs from another
/// queue.
private final class DropCollector {
  private struct Slot {
    var paths: [String] = []
    var pending = 0
    var failed = 0
  }

  private let lock = NSLock()
  private var slots: [Slot] = []
  private var finished = false

  /// A slot that is already known: its paths, or nil for an item that failed.
  func add(_ paths: [String]?) {
    lock.lock()
    defer { lock.unlock() }
    slots.append(paths.map { Slot(paths: $0) } ?? Slot(failed: 1))
  }

  /// A slot that waits for [count] promised files; returns its index.
  func addPending(_ count: Int) -> Int {
    lock.lock()
    defer { lock.unlock() }
    slots.append(Slot(pending: count))
    return slots.count - 1
  }

  /// One promised file of [slot] arrived ([path]) or failed (nil). Returns whether it was awaited,
  /// so the caller leaves the dispatch group once per awaited file.
  func receive(_ slot: Int, path: String?) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !finished, slots[slot].pending > 0 else { return false }
    slots[slot].pending -= 1
    if let path { slots[slot].paths.append(path) } else { slots[slot].failed += 1 }
    return true
  }

  /// The paths in drop order, how many items failed, and how many promised files are still
  /// missing (counted as failed too; the ones that arrive later are ignored).
  func finish() -> ([String], Int, Int) {
    lock.lock()
    defer { lock.unlock() }
    finished = true
    let outstanding = slots.reduce(0) { $0 + $1.pending }
    return (
      slots.flatMap { $0.paths },
      slots.reduce(0) { $0 + $1.failed } + outstanding,
      outstanding
    )
  }
}
