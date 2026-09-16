import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var graceTaskId = UIBackgroundTaskIdentifier.invalid

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerBackgroundGraceChannel(
      messenger: engineBridge.applicationRegistrar.messenger())
  }

  /// `beginBackgroundTask` assertion channel: when the app is backgrounded iOS
  /// suspends the process after a few seconds, killing the pairing mirror's
  /// keep-alive pings. A background task assertion stretches the window to
  /// ~30s, covering brief switches away without any UIBackgroundModes
  /// entitlement. The task id lives here (not Dart) so an assertion that
  /// expired while backgrounded is never re-ended with a recycled id.
  /// Platform-channel handlers run on the main thread, so UIApplication state
  /// can be touched directly.
  private func registerBackgroundGraceChannel(
    messenger: FlutterBinaryMessenger
  ) {
    let channel = FlutterMethodChannel(
      name: "teampilot/background_grace",
      binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleBackgroundGraceCall(call, result: result)
    }
  }

  private func handleBackgroundGraceCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "beginBackgroundTask":
      if graceTaskId != UIBackgroundTaskIdentifier.invalid {
        result(1)
        return
      }
      let taskId = UIApplication.shared.beginBackgroundTask(
        withName: "pairing-mirror-grace"
      ) { [weak self] in
        // Expiration handler: the runtime revoked the remaining time. Ending
        // the task here is mandatory or the app is killed for holding it. The
        // handler may not run on the main thread; hop back to serialize id
        // access with the channel handlers.
        DispatchQueue.main.async { self?.endGraceTask() }
      }
      graceTaskId = taskId
      result(taskId == UIBackgroundTaskIdentifier.invalid ? -1 : 1)
    case "endBackgroundTask":
      endGraceTask()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func endGraceTask() {
    guard graceTaskId != UIBackgroundTaskIdentifier.invalid else { return }
    UIApplication.shared.endBackgroundTask(graceTaskId)
    graceTaskId = UIBackgroundTaskIdentifier.invalid
  }
}
