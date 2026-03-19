import UIKit
import Flutter
import GoogleMaps

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Baca Maps API key dari Keys.plist (copy dari Keys.plist.example, JANGAN commit Keys.plist!)
    let mapsKey: String
    if let path = Bundle.main.path(forResource: "Keys", ofType: "plist"),
       let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
       let key = dict["MAPS_API_KEY"] as? String, !key.isEmpty, !key.contains("YOUR_") {
      mapsKey = key
    } else {
      mapsKey = "" // Akan error di Maps; pastikan Keys.plist ada dengan MAPS_API_KEY
    }
    GMSServices.provideAPIKey(mapsKey)
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}