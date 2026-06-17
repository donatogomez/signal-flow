import Foundation
import CoreKit
import DomainKit

/// Builders for ready-made fleets, so a feature can spin up a realistic, multi-device simulation in
/// one line.
public enum SimulationFleet {

    /// A heterogeneous fleet of 10 devices — 3 greenhouses, 3 refrigerated trucks, 2 warehouses, and
    /// 2 environmental stations — each with an independent, deterministically derived seed.
    ///
    /// - Parameters:
    ///   - seed: Base seed; per-device seeds are derived from it, so the whole fleet is reproducible.
    ///   - clock: Drives both timestamps and pacing.
    ///   - maxTicks: Optional cap on ticks per device (`nil` runs until cancelled).
    public static func standard(
        seed: UInt64 = 42,
        clock: any SimulationClock,
        maxTicks: Int? = nil
    ) -> SimulationEngineActor {
        let blueprint: [(kind: AssetKind, name: String)] = [
            (.greenhouse, "Greenhouse A"),
            (.greenhouse, "Greenhouse B"),
            (.greenhouse, "Greenhouse C"),
            (.refrigeratedTruck, "Reefer 12"),
            (.refrigeratedTruck, "Reefer 19"),
            (.refrigeratedTruck, "Reefer 27"),
            (.warehouse, "Warehouse North"),
            (.warehouse, "Warehouse South"),
            (.environmentalStation, "Station Alpha"),
            (.environmentalStation, "Station Beta"),
        ]

        var rng = SeededRandomNumberGenerator(seed: seed)
        let devices = blueprint.map { entry in
            SimulatedDeviceActor(
                name: entry.name,
                assetKind: entry.kind,
                profile: .make(for: entry.kind),
                clock: clock,
                seed: rng.next()
            )
        }

        return SimulationEngineActor(clock: clock, maxTicks: maxTicks, devices: devices)
    }
}
