import SwiftUI
import DiskwiseCore

/// "This Mac": CPU, GPU, memory and temperature with bars, the battery below.
/// Observes only the monitor, so its readings redraw just this card.
struct SystemCard: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        let s = monitor.snapshot
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "This Mac", detail: s?.chip)
                Spacer()
                if let s { thermalLabel(s.thermal) }
            }
            HStack(alignment: .top, spacing: 16) {
                StatGauge(title: "CPU", value: percent(s?.cpu), fraction: s?.cpu, color: loadColor(s?.cpu))
                StatGauge(title: "GPU", value: percent(s?.gpu), fraction: s?.gpu, color: loadColor(s?.gpu))
                StatGauge(title: "Memory", value: s.map { Bytes.formatMemory($0.memoryUsed) } ?? "...",
                          detail: s.map { "of \(Bytes.formatMemory($0.memoryTotal))" },
                          fraction: s?.memoryFraction, color: memoryColor(s?.memoryFraction))
                StatGauge(title: "Temperature", value: temperature(s),
                          fraction: s?.temperature.map { $0 / 100 }, color: s.map(temperatureColor) ?? Theme.cyan)
            }
            if let battery = s?.battery {
                Hairline()
                batteryRow(battery)
            }
        }
        .padding(12)
        .card()
    }

    // MARK: Values

    private func percent(_ value: Double?) -> String {
        value.map { "\(Int(($0 * 100).rounded()))%" } ?? "..."
    }

    /// Die temperature; Macs without readable sensors show the thermal state instead.
    private func temperature(_ s: SystemSnapshot?) -> String {
        guard let s else { return "..." }
        return s.temperature.map { "\(Int($0.rounded()))°C" } ?? s.thermal.label
    }

    private func loadColor(_ value: Double?) -> Color {
        switch value ?? 0 {
        case 0.9...: return Theme.red
        case 0.7...: return Theme.amber
        default: return Theme.cyan
        }
    }

    /// macOS keeps memory full on purpose, so only warn near the top.
    private func memoryColor(_ value: Double?) -> Color {
        switch value ?? 0 {
        case 0.95...: return Theme.red
        case 0.85...: return Theme.amber
        default: return Theme.cyan
        }
    }

    private func temperatureColor(_ s: SystemSnapshot) -> Color {
        switch s.thermal {
        case .hot, .throttling: return Theme.red
        case .warm: return Theme.amber
        case .normal: return (s.temperature ?? 0) >= 85 ? Theme.amber : Theme.cyan
        }
    }

    private func thermalLabel(_ level: ThermalLevel) -> some View {
        let (text, color): (String, Color) = switch level {
        case .normal: ("Thermals normal", Theme.green)
        case .warm: ("Running warm", Theme.amber)
        case .hot: ("Running hot", Theme.red)
        case .throttling: ("Slowing down to cool", Theme.red)
        }
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.secondary)
        }
    }

    // MARK: Battery

    private func batteryRow(_ b: BatteryInfo) -> some View {
        let worn = (b.health ?? 100) < 80 || !["Good", "Normal", nil].contains(b.condition)
        return HStack(spacing: 6) {
            Image(systemName: batterySymbol(b)).font(.system(size: 13))
                .foregroundStyle(b.charge <= 20 && !b.pluggedIn ? Theme.red : Theme.green)
            Text("Battery").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text.opacity(0.88))
            if let health = b.health {
                Text("\(health)% health").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(worn ? Theme.amber : Theme.text)
                dot
            }
            Text("\(b.cycles) cycles").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            dot
            Text(chargeText(b)).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            Spacer(minLength: 0)
            if let condition = b.condition, worn, condition != "Good", condition != "Normal" {
                Text(condition).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.amber)
            }
        }
        .lineLimit(1)
    }

    private var dot: some View { Text("·").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.tertiary) }

    private func chargeText(_ b: BatteryInfo) -> String {
        if b.charging { return "\(b.charge)%, charging" }
        if b.pluggedIn { return b.full ? "\(b.charge)%, charged" : "\(b.charge)%, on power" }
        return "\(b.charge)%, on battery"
    }

    private func batterySymbol(_ b: BatteryInfo) -> String {
        if b.charging { return "battery.100percent.bolt" }
        switch b.charge {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

/// One stat: a label, the value and a thin bar.
private struct StatGauge: View {
    let title: String
    let value: String
    var detail: String? = nil
    let fraction: Double?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(Theme.number(16)).foregroundStyle(Theme.text).monospacedDigit()
                if let detail { Text(detail).font(.system(size: 10)).foregroundStyle(Theme.tertiary) }
            }
            .lineLimit(1)
            CapacityBar(fraction: fraction ?? 0, color: color)
                .animation(.easeOut(duration: 0.4), value: fraction)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
