// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionNotificationCenter.swift
//  Nook
//
//  The Mac's notification center for `ExtensionCompatNotifications`, and the app's notification delegate.
//

import Foundation
@preconcurrency import UserNotifications

@MainActor
final class ExtensionNotificationCenter: NSObject, ExtensionCompatNotificationCenter, UNUserNotificationCenterDelegate {
    weak var api: ExtensionCompatNotifications?
    private let center = UNUserNotificationCenter.current()
    /// One category per set of button titles: the Mac takes buttons from a category, not from a notification.
    private var categories: [String: UNNotificationCategory] = [:]

    func allowed(asking: Bool, _ done: @escaping (Bool) -> Void) {
        center.getNotificationSettings { [center] settings in
            let status = settings.authorizationStatus
            guard status == .notDetermined, asking else {
                return DispatchQueue.main.async { done(status != .denied) }
            }
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                DispatchQueue.main.async { done(granted) }
            }
        }
    }

    func show(_ notification: ExtensionCompatNotification, _ done: @escaping (Bool) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.subtitle = notification.subtitle
        content.body = notification.body
        if !notification.silent { content.sound = .default }
        content.categoryIdentifier = category(for: notification.buttons)
        center.add(UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil)) { error in
            DispatchQueue.main.async { done(error == nil) }
        }
    }

    func remove(_ identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func delivered(_ done: @escaping ([String]) -> Void) {
        center.getDeliveredNotifications { notifications in
            let identifiers = notifications.map(\.request.identifier)
            DispatchQueue.main.async { done(identifiers) }
        }
    }

    /// Every category reports a dismissal, which is how `onClosed` hears of one.
    private func category(for buttons: [String]) -> String {
        let identifier = ExtensionCompatNotifications.prefix + "." + buttons.joined(separator: "\u{1F}")
        guard categories[identifier] == nil else { return identifier }
        // ponytail: categories are never retired one by one. Past 64 the set starts over, and older notifications lose their buttons.
        if categories.count >= 64 { categories = [:] }
        let actions = buttons.enumerated().map {
            UNNotificationAction(identifier: "button.\($0.offset)", title: $0.element, options: [.foreground])
        }
        categories[identifier] = UNNotificationCategory(
            identifier: identifier, actions: actions, intentIdentifiers: [], options: [.customDismissAction])
        center.setNotificationCategories(Set(categories.values))
        return identifier
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// An extension's notification shows while Nook is in front. Nook's own stay as they were without a delegate.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let ours = notification.request.identifier.hasPrefix(ExtensionCompatNotifications.prefix + "\n")
        completionHandler(ours ? [.banner, .list, .sound] : [])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier, action = response.actionIdentifier
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                switch action {
                case UNNotificationDefaultActionIdentifier: self.api?.responded(to: identifier, .clicked)
                case UNNotificationDismissActionIdentifier: self.api?.responded(to: identifier, .dismissed)
                default:
                    if action.hasPrefix("button."), let index = Int(action.dropFirst(7)) {
                        self.api?.responded(to: identifier, .button(index))
                    }
                }
            }
            completionHandler()
        }
    }
}
