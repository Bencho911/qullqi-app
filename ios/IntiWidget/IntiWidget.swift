import SwiftUI
import WidgetKit

// MARK: - Datos
//
// La app escribe una foto pequeña en el grupo compartido
// (`group.co.inti.app`, clave `snapshot`). Los widgets solo la leen:
// no consultan nada ni tocan tus cuentas.

struct QSnapshot: Codable {
    struct Payment: Codable {
        var title: String
        var amount: Int?
        var daysLeft: Int
    }

    var version: Int
    var updatedAt: String
    var firstName: String
    var scopeLabel: String
    var amountsHidden: Bool
    var runsShort: Bool
    var unread: Int
    var available: Int?
    var perDay: Int?
    var netWorth: Int?
    var payments: [Payment]

    /// Datos de ejemplo para la galería de widgets.
    static let sample = QSnapshot(
        version: 1,
        updatedAt: "",
        firstName: "Camilo",
        scopeLabel: "Todo",
        amountsHidden: false,
        runsShort: false,
        unread: 2,
        available: 3_208_672,
        perDay: 400_000,
        netWorth: 22_623_800,
        payments: [
            Payment(title: "Tarjeta Visa •• 4521", amount: 1_320_000, daysLeft: 3),
            Payment(title: "Internet y TV del hogar", amount: 89_000, daysLeft: 5),
            Payment(title: "Arriendo", amount: 1_200_000, daysLeft: 8),
        ]
    )
}

enum QStore {
    static let group = "group.co.inti.app"

    static func load() -> QSnapshot? {
        guard
            let defaults = UserDefaults(suiteName: group),
            let json = defaults.string(forKey: "snapshot"),
            let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(QSnapshot.self, from: data)
    }
}

// MARK: - Formato

enum QMoney {
    private static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = "."
        f.groupingSize = 3
        f.maximumFractionDigits = 0
        return f
    }()

    /// 3208672 -> "$3.208.672"
    static func cop(_ value: Int) -> String {
        let body = grouped.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
        return (value < 0 ? "-$" : "$") + body
    }

    /// 3208672 -> "$3,2 M"; 85400 -> "$85 mil"
    static func compact(_ value: Int) -> String {
        let a = abs(value)
        let sign = value < 0 ? "-" : ""
        if a >= 1_000_000 {
            let m = Double(a) / 1_000_000
            let text = (m >= 10 || m == m.rounded())
                ? String(Int(m.rounded()))
                : String(format: "%.1f", m).replacingOccurrences(of: ".", with: ",")
            return "\(sign)$\(text) M"
        }
        if a >= 1_000 { return "\(sign)$\(Int((Double(a) / 1_000).rounded())) mil" }
        return cop(value)
    }
}

func qDueText(_ days: Int) -> String {
    switch days {
    case ..<0: return days == -1 ? "Venció ayer" : "Venció hace \(-days) días"
    case 0: return "Vence hoy"
    case 1: return "Vence mañana"
    default: return "Vence en \(days) días"
    }
}

// MARK: - Colores de la marca

enum QColor {
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    /// Verde profundo del bloque destacado.
    static let hero = dynamic(light: 0x0B2A1F, dark: 0x17372C)
    static let heroMuted = dynamic(light: 0xB7CBC1, dark: 0xC3D3CB)
    static let accent = dynamic(light: 0x7FE3B8, dark: 0x9BDDBE)
    static let warning = dynamic(light: 0xF2C25B, dark: 0xEBC070)
    static let danger = dynamic(light: 0xFF9D95, dark: 0xEE8F88)

    static let surface = dynamic(light: 0xFFFFFF, dark: 0x1C1F1E)
    static let ink = dynamic(light: 0x12201A, dark: 0xF3F5F4)
    static let inkMuted = dynamic(light: 0x43524B, dark: 0xBFC7C3)
    static let primary = dynamic(light: 0x0B7554, dark: 0x56BE94)
}

// MARK: - Enlaces (abren la app en una pantalla)

enum QLink {
    static func shortcut(_ id: String) -> URL {
        URL(string: "inti:///atajo/\(id)")!
    }
}

// MARK: - Línea de tiempo

struct QEntry: TimelineEntry {
    let date: Date
    let snapshot: QSnapshot?
}

