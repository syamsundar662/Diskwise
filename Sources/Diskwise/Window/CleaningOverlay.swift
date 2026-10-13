import SwiftUI
import DiskwiseCore

/// Covers the window while a cleanup runs: the ring fills as space is freed,
/// then a checkmark draws in with the result.
struct CleaningOverlay: View {
    @ObservedObject var model: AppModel
    let state: CleaningState

    private var fraction: Double {
        if state.finished { return 1 }
        return state.total > 0 ? Double(state.freed) / Double(state.total) : 0
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    TickRing(progress: fraction, colors: state.failed > 0 && state.finished ? (Theme.amber, Theme.amber) : (Theme.cyan, Theme.green),
                             ticks: 72, tickLength: 13, tickWidth: 3.4)
                        .animation(.easeOut(duration: 0.5), value: fraction)
                    if state.finished {
                        DrawnCheckmark().frame(width: 64, height: 64).transition(.scale(scale: 0.6).combined(with: .opacity))
                    } else {
                        VStack(spacing: 2) {
                            RollingBytes(bytes: state.freed, font: Theme.number(30))
                            Text(state.trashed ? "moved" : "freed").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: 190, height: 190)
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: state.finished)

                VStack(spacing: 6) {
                    Text(title).font(.system(size: 21, weight: .bold)).foregroundStyle(Theme.text)
                        .contentTransition(.opacity)
                    Text(detail).font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                        .lineLimit(2).multilineTextAlignment(.center).truncationMode(.middle)
                        .frame(height: 34, alignment: .top)
                }
                .animation(.easeOut(duration: 0.25), value: state.finished)

                if state.finished {
                    HStack(spacing: 10) {
                        if state.trashed && state.freed > 0 {
                            Button("Empty Trash") {
                                model.cleaning = nil
                                model.confirmEmptyTrash()
                            }
                            .buttonStyle(PillButtonStyle())
                        }
                        Button("Done") { model.cleaning = nil }
                            .buttonStyle(GlowButtonStyle())
                            .keyboardShortcut(.defaultAction)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 34)
            .frame(width: 440)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        }
    }

    private var title: String {
        guard state.finished else { return state.trashed ? "Moving to the Trash..." : "Cleaning..." }
        if state.freed == 0 { return "Nothing was removed" }
        return state.trashed ? "Moved \(Bytes.format(state.freed)) to the Trash" : "Freed \(Bytes.format(state.freed))"
    }

    private var detail: String {
        guard state.finished else { return state.current }
        var text = state.trashed ? "Empty the Trash to get the space back." : "Your Mac has more room to breathe."
        if state.failed > 0 { text = "\(state.failed) items couldn't be removed, usually because an app is using them." }
        return text
    }
}

/// A green circle whose checkmark draws itself in.
struct DrawnCheckmark: View {
    @State private var drawn = RenderMode.snapshot

    var body: some View {
        ZStack {
            Circle().fill(Theme.green.opacity(0.18))
            CheckShape()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(Theme.green, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .padding(18)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.45).delay(0.1)) { drawn = true } }
    }

    private struct CheckShape: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY - rect.height * 0.1))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.1))
            return p
        }
    }
}
