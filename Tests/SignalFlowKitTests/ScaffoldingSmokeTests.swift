import Testing
@testable import DomainKit
import TestingSupportKit

/// Smoke tests for the scaffolding step.
///
/// These exist only to prove the test stack runs and that `TestingSupportKit` is consumable from a
/// test target. They will be replaced by real domain tests as logic lands.
@Suite("Scaffolding smoke")
struct ScaffoldingSmokeTests {

    @Test("DomainKit links and exposes its module marker")
    func domainModuleLinks() {
        #expect(DomainKit.moduleName == "DomainKit")
    }

    @Test("TestingSupportKit links and exposes its module marker")
    func testingSupportModuleLinks() {
        #expect(TestingSupportKit.moduleName == "TestingSupportKit")
    }
}
