import Foundation

final class WatchSessionStore {
  private let defaults: UserDefaults

  init() {
    if let suiteName = Bundle.main.object(forInfoDictionaryKey: "ConsumerAppGroup") as? String,
       !suiteName.isEmpty,
       let suiteDefaults = UserDefaults(suiteName: suiteName) {
      self.defaults = suiteDefaults
    } else {
      self.defaults = .standard
    }
  }

  func sessionId() -> String? {
    let sessionId = defaults.string(forKey: "sessionId") ?? ""
    return sessionId.isEmpty ? nil : sessionId
  }
}
