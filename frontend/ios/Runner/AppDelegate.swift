import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register the expiry-cleanup task with BGTaskScheduler (§15).
    //
    // iOS gives no guarantee about when — or whether — this runs; the system
    // decides based on usage patterns and battery state. That is precisely
    // why the Dart side also runs cleanup on launch, on resume, before showing
    // the temporary-contact list, and when temporary contacts are saved.
    // Both handler kinds are registered because the Dart side may schedule
    // either: registerPeriodicTask maps to a BGAppRefreshTask, and the
    // one-off cleanup request maps to a BGProcessingTask.
    WorkmanagerPlugin.registerBGProcessingTask(
      withIdentifier: "contact_scanner.expiry_cleanup"
    )
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "contact_scanner.expiry_cleanup",
      earliestBeginInSeconds: 15 * 60
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
