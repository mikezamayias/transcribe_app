import UIKit
import dartnative_ios

@main
@objc class AppDelegate: DartNativeAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    ScribeClient.purgeStaleTempFiles()
    return result
  }

  override func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    ScribeClient.handleEventsForBackgroundURLSession(identifier: identifier, completionHandler: completionHandler)
  }
}
