import SwiftUI
import DiskwiseCore

/// The main window: sidebar on the left, each section on its own colored
/// background, and overlays for confirmations, cleaning progress, results and
/// first-launch onboarding.
struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs = Preferences.shared
    /// Off for snapshots: off-screen renders can't scroll or show real window buttons.
    var live = true

    static let minSize = CGSize(width: 1040, height: 680)

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                SectionBackdrop(section: model.section)
                    .id(model.section)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.55), value: model.section)
            HStack(spacing: 0) {
                AppSidebar(model: model)
                ZStack {
                    page(model.section)
                        .id(model.section)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 18)), removal: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            if !live { TrafficLights().padding(.leading, 18).padding(.top, 18) }
        }
        .overlay(alignment: .topTrailing) { WindowToolbar(model: model) }
        .overlay(alignment: .bottom) { if model.cleaning == nil { StatusOverlay(model: model).padding(.leading, AppSidebar.width) } }
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
        case .dashboard: SmartCareView(model: model)
        case .cleanup: CleanupWindowPage(model: model, live: live)
        case .lens: LensView(model: model, live: live)
        case .files: FilesWindowPage(model: model, live: live)
        case .projects: ProjectsWindowPage(model: model, live: live)
        case .apps: AppsWindowPage(model: model, live: live)
        case .activity: ActivityView(model: model)
        }
    }
}
