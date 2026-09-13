import UIKit
import dartnative_ios

@objc class SceneDelegate: DartNativeSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let url = connectionOptions.urlContexts.first?.url {
      ScribeClient.handleOpenFile(at: url)
    }
  }

  @objc func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    if let url = URLContexts.first?.url {
      ScribeClient.handleOpenFile(at: url)
    }
  }
}
