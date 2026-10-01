import DrypCore
import Foundation
import UserNotifications

/// Banners posted as dryp through the notification center, with an "Extend 1 hr" action on warnings.
final class UserNotifier: NSObject, Notifier, UNUserNotificationCenterDelegate {
    static let warningCategory = "dryp.warning"
    static let extendAction = "dryp.extend"

    var onExtend: ((Mode) -> Void)?
    private let log: (String) -> Void
    // The notification center traps outside an app bundle (`swift run`), so a dev run uses the osascript fallback.
    private let center: UNUserNotificationCenter? =
        Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil

    init(log: @escaping (String) -> Void) {
        self.log = log
        super.init()
        guard let center else { return }
        center.delegate = self
        let extend = UNNotificationAction(identifier: Self.extendAction, title: "Extend 1 hr", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.warningCategory, actions: [extend], intentIdentifiers: [], options: []),
        ])
    }

    /// Call at launch, so the permission prompt appears right after install rather than mid-session.
    func requestAuthorization() {
        guard let center else { return }
        center.getNotificationSettings { [center, log] settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            // Alerts only: dryp never plays a sound, so it doesn't ask to.
            center.requestAuthorization(options: [.alert]) { granted, error in
                if let error {
                    log("notifications unavailable (\(error.localizedDescription)); using osascript")
                } else {
                    log(granted ? "notifications: allowed" : "notifications: declined")
                }
            }
        }
    }

    func post(_ notice: Notice) {
        let (title, body) = Self.text(notice)
        guard let center else {
            postViaScript(title, body)
            return
        }
        let send = { [center, log] in
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            var identifier = "dryp.\(UUID().uuidString)"
            if case .warning(let mode) = notice {
                content.categoryIdentifier = Self.warningCategory
                content.userInfo = ["mode": mode.rawValue]
                identifier = "dryp.warning.\(mode.rawValue)"
            }
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
                if let error {
                    log("notification failed (\(error.localizedDescription)); using osascript")
                    DispatchQueue.main.async { postViaScript(title, body) }
                }
            }
        }
        center.getNotificationSettings { [center] settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                send()
            case .notDetermined:
                center.requestAuthorization(options: [.alert]) { granted, error in
                    if granted { send() } else if error != nil { DispatchQueue.main.async { postViaScript(title, body) } }
                }
            case .denied:
                break   // The user's choice in System Settings; don't route around it.
            @unknown default:
                DispatchQueue.main.async { postViaScript(title, body) }
            }
        }
    }

    static func text(_ notice: Notice) -> (title: String, body: String) {
        switch notice {
        case .warning(let mode): return (NoticeText.warning(mode), "")
        case .ended(let ending): return (NoticeText.ended(ending), "")
        case .foreignSleepDisabled: return (NoticeText.foreignTitle, NoticeText.foreignBody)
        case .restoreFailed: return (NoticeText.restoreFailedTitle, NoticeText.restoreFailedBody)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == Self.extendAction,
           let raw = response.notification.request.content.userInfo["mode"] as? String,
           let mode = Mode(rawValue: raw) {
            DispatchQueue.main.async { self.onExtend?(mode) }
        }
        completionHandler()
    }

    // dryp is an accessory app, so it is never "frontmost" — but without this the center would treat it as
    // foreground and suppress the banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}

/// Works without any permission, but the banner shows Script Editor's name and icon and has no Extend button.
func postViaScript(_ title: String, _ body: String) {
    func literal(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "") + "\"" }
    Shell.run("/usr/bin/osascript", ["-e", "display notification \(literal(body)) with title \(literal(title))"])
}
