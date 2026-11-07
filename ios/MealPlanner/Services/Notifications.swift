import Foundation
import UserNotifications
import MealCore

enum Notifications {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Напоминания: приготовление блюда в заданный час и истечение срока годности запасов.
    static func reschedule(state: AppState, library: Library) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard state.reminders.cookingEnabled || state.reminders.expiryEnabled else { return }
        let cal = Calendar.current
        if state.reminders.cookingEnabled, let plan = state.currentPlan {
            for m in plan.meals where m.day < 14 && !state.doneMeals.contains(m.id) {
                guard let day = cal.date(byAdding: .day, value: m.day, to: cal.startOfDay(for: plan.settings.startDate)),
                      let fire = cal.date(bySettingHour: state.reminders.cookingHour, minute: 0, second: 0, of: day), fire > Date(), m.slot == 0 || m.type == .dinner else { continue }
                let c = UNMutableNotificationContent()
                c.title = "Пора готовить: \(m.slotName)"
                c.body = m.recipeName
                let trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
                try? await center.add(UNNotificationRequest(identifier: "cook-\(m.id)", content: c, trigger: trigger))
            }
        }
        if state.reminders.expiryEnabled {
            for item in state.pantry {
                guard let exp = item.expiry, let fire = cal.date(byAdding: .day, value: -1, to: exp), fire > Date() else { continue }
                let c = UNMutableNotificationContent()
                c.title = "Скоро истекает срок годности"
                c.body = library.ingredients[item.ingredientKey]?.name ?? "Продукт"
                let t = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour], from: cal.date(bySettingHour: 10, minute: 0, second: 0, of: fire) ?? fire), repeats: false)
                try? await center.add(UNNotificationRequest(identifier: "exp-\(item.id)", content: c, trigger: t))
            }
        }
    }
}
