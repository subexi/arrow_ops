import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let iCloudChannelName = "arrow_ops/icloud"
  private var iCloudChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    if let screenFrame = self.screen?.visibleFrame {
      let targetWidth = max(screenFrame.width - 24, 0)
      let targetHeight = max(screenFrame.height - 24, 0)
      let targetFrame = NSRect(
        x: screenFrame.midX - (targetWidth / 2),
        y: screenFrame.midY - (targetHeight / 2),
        width: targetWidth,
        height: targetHeight
      )

      self.setFrame(targetFrame, display: true)
      self.minSize = NSSize(width: 760, height: 560)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerICloudChannel(flutterViewController: flutterViewController)

    super.awakeFromNib()
  }

  private func registerICloudChannel(flutterViewController: FlutterViewController) {
    iCloudChannel = FlutterMethodChannel(name: iCloudChannelName, binaryMessenger: flutterViewController.engine.binaryMessenger)
    iCloudChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }

      switch call.method {
      case "getICloudDocumentsPath":
        let args = call.arguments as? [String: Any]
        let containerId = args?["containerId"] as? String
        result(self.resolveICloudDocumentsPath(containerId: containerId))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func resolveICloudDocumentsPath(containerId: String?) -> String? {
    let identifier = (containerId?.isEmpty ?? true) ? nil : containerId
    guard let containerUrl = FileManager.default.url(forUbiquityContainerIdentifier: identifier) else {
      return nil
    }

    let docsUrl = containerUrl.appendingPathComponent("Documents", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: docsUrl, withIntermediateDirectories: true)
      return docsUrl.path
    } catch {
      return nil
    }
  }
}
