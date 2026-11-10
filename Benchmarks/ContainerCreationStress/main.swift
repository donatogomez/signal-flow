import Foundation
import Synchronization
import PersistenceKit

// Reproduction harness for issue #30: creating new stores on several threads at once could crash the
// process inside Core Data. Only the first creations in a process are exposed, so a run is one
// process that creates `threads` new stores at the same moment, and a crash ends that process with a
// signal. Measure by repeating it in fresh processes:
//
//   swift build --product ContainerCreationStress
//   for i in $(seq 500); do .build/debug/ContainerCreationStress memory 8 >/dev/null || echo crash; done | grep -c crash
//
// Arguments: `memory` (default) or `disk` (new stores in a temporary directory), then the thread
// count (default 8). It prints the time to create all stores.

let arguments = CommandLine.arguments
let onDisk = arguments.count > 1 && arguments[1] == "disk"
let threads = arguments.count > 2 ? Int(arguments[2]) ?? 8 : 8
let directory = FileManager.default.temporaryDirectory.appending(path: "container-stress-\(UUID().uuidString)")

let stores = Mutex<[PersistenceStore]>([])
let failures = Atomic<Int>(0)
let start = ContinuousClock.now
DispatchQueue.concurrentPerform(iterations: threads) { index in
    do {
        let container = onDisk
            ? try PersistenceController.makeContainer(url: directory.appending(path: "\(index).store"))
            : try PersistenceController.makeInMemoryContainer()
        let store = PersistenceStore(modelContainer: container)
        stores.withLock { $0.append(store) }
    } catch {
        failures.add(1, ordering: .relaxed)
        print("Creating a store failed: \(error)")
    }
}
let elapsed = ContinuousClock.now - start

for store in stores.withLock({ $0 }) {
    let count = try await store.readingCount()
    precondition(count == 0, "a new store should be empty")
}
try? FileManager.default.removeItem(at: directory)
print("Created \(threads - failures.load(ordering: .relaxed)) of \(threads) \(onDisk ? "on-disk" : "in-memory") stores in \(elapsed)")
exit(failures.load(ordering: .relaxed) == 0 ? 0 : 1)
