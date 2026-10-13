import SwiftUI
import DiskwiseCore

/// CleanMyMac-style sidebar: 3D icons with labels, a highlight that glides to
/// the selected section, Activity and Settings at the bottom.
struct AppSidebar: View {
    @ObservedObject var model: AppModel
    @Namespace private var selection

    static let width: CGFloat = 232

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Spacer().frame(height: 52)
            ForEach(NavItem.main) { item in row(item) }
            Spacer()
            row(.activity)
            SidebarRow(title: "Settings", icon: "icon-settings", symbol: "gearshape.fill", tint: Color(0.7, 0.7, 0.75),
                       selected: false, badge: nil, namespace: selection) {
                NSApp.sendAction(#selector(AppDelegate.showSettings(_:)), to: nil, from: nil)
            }
            Spacer().frame(height: 14)
        }
        .padding(.horizontal, 14)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.12))
        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.08)).frame(width: 1) }
    }

    private func row(_ item: NavItem) -> some View {
        SidebarRow(title: item.rawValue, icon: item.icon, symbol: item.symbol, tint: item.color,
                   selected: model.section == item, badge: badge(item), namespace: selection) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { model.section = item }
        }
        .help("\(item.rawValue) (Cmd+\(item.shortcut))")
    }

    private func badge(_ item: NavItem) -> String? {
        switch item {
        case .cleanup: return model.selectedBytes > Bytes.gb ? Bytes.format(model.selectedBytes) : nil
        case .projects: return model.staleProjects.isEmpty ? nil : "\(model.staleProjects.count)"
        default: return nil
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let icon: String
    let symbol: String
    let tint: Color
    let selected: Bool
    let badge: String?
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false
    @State private var pop = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Icon3D(name: icon, symbol: symbol, tint: tint, size: 26)
                    .scaleEffect(pop ? 1.24 : hovering && !selected ? 1.08 : 1)
                    .rotationEffect(.degrees(pop ? -10 : 0))
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.8))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.12)))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.white.opacity(0.16))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.1)))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.07))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onChange(of: selected) { _, now in
            // A little pop and tilt on the icon of the section you just opened.
            guard now else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { pop = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { pop = false }
            }
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Top right of the window: free space and the alerts bell.
struct WindowToolbar: View {
    @ObservedObject var model: AppModel
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Button { withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { model.section = .lens } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "internaldrive.fill").font(.system(size: 12))
                    HStack(spacing: 4) {
                        RollingBytes(bytes: model.disk?.available ?? 0, font: .system(size: 12.5, weight: .semibold))
                        Text("free").font(.system(size: 12.5, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(.white.opacity(0.13)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
                .overlay {
                    // Pulses when free space changes, like after a cleanup.
                    Capsule().strokeBorder(Theme.green, lineWidth: 2)
                        .scaleEffect(pulse ? 1.35 : 1)
                        .opacity(pulse ? 0 : 0.9)
                        .opacity(pulse ? 1 : 0)
                }
                .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .onChange(of: model.disk?.available ?? 0) { old, new in
                guard old > 0, abs(new - old) > 200 * Bytes.mb else { return }
                pulse = false
                withAnimation(.easeOut(duration: 1.0)) { pulse = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) { pulse = false }
            }
            .help("Free space on \(model.disk?.name ?? "your disk"). Opens Space Lens.")
            Button { NSApp.sendAction(#selector(AppDelegate.showSettings(_:)), to: nil, from: nil) } label: {
                Image(systemName: model.alertsOn ? "bell.fill" : "bell.slash.fill").font(.system(size: 12))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white.opacity(0.13)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.1)))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .help(model.alertsOn ? "Low space alerts are on" : "Low space alerts are off")
        }
        .padding(.top, 14)
        .padding(.trailing, 16)
    }
}
