import Foundation
import CoreKit
import DomainKit

/// Simulates a single IoT device. The actor **owns all mutable simulation state** (signal models,
/// door/connectivity/motion state machines, the RNG, the tick counter), so progression is serialized
/// and free of data races by construction — there is no lock anywhere.
///
/// Identity fields are `nonisolated let`, so the engine can list its fleet without awaiting; the
/// evolving state is fully isolated. `advance()` is the deterministic heart: given the same seed and
/// the same number of calls, it produces an identical telemetry sequence every time.
public actor SimulatedDeviceActor {
    public nonisolated let id: DeviceID
    public nonisolated let assetID: AssetID
    public nonisolated let name: String
    public nonisolated let assetKind: AssetKind

    private let origin: Date
    private let secondsPerTick: Double

    private var profile: SimulationProfile
    private var rng: SeededRandomNumberGenerator
    private var tickIndex = 0

    // Discrete state machines.
    private var doorOpenTicksRemaining = 0
    private var outageTicksRemaining = 0
    private var isOnline = true
    private var motion: MotionState?
    private var batteryLowLatched = false

    public init(
        id: DeviceID = DeviceID(),
        assetID: AssetID = AssetID(),
        name: String,
        assetKind: AssetKind,
        profile: SimulationProfile,
        clock: any SimulationClock,
        seed: UInt64
    ) {
        self.id = id
        self.assetID = assetID
        self.name = name
        self.assetKind = assetKind
        self.origin = clock.origin
        self.secondsPerTick = clock.tick.inSeconds
        self.profile = profile
        self.motion = profile.motion.map(MotionState.init)
        var rng = SeededRandomNumberGenerator(seed: seed)
        for index in self.profile.metrics.indices {
            self.profile.metrics[index].applyInitialVariation(using: &rng)
        }
        self.rng = rng
    }

    public nonisolated var descriptor: DeviceDescriptor {
        DeviceDescriptor(id: id, assetID: assetID, name: name, assetKind: assetKind)
    }

    /// Advances the simulation by one tick and returns everything the device emits for it.
    public func advance() -> [DeviceTelemetry] {
        let date = origin.addingTimeInterval(secondsPerTick * Double(tickIndex))
        let sinceOrigin = secondsPerTick * Double(tickIndex)
        defer { tickIndex += 1 }

        var output: [DeviceTelemetry] = []

        // 1. Connectivity. While offline, the device stays silent except for the restore event.
        if !isOnline {
            outageTicksRemaining -= 1
            guard outageTicksRemaining <= 0 else { return output }
            isOnline = true
            output.append(event(.connected, at: date))
        } else if rng.chance(profile.connectivity.dropProbability) {
            isOnline = false
            outageTicksRemaining = Int.random(in: profile.connectivity.outageDurationTicks, using: &rng)
            output.append(event(.disconnected, at: date))
            return output
        }

        // 2. Door (warms the cabin while open).
        let temperatureOffset = advanceDoor(at: date, into: &output)

        // 3. Metrics → readings + threshold/battery events.
        for index in profile.metrics.indices {
            let offset = profile.metrics[index].metric == .temperature ? temperatureOffset : 0
            let sample = profile.metrics[index].sample(sinceOrigin: sinceOrigin, offset: offset, using: &rng)
            let unit = profile.metrics[index].unit
            let metric = profile.metrics[index].metric

            if let value = try? MeasuredValue(magnitude: sample.magnitude, unit: unit) {
                output.append(.reading(TelemetryReading(
                    id: ReadingID(rng.nextUUID()), deviceID: id, metric: metric, value: value, recordedAt: date
                )))
            }
            if sample.breachedSafeRange {
                output.append(event(.custom("threshold_exceeded"), at: date,
                                     detail: "\(metric.displayName) \(formatted(sample.magnitude)) \(unit.symbol)"))
            }
            if metric == .batteryLevel {
                appendBatteryEvents(magnitude: sample.magnitude, at: date, into: &output)
            }
        }

        // 4. Motion → position update.
        if var current = motion {
            current.advance(using: &rng)
            motion = current
            if let location = try? Location(latitude: current.latitude, longitude: current.longitude) {
                output.append(.location(deviceID: id, location: location, recordedAt: date))
            }
        }

        return output
    }

    // MARK: - Helpers

    private func advanceDoor(at date: Date, into output: inout [DeviceTelemetry]) -> Double {
        guard let door = profile.door else { return 0 }
        if doorOpenTicksRemaining > 0 {
            doorOpenTicksRemaining -= 1
            if doorOpenTicksRemaining == 0 { output.append(event(.doorClosed, at: date)) }
            return door.temperatureOffset
        }
        if rng.chance(door.openProbability) {
            doorOpenTicksRemaining = Int.random(in: door.openDurationTicks, using: &rng)
            output.append(event(.doorOpened, at: date))
            return door.temperatureOffset
        }
        return 0
    }

    private func appendBatteryEvents(magnitude: Double, at date: Date, into output: inout [DeviceTelemetry]) {
        if magnitude <= 15, !batteryLowLatched {
            batteryLowLatched = true
            output.append(event(.custom("battery_low"), at: date, detail: "\(Int(magnitude))%"))
        } else if magnitude > 20 {
            batteryLowLatched = false
        }
    }

    private func event(_ kind: DeviceEvent.Kind, at date: Date, detail: String? = nil) -> DeviceTelemetry {
        .event(DeviceEvent(id: EventID(rng.nextUUID()), deviceID: id, kind: kind, occurredAt: date, detail: detail))
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
