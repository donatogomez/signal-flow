import Foundation
import DomainKit

/// Coordinates a fleet of ``SimulatedDeviceActor``s and exposes their telemetry as merged or
/// per-device `AsyncStream`s.
///
/// The engine is an actor because it owns a **mutable device registry** (devices can be added at
/// runtime). Stream production itself is delegated to free functions running in a `TaskGroup`, so the
/// many device actors run concurrently rather than serializing on the engine.
public actor SimulationEngineActor {
    private let clock: any SimulationClock
    private let maxTicks: Int?
    private var devices: [SimulatedDeviceActor]

    public init(clock: any SimulationClock, maxTicks: Int? = nil, devices: [SimulatedDeviceActor] = []) {
        self.clock = clock
        self.maxTicks = maxTicks
        self.devices = devices
    }

    public func add(_ device: SimulatedDeviceActor) {
        devices.append(device)
    }

    public var deviceCount: Int { devices.count }

    public func descriptors() -> [DeviceDescriptor] {
        devices.map(\.descriptor)
    }

    /// A single stream merging every device's telemetry. Items from different devices interleave in
    /// real-time order; each device's own substream stays deterministic. Cancelling the consumer (or
    /// the underlying task) tears down the whole task group promptly.
    public func makeFleetStream() -> AsyncStream<DeviceTelemetry> {
        let devices = self.devices
        let clock = self.clock
        let maxTicks = self.maxTicks

        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    for device in devices {
                        group.addTask {
                            await pumpDevice(device, clock: clock, maxTicks: maxTicks, into: continuation)
                        }
                    }
                    await group.waitForAll()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A stream for a single device, or `nil` if it isn't in the fleet.
    public func makeStream(for id: DeviceID) -> AsyncStream<DeviceTelemetry>? {
        guard let device = devices.first(where: { $0.id == id }) else { return nil }
        return device.makeTelemetryStream(clock: clock, maxTicks: maxTicks)
    }
}