struct QProvider: TimelineProvider {
    func placeholder(in context: Context) -> QEntry {
        QEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (QEntry) -> Void) {
        completion(QEntry(date: Date(), snapshot: context.isPreview ? .sample : QStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QEntry>) -> Void) {
        let entry = QEntry(date: Date(), snapshot: QStore.load())
        // La app refresca los widgets cuando cambian los datos; aparte, cada
        // media hora, por si pasa un día y cambian los "vence en N días".
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Piezas

extension View {
    /// Fondo del widget: en iOS 17 va como contenedor; antes, como fondo.
    @ViewBuilder
    func qBackground(_ color: Color) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(color, for: .widget)
        } else {
            self.background(color)
        }
    }
}

/// El monto grande, o "Abre Inti" si la persona los ocultó.
struct QAmount: View {
    let value: Int?
    let hidden: Bool
    var size: CGFloat = 28
    var color: Color = .white

    var body: some View {
        if hidden || value == nil {
            Label("Abre Inti", systemImage: "lock.fill")
                .font(.system(size: size * 0.55, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else {
            Text(QMoney.cop(value ?? 0))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .privacySensitive()
        }
    }
}

/// Fila de un pago próximo.
struct QPaymentRow: View {
    let payment: QSnapshot.Payment
    let hidden: Bool
    var onDark: Bool = true

    private var dot: Color {
        if payment.daysLeft < 0 { return QColor.danger }
        if payment.daysLeft <= 3 { return QColor.warning }
        return QColor.accent
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(dot).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(payment.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(onDark ? Color.white : QColor.ink)
                    .lineLimit(1)
                Text(qDueText(payment.daysLeft))
                    .font(.system(size: 11))
                    .foregroundStyle(onDark ? QColor.heroMuted : QColor.inkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if !hidden, let amount = payment.amount {
                Text(QMoney.compact(amount))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(onDark ? Color.white : QColor.ink)
                    .lineLimit(1)
                    .privacySensitive()
            }
        }
    }
}

/// Lo que se ve cuando la app aún no ha dejado datos.
struct QEmpty: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 22))
                .foregroundStyle(QColor.accent)
            Text("Abre Inti")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text("para ver tu disponible")
                .font(.system(size: 11))
                .foregroundStyle(QColor.heroMuted)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Widget 1: lo que puedes gastar

struct AvailableView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .systemMedium: medium
        default: small
        }
    }

    // Pantalla de inicio, pequeño.
    private var small: some View {
        Group {
            if let s = entry.snapshot {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Disponible")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(QColor.heroMuted)
                        Spacer(minLength: 0)
                        if s.runsShort {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(QColor.warning)
                        }
                    }
                    Spacer(minLength: 0)
                    QAmount(value: s.available, hidden: s.amountsHidden, size: 26)
                    if !s.amountsHidden, let perDay = s.perDay {
                        Text("\(QMoney.compact(perDay)) por día")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(QColor.accent)
                            .lineLimit(1)
                            .privacySensitive()
                    }
                    Text(s.scopeLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(QColor.heroMuted)
                }
            } else {
                QEmpty()
            }
        }
        .widgetURL(QLink.shortcut("disponible"))
        .qBackground(QColor.hero)
    }

    // Pantalla de inicio, mediano: el disponible y lo que viene.
    private var medium: some View {
        Group {
            if let s = entry.snapshot {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Disponible para gastar")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(QColor.heroMuted)
                        Spacer(minLength: 0)
                        QAmount(value: s.available, hidden: s.amountsHidden, size: 30)
                        if !s.amountsHidden, let perDay = s.perDay {
                            Text("Hasta \(QMoney.compact(perDay)) por día")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(s.runsShort ? QColor.warning : QColor.accent)
                                .lineLimit(1)
                                .privacySensitive()
                        }
                        Text(s.scopeLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(QColor.heroMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lo que viene")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(QColor.heroMuted)
                        if s.payments.isEmpty {
                            Text("Nada en los próximos 30 días")
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                        } else {
                            ForEach(Array(s.payments.prefix(2).enumerated()), id: \.offset) { _, p in
                                QPaymentRow(payment: p, hidden: s.amountsHidden)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                QEmpty()
            }
        }
        .widgetURL(QLink.shortcut("disponible"))
        .qBackground(QColor.hero)
    }

    // Pantalla de bloqueo.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Disponible")
                .font(.system(size: 12, weight: .semibold))
                .widgetAccentable()
            if let s = entry.snapshot, !s.amountsHidden, let value = s.available {
                Text(QMoney.cop(value))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .privacySensitive()
                if let p = s.payments.first, let amount = p.amount {
                    Text("\(p.title.prefix(18)) · \(QMoney.compact(amount))")
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .privacySensitive()
                }
            } else {
                Label("Abre Inti", systemImage: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .widgetURL(QLink.shortcut("disponible"))
        .qBackground(.clear)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "leaf.fill").font(.system(size: 11))
                if let s = entry.snapshot, !s.amountsHidden, let value = s.available {
                    Text(QMoney.compact(value))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .privacySensitive()
                } else {
                    Image(systemName: "lock.fill").font(.system(size: 13))
                }
            }
        }
        .widgetURL(QLink.shortcut("disponible"))
        .qBackground(.clear)
    }

    private var inline: some View {
        Group {
            if let s = entry.snapshot, !s.amountsHidden, let value = s.available {
                Text("Disponible \(QMoney.compact(value))").privacySensitive()
            } else {
                Text("Abre Inti")
            }
        }
        .widgetURL(QLink.shortcut("disponible"))
    }
}

struct IntiAvailableWidget: Widget {
    let kind = "IntiWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QProvider()) { entry in
            AvailableView(entry: entry)
        }
        .configurationDisplayName("Disponible para gastar")
        .description("Lo que puedes gastar de verdad y lo que viene.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryRectangular, .accessoryCircular, .accessoryInline,
        ])
    }
}

