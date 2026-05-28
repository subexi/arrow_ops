import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let iCloudChannelName = "arrow_ops/icloud"
  private var iCloudChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerICloudChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
  }

  private func registerICloudChannel(binaryMessenger: any FlutterBinaryMessenger) {
    iCloudChannel = FlutterMethodChannel(name: iCloudChannelName, binaryMessenger: binaryMessenger)
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
