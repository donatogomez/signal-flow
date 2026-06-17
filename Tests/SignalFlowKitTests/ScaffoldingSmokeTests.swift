import Testing
import TestingSupportKit

/// Smoke test for the package wiring. `DomainKit`'s placeholder marker was removed once real types
/// landed; `DomainKit`'s behavior is covered by the dedicated suites in this target.
@Suite("Scaffolding smoke")
struct ScaffoldingSmokeTests {

    @Test("TestingSupportKit links and exposes its module marker")
    func testingSupportModuleLinks() {
        #expect(TestingSupportKit.moduleName == "TestingSupportKit")
    }
}
