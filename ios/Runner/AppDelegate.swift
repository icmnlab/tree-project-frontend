import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 初始化 Google Maps SDK - 必須在使用任何 Google Maps 功能之前呼叫
    GMSServices.provideAPIKey("AIzaSyCme9JKEwMreEE_ZUwDcATTEwk6ow1g60U")
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