// MARK: - Widget 2: próximos pagos

struct PaymentsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QEntry

    var body: some View {
        Group {
            if let s = entry.snapshot {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Próximos pagos")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                        if s.unread > 0 {
                            Label("\(s.unread)", systemImage: "bell.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(QColor.warning)
                        }
                    }
                    if s.payments.isEmpty {
                        Spacer(minLength: 0)
                        Text("No tienes pagos en los próximos 30 días.")
                            .font(.system(size: 13))
                            .foregroundStyle(QColor.heroMuted)
                        Spacer(minLength: 0)
                    } else {
                        ForEach(Array(s.payments.prefix(family == .systemLarge ? 5 : 3).enumerated()), id: \.offset) { _, p in
                            QPaymentRow(payment: p, hidden: s.amountsHidden)
                        }
                        Spacer(minLength: 0)
                    }
                }
            } else {
                QEmpty()
            }
        }
        .widgetURL(QLink.shortcut("pagos"))
        .qBackground(QColor.hero)
    }
}

struct IntiPaymentsWidget: Widget {
    let kind = "IntiPaymentsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QProvider()) { entry in
            PaymentsView(entry: entry)
        }
        .configurationDisplayName("Próximos pagos")
        .description("Tarjetas, pagos fijos e impuestos que vencen pronto.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Widget 3: atajos

struct QuickActionTile: View {
    let symbol: String
    let title: String
    let id: String
    var badge: Int = 0

    var body: some View {
        Link(destination: QLink.shortcut(id)) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(QColor.accent)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(QColor.warning)
                            .clipShape(Capsule())
                            .offset(x: 6, y: -4)
                    }
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct QuickActionsView: View {
    let entry: QEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(greeting)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
            HStack(spacing: 6) {
                QuickActionTile(symbol: "minus.circle.fill", title: "Gasto", id: "registrar-gasto")
                QuickActionTile(symbol: "arrow.left.arrow.right.circle.fill", title: "Mover", id: "mover-plata")
                QuickActionTile(symbol: "doc.viewfinder", title: "Escanear", id: "escanear-factura")
                QuickActionTile(
                    symbol: "bell.fill",
                    title: "Avisos",
                    id: "avisos",
                    badge: entry.snapshot?.unread ?? 0
                )
            }
        }
        .qBackground(QColor.hero)
    }

    private var greeting: String {
        if let name = entry.snapshot?.firstName, !name.isEmpty {
            return "Hola, \(name)"
        }
        return "Inti"
    }
}

struct IntiQuickWidget: Widget {
    let kind = "IntiQuickActions"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QProvider()) { entry in
            QuickActionsView(entry: entry)
        }
        .configurationDisplayName("Atajos")
        .description("Registra un gasto, mueve plata o escanea una factura.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Paquete

@main
struct IntiWidgets: WidgetBundle {
    var body: some Widget {
        IntiAvailableWidget()
        IntiPaymentsWidget()
        IntiQuickWidget()
    }
}
