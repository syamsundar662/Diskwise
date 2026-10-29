import Darwin
import Foundation
import IOKit

/// One reading of the Mac's load, memory, temperature and battery, for the
/// panel's "This Mac" card.
public struct SystemSnapshot: Equatable {
    /// Share of all cores busy since the last reading, 0...1. Nil on the first reading.
    public var cpu: Double?
    /// GPU utilization, 0...1. Nil when the GPU doesn't report it.
    public var gpu: Double?
    public var memoryUsed: Int64
    public var memoryTotal: Int64
    /// Average of the chip's die sensors in °C. Nil where the sensors can't be read (Intel Macs).
    public var temperature: Double?
    public var thermal: ThermalLevel
    /// Nil on Macs without a battery.
    public var battery: BatteryInfo?
    public var chip: String

    public var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
}

/// macOS's thermal state: how hard the system is working to stay cool.
public enum ThermalLevel: Equatable {
    case normal, warm, hot, throttling

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .normal
        case .fair: self = .warm
        case .serious: self = .hot
        case .critical: self = .throttling
        @unknown default: self = .normal
        }
    }

    public var label: String {
        switch self {
        case .normal: return "Normal"
        case .warm: return "Warm"
        case .hot: return "Hot"
        case .throttling: return "Throttling"
        }
    }
}

// MARK: CPU

/// Processor tick counters summed over all cores.
public struct CPUTicks: Equatable {
    public var busy: UInt64
    public var idle: UInt64

    public init(busy: UInt64, idle: UInt64) {
        self.busy = busy
        self.idle = idle
    }

    /// Share of ticks spent busy between two readings; nil if no time passed.
    public static func usage(from old: CPUTicks, to new: CPUTicks) -> Double? {
        guard new.busy >= old.busy, new.idle >= old.idle else { return nil }
        let busy = Double(new.busy - old.busy)
        let total = busy + Double(new.idle - old.idle)
        return total > 0 ? busy / total : nil
    }

    static func read() -> CPUTicks? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)) }
        var ticks = CPUTicks(busy: 0, idle: 0)
        for core in 0..<Int(count) {
            let base = core * Int(CPU_STATE_MAX)
            func state(_ s: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[base + Int(s)])) }
            ticks.busy += state(CPU_STATE_USER) + state(CPU_STATE_SYSTEM) + state(CPU_STATE_NICE)
            ticks.idle += state(CPU_STATE_IDLE)
        }
        return ticks
    }
}

// MARK: Memory

public enum MemoryStats {
    /// Memory used as Activity Monitor counts it: app memory (anonymous pages
    /// minus purgeable ones) plus wired plus compressed.
    public static func used(pageSize: UInt64, internal anonymous: UInt64, purgeable: UInt64, wired: UInt64, compressed: UInt64) -> Int64 {
        let app = anonymous > purgeable ? anonymous - purgeable : 0
        return Int64((app + wired + compressed) * pageSize)
    }

    static func readUsed() -> Int64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return used(pageSize: UInt64(vm_kernel_page_size), internal: UInt64(stats.internal_page_count),
                    purgeable: UInt64(stats.purgeable_count), wired: UInt64(stats.wire_count),
                    compressed: UInt64(stats.compressor_page_count))
    }
}

extension Bytes {
    /// RAM in binary units, as Activity Monitor and About This Mac show it: "24 GB", "14.2 GB", "900 MB".
    public static func formatMemory(_ bytes: Int64) -> String {
        let gib = Double(max(bytes, 0)) / 1_073_741_824
        if gib < 1 { return "\(Int((gib * 1024).rounded())) MB" }
        let rounded = (gib * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded)) GB" : String(format: "%.1f GB", rounded)
    }
}

// MARK: GPU

enum GPUStats {
    /// Highest "Device Utilization %" any GPU reports, 0...1.
    static func read() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                let percent = (stats["Device Utilization %"] as? NSNumber)?.doubleValue else { continue }
            best = max(best ?? 0, min(max(percent / 100, 0), 1))
        }
        return best
    }
}

// MARK: Temperature

/// Reads the Apple silicon temperature sensors through IOKit's HID event
/// system. The functions are private, so they're looked up at run time and
/// missing ones just mean no temperature.
public final class Thermals {
    private typealias ClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatching = @convention(c) (CFTypeRef, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEvent = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias FloatValue = @convention(c) (CFTypeRef, Int32) -> Double

    private static let temperatureEvent: Int64 = 15
    private var client: CFTypeRef?
    private var sensors: [(name: String, service: CFTypeRef)] = []
    private var copyEvent: CopyEvent?
    private var floatValue: FloatValue?

    public init() {
        guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return }
        func load<T>(_ name: String, as: T.Type) -> T? { dlsym(iokit, name).map { unsafeBitCast($0, to: T.self) } }
        guard let create = load("IOHIDEventSystemClientCreate", as: ClientCreate.self),
              let setMatching = load("IOHIDEventSystemClientSetMatching", as: SetMatching.self),
              let copyServices = load("IOHIDEventSystemClientCopyServices", as: CopyServices.self),
              let copyProperty = load("IOHIDServiceClientCopyProperty", as: CopyProperty.self),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue() else { return }
        copyEvent = load("IOHIDServiceClientCopyEvent", as: CopyEvent.self)
        floatValue = load("IOHIDEventGetFloatValue", as: FloatValue.self)
        // Vendor page 0xff00, usage 5: temperature sensors.
        _ = setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        self.client = client
        let services = copyServices(client)?.takeRetainedValue() as? [CFTypeRef] ?? []
        sensors = services.compactMap { service in
            guard let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  Self.isDie(name) else { return nil }
            return (name, service)
        }
    }

