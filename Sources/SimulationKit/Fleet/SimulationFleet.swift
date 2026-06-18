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

        // Device and asset identities are derived from the seed (not random), so the same fleet —
        // same ids — is reproduced on every launch. That stable identity is what lets persisted
        // telemetry line up with the regenerated fleet, and keeps persistence idempotent.
        var rng = SeededRandomNumberGenerator(seed: seed)
        let devices = blueprint.map { entry in
            let assetID = AssetID(rng.nextUUID())
            let deviceID = DeviceID(rng.nextUUID())
            let deviceSeed = rng.next()
            return SimulatedDeviceActor(
                id: deviceID,
                assetID: assetID,
                name: entry.name,
                assetKind: entry.kind,
                profile: .make(for: entry.kind),
                clock: clock,
                seed: deviceSeed
            )
        }

        return SimulationEngineActor(clock: clock, maxTicks: maxTicks, devices: devices)
    }
}
