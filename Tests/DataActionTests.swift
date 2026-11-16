import Testing
@testable import Typo

@Suite("Data actions")
struct DataActionTests {
    @Test func findsPhoneAndLink() {
        let actions = DataAction.detect(in: "Call 03 9000 0000 or see https://www.example.com")
        #expect(actions.contains { if case .phone = $0.kind { return true }; return false })
        #expect(actions.contains { if case .link = $0.kind { return true }; return false })
    }
}