    /// Average die temperature in °C right now.
    public func read() -> Double? {
        guard let copyEvent, let floatValue else { return nil }
        let field = Int32(Self.temperatureEvent << 16)
        let readings = sensors.compactMap { sensor -> (String, Double)? in
            guard let event = copyEvent(sensor.service, Self.temperatureEvent, 0, 0)?.takeRetainedValue() else { return nil }
            return (sensor.name, floatValue(event, field))
        }
        return Self.dieTemperature(readings)
    }

    /// Average of the plausible die sensor readings ("PMU tdie1", ...); other
    /// sensors (NAND, battery, calibration) and broken values are left out.
    public static func dieTemperature(_ readings: [(String, Double)]) -> Double? {
        let values = readings.filter { isDie($0.0) && $0.1 > 5 && $0.1 < 130 }.map(\.1)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func isDie(_ name: String) -> Bool { name.contains("tdie") }
}

// MARK: Battery

/// Battery health as System Settings shows it (Battery, Battery Health).
public struct BatteryHealth: Equatable {
    public var percent: Int
    /// "Good", "Normal", "Service Recommended", ...
    public var condition: String?

    public init(percent: Int, condition: String?) {
        self.percent = percent
        self.condition = condition
    }

    /// From `system_profiler SPPowerDataType -json`.
    public init?(profilerJSON data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPPowerDataType"] as? [[String: Any]],
              let info = sections.lazy.compactMap({ $0["sppower_battery_health_info"] as? [String: Any] }).first,
              let text = info["sppower_battery_health_maximum_capacity"] as? String,
              let percent = Int(text.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)) else { return nil }
        self.init(percent: percent, condition: info["sppower_battery_health"] as? String)
    }

    /// Runs system_profiler (about a tenth of a second). Health changes slowly, so read it rarely.
    public static func read() -> BatteryHealth? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return BatteryHealth(profilerJSON: data)
    }
}

public struct BatteryInfo: Equatable {
    /// Maximum capacity in percent of the design capacity.
    public var health: Int?
    public var condition: String?
    public var cycles: Int
    /// Charge in percent.
    public var charge: Int
    public var charging: Bool
    public var pluggedIn: Bool
    public var full: Bool

    /// From the AppleSmartBattery registry entry. `health` comes from System
    /// Settings' number when known; otherwise it's nominal over design capacity.
    public init?(registry: [String: Any], health: BatteryHealth?) {
        func int(_ key: String, in dict: [String: Any] = registry) -> Int? { (dict[key] as? NSNumber)?.intValue }
        func bool(_ key: String) -> Bool { (registry[key] as? NSNumber)?.boolValue ?? false }
        guard let cycles = int("CycleCount"), let current = int("CurrentCapacity") else { return nil }
        let scale = int("MaxCapacity") ?? 100
        self.cycles = cycles
        charge = scale > 0 ? min(100, Int((Double(current) * 100 / Double(scale)).rounded())) : current
        charging = bool("IsCharging")
        pluggedIn = bool("ExternalConnected")
        full = bool("FullyCharged")
        condition = health?.condition
        if let health {
            self.health = health.percent
        } else {
            let data = registry["BatteryData"] as? [String: Any] ?? [:]
            if let nominal = int("NominalChargeCapacity", in: data) ?? int("NominalChargeCapacity"),
               let design = int("DesignCapacity", in: data) ?? int("DesignCapacity"), design > 0 {
                self.health = Int(Double(nominal) * 100 / Double(design))
            }
        }
    }

    static func read(health: BatteryHealth?) -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let registry = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return BatteryInfo(registry: registry, health: health)
    }
}

// MARK: Sampler

/// Takes readings. Keeps the previous CPU counters and the sensor handles, so
/// call it from one serial queue.
public final class SystemSampler {
    private var lastTicks: CPUTicks?
    private lazy var thermals = Thermals()
    public let chip: String

    public init() {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        chip = String(cString: buffer)
    }

    /// Forgets the CPU counters, so the next reading starts a fresh interval.
    public func reset() { lastTicks = nil }

    public func sample(health: BatteryHealth?) -> SystemSnapshot {
        let ticks = CPUTicks.read()
        var cpu: Double?
        if let lastTicks, let ticks { cpu = CPUTicks.usage(from: lastTicks, to: ticks) }
        lastTicks = ticks
        return SystemSnapshot(
            cpu: cpu, gpu: GPUStats.read(),
            memoryUsed: MemoryStats.readUsed() ?? 0, memoryTotal: Int64(ProcessInfo.processInfo.physicalMemory),
            temperature: thermals.read(), thermal: ThermalLevel(ProcessInfo.processInfo.thermalState),
            battery: BatteryInfo.read(health: health), chip: chip)
    }
}
