import SwiftUI
import DiskwiseCore

// Window versions of the list pages: the panel's lists, given a title and the
// full height of the window.

struct CleanupWindowPage: View {
    @ObservedObject var model: AppModel
    var live: Bool

    var body: some View {
        WindowPage(title: "Smart Cleanup",
                   subtitle: "Caches, logs and build data that apps and tools rebuild on their own. Expand a group to pick items.") {
            Button(model.cleanupLoading ? "Checking..." : "Check again") { model.loadCleanup() }
                .buttonStyle(PillButtonStyle()).disabled(model.cleanupLoading)
        } content: {
            CleanupPage(model: model, live: live, listHeight: nil).windowCard()
        }
    }
}

struct FilesWindowPage: View {
    @ObservedObject var model: AppModel
    var live: Bool

    var body: some View {
        WindowPage(title: "Large & Old Files",
                   subtitle: "Big files in your folders, and downloads you haven't opened in \(Downloads.oldDays) days. Removed files go to the Trash.") {
            EmptyView()
        } content: {
            FilesPage(model: model, live: live, listHeight: nil).windowCard()
        }
    }
}

struct ProjectsWindowPage: View {
    @ObservedObject var model: AppModel
    var live: Bool

    var body: some View {
        WindowPage(title: "Project Junk",
                   subtitle: "node_modules, build, Pods and similar folders your tools recreate. Idle projects are selected.") {
            EmptyView()
        } content: {
            ProjectsPage(model: model, live: live, listHeight: nil).windowCard()
        }
    }
}

struct AppsWindowPage: View {
    @ObservedObject var model: AppModel
    var live: Bool

    private var app: InstalledApp? { model.windowApp.flatMap { path in model.apps.first { $0.path == path } } }

    var body: some View {
        WindowPage(title: "Uninstaller",
                   subtitle: app == nil ? "Remove apps together with the support files, caches and settings they leave behind."
                       : "The app and the files it left in your Library. Everything goes to the Trash.") {
            if app != nil {
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) { model.windowApp = nil }
                } label: {
                    Label("All apps", systemImage: "chevron.left")
                }
                .buttonStyle(PillButtonStyle())
            }
        } content: {
            ZStack {
                if let app {
                    AppDetailPage(model: model, path: app.path, live: live, listHeight: nil)
                        .windowCard()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    AppsPage(model: model, live: live, listHeight: nil) { app in
                        model.loadLeftovers(for: app)
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) { model.windowApp = app.path }
                    }
                    .windowCard()
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
        }
    }
}
