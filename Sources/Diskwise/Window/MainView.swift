import SwiftUI
import DiskwiseCore

/// The main window: icon rail on the left, the selected page, and overlays for
/// confirmations, cleaning progress, results and first-launch onboarding.
struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs = Preferences.shared
    /// Off for snapshots: off-screen renders can't scroll or show real window buttons.
    var live = true

    static let minSize = CGSize(width: 1000, height: 660)

    var body: some View {
        ZStack(alignment: .topLeading) {
            WindowBackdrop(glow: model.section == .dashboard)
            HStack(spacing: 0) {
                IconRail(model: model)
                ZStack {
                    page(model.section)
                        .id(model.section)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 16)),
                                                removal: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            if !live { TrafficLights().padding(.leading, 18).padding(.top, 18) }
        }
        .overlay(alignment: .bottom) { if model.cleaning == nil { StatusOverlay(model: model) } }
        .overlay { if let confirmation = model.confirmation { ConfirmCard(confirmation: confirmation, model: model) } }
        .overlay {
            if let state = model.cleaning {
                CleaningOverlay(model: model, state: state).transition(.opacity)
            }
        }
        .overlay {
            if !prefs.onboardingDone {
                OnboardingView(model: model, live: live).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.cleaning == nil)
        .animation(.easeOut(duration: 0.35), value: prefs.onboardingDone)
        .frame(minWidth: Self.minSize.width, minHeight: Self.minSize.height)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func page(_ section: NavItem) -> some View {
        switch section {
        case .dashboard: DashboardView(model: model)
        case .cleanup: CleanupWindowPage(model: model, live: live)
        case .lens: LensView(model: model, live: live)
        case .files: FilesWindowPage(model: model, live: live)
        case .projects: ProjectsWindowPage(model: model, live: live)
        case .apps: AppsWindowPage(model: model, live: live)
        }
    }
}

/// Icons for the pages, with a highlight that glides to the selected one.
struct IconRail: View {
    @ObservedObject var model: AppModel
    @Namespace private var selection

    var body: some View {
        VStack(spacing: 8) {
            AppMark(size: 34).padding(.top, 50).padding(.bottom, 16)
            ForEach(NavItem.allCases) { item in
                RailButton(item: item, selected: model.section == item, namespace: selection,
                           dot: item == .cleanup && model.selectedBytes > Bytes.gb) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { model.section = item }
                }
            }
            Spacer()
            RailIcon(symbol: "gearshape.fill", help: "Settings (Cmd+,)") {
                NSApp.sendAction(#selector(AppDelegate.showSettings(_:)), to: nil, from: nil)
            }
            .padding(.bottom, 18)
        }
        .frame(width: 76)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.22))
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
    }
}

private struct RailButton: View {
    let item: NavItem
    let selected: Bool
    let namespace: Namespace.ID
    var dot = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: item.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selected ? Theme.text : hovering ? Theme.secondary : Theme.tertiary)
                .frame(width: 44, height: 44)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.cyan.opacity(0.22))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cyan.opacity(0.25)))
                            .matchedGeometryEffect(id: "rail", in: namespace)
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if dot { Circle().fill(Theme.cyan).frame(width: 7, height: 7).padding(8) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("\(item.rawValue) (Cmd+\(item.shortcut))")
        .accessibilityLabel(item.rawValue)
    }
}

private struct RailIcon: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(hovering ? Theme.secondary : Theme.tertiary)
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(hovering ? 30 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: hovering)
        .help(help)
    }
}
