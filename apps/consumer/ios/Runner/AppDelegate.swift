import Flutter
import UIKit
import WatchConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate, WCSessionDelegate {
  private let sessionChannelName = "com.orderingintelligence.consumer/session_bridge"
  private var watchSession: WCSession?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: sessionChannelName, binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterError(code: "unavailable", message: "App delegate unavailable", details: nil))
          return
        }
        switch call.method {
        case "saveSession":
          let args = call.arguments as? [String: Any] ?? [:]
          self.saveSession(args: args)
          result(true)
        case "saveHandoffLink":
          let args = call.arguments as? [String: Any] ?? [:]
          let link = args["link"] as? String ?? ""
          self.saveHandoffLink(link)
          result(true)
        case "clearSession":
          self.clearSession()
          result(true)
        case "loadSession":
          result(self.loadSession())
        case "loadHandoffLink":
          result(self.loadHandoffLink())
        case "clearHandoffLink":
          self.clearHandoffLink()
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    configureWatchConnectivity()
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func configureWatchConnectivity() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    session.activate()
    watchSession = session
  }

  private func sessionDefaults() -> UserDefaults {
    if let suiteName = Bundle.main.object(forInfoDictionaryKey: "ConsumerAppGroup") as? String,
       !suiteName.isEmpty,
       let defaults = UserDefaults(suiteName: suiteName) {
      return defaults
    }
    return UserDefaults.standard
  }

  private func saveSession(args: [String: Any]) {
    let defaults = sessionDefaults()
    defaults.set(args["sessionId"], forKey: "sessionId")
    defaults.set(args["customerId"], forKey: "customerId")
    defaults.set(args["tenantId"], forKey: "tenantId")
    defaults.set(args["accountId"], forKey: "accountId")
    defaults.set(args["userId"], forKey: "userId")
    defaults.set(args["displayName"], forKey: "displayName")
    defaults.set(args["storeId"], forKey: "storeId")
    defaults.set(args["storeName"], forKey: "storeName")
    defaults.set(args["businessType"], forKey: "businessType")
    defaults.set(args["currency"], forKey: "currency")
    defaults.set(args["fuelDefaultPrepayCents"], forKey: "fuelDefaultPrepayCents")
    defaults.set(args["fuelPreauthCapCents"], forKey: "fuelPreauthCapCents")
    defaults.set(Date().timeIntervalSince1970, forKey: "updatedAt")
  }

  private func clearSession() {
    let defaults = sessionDefaults()
    [
      "sessionId",
      "customerId",
      "tenantId",
      "accountId",
      "userId",
      "displayName",
      "storeId",
      "storeName",
      "businessType",
      "currency",
      "fuelDefaultPrepayCents",
      "fuelPreauthCapCents",
      "updatedAt"
    ].forEach { defaults.removeObject(forKey: $0) }
  }

  private func saveHandoffLink(_ link: String) {
    let defaults = sessionDefaults()
    if link.isEmpty {
      defaults.removeObject(forKey: "handoffLink")
      return
    }
    defaults.set(link, forKey: "handoffLink")
  }

  private func loadHandoffLink() -> String? {
    let defaults = sessionDefaults()
    let link = defaults.string(forKey: "handoffLink") ?? ""
    return link.isEmpty ? nil : link
  }

  private func clearHandoffLink() {
    let defaults = sessionDefaults()
    defaults.removeObject(forKey: "handoffLink")
  }

  private func loadSession() -> [String: Any]? {
    let defaults = sessionDefaults()
    guard let sessionId = defaults.string(forKey: "sessionId"), !sessionId.isEmpty else {
      return nil
    }
    return [
      "sessionId": sessionId,
      "customerId": defaults.string(forKey: "customerId") ?? "",
      "tenantId": defaults.string(forKey: "tenantId") ?? "",
      "accountId": defaults.string(forKey: "accountId") ?? "",
      "userId": defaults.string(forKey: "userId") ?? "",
      "displayName": defaults.string(forKey: "displayName") ?? "",
      "storeId": defaults.string(forKey: "storeId") ?? "",
      "storeName": defaults.string(forKey: "storeName") ?? "",
      "businessType": defaults.string(forKey: "businessType") ?? "",
      "currency": defaults.string(forKey: "currency") ?? "",
      "fuelDefaultPrepayCents": defaults.integer(forKey: "fuelDefaultPrepayCents"),
      "fuelPreauthCapCents": defaults.integer(forKey: "fuelPreauthCapCents"),
      "updatedAt": defaults.double(forKey: "updatedAt")
    ]
  }

  private func handleWatchPayload(_ payload: [String: Any]) {
    if let link = payload["handoffLink"] as? String, !link.isEmpty {
      saveHandoffLink(link)
    }
  }

  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    handleWatchPayload(message)
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    handleWatchPayload(userInfo)
  }
}
