import Foundation
import DiskwiseCore

/// Live readings for the panel's "This Mac" card. Samples every 2 seconds off
/// the main thread, only while the panel is open, and publishes on its own so
/// a reading redraws just the card, not the whole panel.
@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot: SystemSnapshot?
    /// Used only on `queue`.
    private let sampler = SystemSampler()
    private let queue = DispatchQueue(label: "diskwise.system", qos: .utility)
    private var timer: Timer?
    private var health: BatteryHealth?
    private var healthDate = Date.distantPast

    func start() {
        guard timer == nil else { return }
        tick()
        // The first reading only sets the CPU counters; the second gives CPU use.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard self?.timer != nil else { return }
            self?.tick()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        let sampler = sampler
        queue.async { sampler.reset() }
    }

    private func tick() {
        // Battery health changes over weeks; read it once an hour.
        let refreshHealth = Date().timeIntervalSince(healthDate) > 3600
        if refreshHealth { healthDate = Date() }
        let known = health
        let sampler = sampler
        queue.async { [weak self] in
            let health = refreshHealth ? BatteryHealth.read() ?? known : known
            var reading = sampler.sample(health: health)
            DispatchQueue.main.async {
                guard let self else { return }
                self.health = health
                // Keep the last CPU value while a fresh interval starts, instead of blanking it.
                if reading.cpu == nil { reading.cpu = self.snapshot?.cpu }
                if reading != self.snapshot { self.snapshot = reading }
            }
        }
    }
}
