import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    func requestAuthorization() {
        Task {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func postDrinkReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Time to drink water!"
        content.body = "Stay hydrated — take a sip or log a bottle."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "drink-reminder-\(UUID().uuidString)",
            content: content,
            trigger: nil // Fire immediately
        )

        Task {
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}
