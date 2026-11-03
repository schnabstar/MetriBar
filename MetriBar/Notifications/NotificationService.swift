import Foundation
import MetriBarKit
import Observation
import UserNotifications

/// Shows `AlertNotice`s as macOS notifications and reports clicks on them.
///
/// Notifications are local: nothing is sent to a server. The permission is
/// asked for when the user turns notifications on, never at launch. The
/// system notification center is only touched after `activate()`, so tools
/// that create a model without notifications do not need an app bundle.
@MainActor
@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    enum Authorization {
        /// Not asked about yet.
        case unknown
        case notDetermined
        case denied
        case allowed
    }

    private(set) var authorization = Authorization.unknown

    /// Called when the user clicks a notification; the server, if it is known.
    @ObservationIgnored var onOpenServer: ((UUID?) -> Void)?
    @ObservationIgnored private var isActive = false

    /// Becomes the delegate of the notification center, which has to happen
    /// at launch to receive clicks on notifications.
    func activate() {
        guard !isActive else { return }
        isActive = true
        UNUserNotificationCenter.current().delegate = self
        Task { await refresh() }
    }

    func refresh() async {
        guard isActive else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization =
            switch settings.authorizationStatus {
            case .notDetermined: .notDetermined
            case .denied: .denied
            default: .allowed
            }
    }

    /// Asks the system for permission; the system asks the user only once.
    func requestAuthorization() async {
        guard isActive else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refresh()
    }

    func post(_ notices: [AlertNotice]) {
        guard isActive else { return }
        for notice in notices {
            send(
                identifier: notice.id, title: NoticeText.title(notice), body: NoticeText.body(notice),
                serverID: notice.serverID, urgent: notice.condition.level >= .critical || notice.event == .offline)
        }
    }

    func postTest() {
        guard isActive else { return }
        send(
            identifier: "test", title: String(localized: "MetriBar"),
            body: String(localized: "This is a test notification."), serverID: nil, urgent: false)
    }

    private func send(identifier: String, title: String, body: String, serverID: UUID?, urgent: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = urgent ? .default : nil
        content.threadIdentifier = serverID?.uuidString ?? "metribar"
        if let serverID { content.userInfo = ["serverID": serverID.uuidString] }
        // The same identifier replaces an older notice about the same thing.
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banners also while MetriBar's own windows are in front.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let serverID = (response.notification.request.content.userInfo["serverID"] as? String)
            .flatMap(UUID.init(uuidString:))
        await MainActor.run { onOpenServer?(serverID) }
    }
}
