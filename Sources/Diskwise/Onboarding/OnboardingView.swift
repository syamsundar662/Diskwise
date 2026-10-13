import SwiftUI
import DiskwiseCore

/// First launch: what Diskwise does, Full Disk Access (detected live), and
/// alerts and login preferences.
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs = Preferences.shared
    var live = true
    @State var step = 0
    @State private var hasAccess = AppModel.hasFullDiskAccess()
    @State private var floating = false

    var body: some View {
        ZStack {
            WindowBackdrop(glow: true)
            VStack(spacing: 0) {
                Spacer(minLength: 20)
                Group {
                    switch step {
                    case 0: welcome
                    case 1: access
                    default: preferences
                    }
                }
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .frame(maxWidth: 560)
                Spacer(minLength: 20)
                dots.padding(.bottom, 26)
            }
            .padding(.horizontal, 40)
        }
        .task(id: step) {
            // Watch for Full Disk Access while its step is showing.
            guard step == 1, live else { return }
            while !Task.isCancelled {
                let granted = AppModel.hasFullDiskAccess()
                if granted != hasAccess { withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { hasAccess = granted } }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func next() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step += 1 }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<3) { i in
                Capsule().fill(i == step ? Theme.cyan : Color.white.opacity(0.2))
                    .frame(width: i == step ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 26) {
            AppMark(size: 104)
                .offset(y: floating ? -5 : 5)
                .onAppear { withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { floating = true } }
            VStack(spacing: 8) {
                Text("Welcome to Diskwise").font(.system(size: 32, weight: .bold)).foregroundStyle(Theme.text)
                Text("See what fills your Mac and free up space, safely.")
                    .font(.system(size: 15)).foregroundStyle(Theme.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                feature("sparkles", Theme.teal, "Smart Cleanup", "Caches, logs and build files that rebuild themselves.")
                feature("chart.pie.fill", Theme.blue, "Space Lens", "Every folder by size, one click deep.")
                feature("checkmark.shield.fill", Theme.green, "Safe by design",
                        "Your files only go to the Trash. Nothing outside your home folder is ever deleted.")
            }
            .padding(20)
            .card(radius: 16)
            Button("Get Started") { next() }.buttonStyle(GlowButtonStyle(large: true)).keyboardShortcut(.defaultAction)
        }
    }

    private func feature(_ symbol: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            IconChip(symbol: symbol, color: color, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var access: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill((hasAccess ? Theme.green : Theme.cyan).opacity(0.14)).frame(width: 104, height: 104)
                Image(systemName: hasAccess ? "checkmark.shield.fill" : "lock.shield.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(hasAccess ? Theme.green : Theme.cyan)
                    .contentTransition(.symbolEffect(.replace))
            }
            VStack(spacing: 8) {
                Text(hasAccess ? "Full Disk Access is on" : "Allow Full Disk Access")
                    .font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.text)
                    .contentTransition(.opacity)
                Text("Diskwise needs it to measure the Trash, Mail downloads and app containers. It only reads sizes, never the contents of your documents.")
                    .font(.system(size: 14)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 12) {
                stepRow(1, "Click Open System Settings below.")
                stepRow(2, "Turn on Diskwise in the list. Use + to add it if it's missing.")
                stepRow(3, "Come back here. Diskwise notices on its own.")
            }
            .padding(20)
            .card(radius: 16)
            HStack(spacing: 8) {
                if hasAccess {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                    Text("Access granted").foregroundStyle(Theme.green)
                } else {
                    Spinner(size: 11)
                    Text("Waiting for access...").foregroundStyle(Theme.secondary)
                }
            }
            .font(.system(size: 12.5, weight: .semibold))
            HStack(spacing: 12) {
                if hasAccess {
                    Button("Continue") { next() }.buttonStyle(GlowButtonStyle(large: true)).keyboardShortcut(.defaultAction)
                } else {
                    Button("Skip for now") { next() }.buttonStyle(PillButtonStyle())
                    Button("Open System Settings") { model.openFullDiskAccessSettings() }
                        .buttonStyle(GlowButtonStyle(large: true))
                }
            }
        }
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)").font(Theme.number(12, .bold)).foregroundStyle(Theme.onCyan)
                .frame(width: 22, height: 22).background(Circle().fill(Theme.cyan))
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.text)
            Spacer(minLength: 0)
        }
    }

    private var preferences: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(Theme.amber.opacity(0.14)).frame(width: 104, height: 104)
                Image(systemName: "bell.badge.fill").font(.system(size: 42, weight: .semibold)).foregroundStyle(Theme.amber)
            }
            VStack(spacing: 8) {
                Text("Stay ahead of a full disk").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.text)
                Text("Diskwise can keep an eye on your space from the menu bar.")
                    .font(.system(size: 14)).foregroundStyle(Theme.secondary)
            }
            VStack(spacing: 0) {
                toggleRow("bell.fill", Theme.amber, "Warn me when space runs low",
                          "A notification when less than \(prefs.alertThresholdGB) GB is left.", isOn: $model.alertsOn)
                Hairline().padding(.leading, 56)
                toggleRow("menubar.rectangle", Theme.cyan, "Show in the menu bar",
                          "Disk usage at a glance, with quick cleanup.", isOn: $prefs.showMenuBarItem)
                Hairline().padding(.leading, 56)
                toggleRow("power", Theme.green, "Open at login", "Keeps the menu bar item and alerts running.",
                          isOn: $prefs.launchAtLogin)
            }
            .card(radius: 16)
            Button("Start Using Diskwise") {
                prefs.onboardingDone = true
                if model.scan == nil, !model.scanning { model.startScan() }
            }
            .buttonStyle(GlowButtonStyle(large: true))
            .keyboardShortcut(.defaultAction)
        }
    }

    private func toggleRow(_ symbol: String, _ color: Color, _ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            IconChip(symbol: symbol, color: color, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            PillToggle(isOn: isOn)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
