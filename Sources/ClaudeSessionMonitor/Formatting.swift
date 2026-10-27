import Foundation

enum Formatting {
    static let locale = Locale(identifier: "es_ES")

    /// "Se reinicia en 2 h 58 min · hoy 10:09", "Se reinicia en 4 d 1 h · vie 31 oct, 9:59"…
    static func resetDescription(for date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let remaining = date.timeIntervalSince(now)
        if remaining <= 0 { return "Reiniciado" }

        let calendar = Calendar.current
        let time = date.formatted(.dateTime.hour().minute().locale(locale))
        let when: String
        if calendar.isDateInToday(date) {
            when = "hoy \(time)"
        } else if calendar.isDateInTomorrow(date) {
            when = "mañana \(time)"
        } else {
            when = "\(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))), \(time)"
        }
        return "Se reinicia en \(duration(remaining)) · \(when)"
    }

    /// Versión corta para el resumen: "hoy 8:57", "mañana 14:21", "sáb 10:00".
    static func shortReset(_ date: Date?, now: Date) -> String {
        guard let date else { return "" }
        if date <= now { return "reiniciado" }
        let calendar = Calendar.current
        let time = date.formatted(.dateTime.hour().minute().locale(locale))
        if calendar.isDateInToday(date) { return "hoy \(time)" }
        if calendar.isDateInTomorrow(date) { return "mañana \(time)" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).locale(locale))) \(time)"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let mins = minutes % 60
        if days > 0 { return hours > 0 ? "\(days) d \(hours) h" : "\(days) d" }
        if hours > 0 { return mins > 0 ? "\(hours) h \(mins) min" : "\(hours) h" }
        return "\(mins) min"
    }

    static func updatedDescription(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "Actualizado ahora" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        return "Actualizado \(formatter.localizedString(for: date, relativeTo: now))"
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded())) %"
    }
}
