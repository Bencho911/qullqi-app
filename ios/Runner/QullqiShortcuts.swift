import AppIntents
import Foundation

// Atajos de Qullqi para la app Atajos, Siri y Spotlight.
//
// Cómo hablan con la app de Flutter:
//  - Los que abren la app dejan la pantalla pedida en la clave
//    `flutter.pending_route` (el prefijo `flutter.` es el que usa el paquete
//    shared_preferences). Al abrirse, la app la lee, navega y la borra.
//  - "¿Cuánto puedo gastar?" no abre la app: lee la foto que la app dejó en
//    `flutter.widget_snapshot` y la responde en voz alta.
//
// Nada de esto toca tus cuentas ni sale del teléfono.

private enum QullqiPrefs {
    static let pendingRoute = "flutter.pending_route"
    static let snapshotKey = "flutter.widget_snapshot"

    static func setRoute(_ id: String) {
        UserDefaults.standard.set(id, forKey: pendingRoute)
    }

    static func loadSnapshot() -> [String: Any]? {
        guard
            let json = UserDefaults.standard.string(forKey: snapshotKey),
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        return object as? [String: Any]
    }

    /// 3208672 -> "3.208.672 pesos" (para que Siri lo diga bien).
    static func spoken(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.maximumFractionDigits = 0
        let body = formatter.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
        return (value < 0 ? "menos " : "") + body + " pesos"
    }
}

@available(iOS 16.0, *)
struct RegistrarGastoIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar un gasto"
    static var description = IntentDescription("Abre Qullqi para anotar un gasto.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        QullqiPrefs.setRoute("registrar-gasto")
        return .result()
    }
}

@available(iOS 16.0, *)
struct MoverPlataIntent: AppIntent {
    static var title: LocalizedStringResource = "Mover plata"
    static var description = IntentDescription("Abre Qullqi para mover plata entre tus cuentas.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        QullqiPrefs.setRoute("mover-plata")
        return .result()
    }
}

@available(iOS 16.0, *)
struct EscanearFacturaIntent: AppIntent {
    static var title: LocalizedStringResource = "Escanear una factura"
    static var description = IntentDescription("Abre Qullqi para escanear una factura.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        QullqiPrefs.setRoute("escanear-factura")
        return .result()
    }
}

@available(iOS 16.0, *)
struct ProximosPagosIntent: AppIntent {
    static var title: LocalizedStringResource = "Ver próximos pagos"
    static var description = IntentDescription("Abre Qullqi en lo que vence pronto.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        QullqiPrefs.setRoute("pagos")
        return .result()
    }
}

@available(iOS 16.0, *)
struct CuantoPuedoGastarIntent: AppIntent {
    static var title: LocalizedStringResource = "¿Cuánto puedo gastar?"
    static var description = IntentDescription(
        "Te dice lo que tienes disponible para gastar, sin abrir la app."
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snap = QullqiPrefs.loadSnapshot() else {
            return .result(dialog: "Abre Qullqi una vez para que pueda decirte tu disponible.")
        }
        if (snap["amountsHidden"] as? Bool) == true {
            return .result(dialog: "Ocultaste los montos. Abre Qullqi para verlos.")
        }
        guard let available = snap["available"] as? Int else {
            return .result(dialog: "Abre Qullqi para ver tu disponible.")
        }
        var text = "Puedes gastar \(QullqiPrefs.spoken(available))."
        if let perDay = snap["perDay"] as? Int {
            text += " Eso es hasta \(QullqiPrefs.spoken(perDay)) por día."
        }
        if (snap["runsShort"] as? Bool) == true {
            text += " Ojo: a este ritmo el mes se te puede quedar corto."
        }
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

@available(iOS 16.0, *)
struct QullqiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CuantoPuedoGastarIntent(),
            phrases: [
                "Cuánto puedo gastar en \(.applicationName)",
                "Mi disponible en \(.applicationName)",
                "Dime mi disponible en \(.applicationName)",
            ],
            shortTitle: "Mi disponible",
            systemImageName: "leaf.fill"
        )
        AppShortcut(
            intent: RegistrarGastoIntent(),
            phrases: [
                "Registrar un gasto en \(.applicationName)",
                "Anotar un gasto en \(.applicationName)",
            ],
            shortTitle: "Registrar gasto",
            systemImageName: "minus.circle.fill"
        )
        AppShortcut(
            intent: MoverPlataIntent(),
            phrases: [
                "Mover plata en \(.applicationName)",
                "Pasar plata en \(.applicationName)",
            ],
            shortTitle: "Mover plata",
            systemImageName: "arrow.left.arrow.right.circle.fill"
        )
        AppShortcut(
            intent: EscanearFacturaIntent(),
            phrases: [
                "Escanear una factura en \(.applicationName)",
            ],
            shortTitle: "Escanear factura",
            systemImageName: "doc.viewfinder"
        )
        AppShortcut(
            intent: ProximosPagosIntent(),
            phrases: [
                "Mis próximos pagos en \(.applicationName)",
                "Qué vence en \(.applicationName)",
            ],
            shortTitle: "Próximos pagos",
            systemImageName: "calendar"
        )
    }
}
