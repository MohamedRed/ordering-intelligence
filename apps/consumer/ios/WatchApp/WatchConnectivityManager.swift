import Foundation
import WatchConnectivity

final class WatchConnectivityManager: NSObject, WCSessionDelegate {
  static let shared = WatchConnectivityManager()

  private override init() {
    super.init()
    activate()
  }

  private func activate() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    session.activate()
  }

  func sendHandoffLink(_ link: String) {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    if session.isReachable {
      session.sendMessage(["handoffLink": link], replyHandler: nil, errorHandler: nil)
    } else {
      session.transferUserInfo(["handoffLink": link])
    }
  }

  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
}
