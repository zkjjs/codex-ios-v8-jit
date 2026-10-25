import UserNotifications

enum TransferNotifications {
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
    static func completed(_ record: TransferRecord) {
        let content = UNMutableNotificationContent()
        content.title = "下载完成"
        content.body = record.name
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: record.id.uuidString, content: content, trigger: nil))
    }
}
