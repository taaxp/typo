import Testing
@testable import Typo

@Suite("Payment cards")
struct CardNumberTests {
    // Public test numbers published by card networks for testing; not real accounts.
    @Test(arguments: ["4111111111111111", "5555555555554444", "378282246310005", "2223003122003222"])
    func luhnAcceptsTestNumbers(_ number: String) {
        #expect(CardNumber.isValid(number))
    }

    @Test func luhnRejectsTypos() {
        #expect(!CardNumber.isValid("4111111111111112"))
        #expect(!CardNumber.isValid("1234"))
    }

    @Test func detectsNetworks() {
        #expect(CardNumber.network("4111 1111 1111 1111") == .visa)
        #expect(CardNumber.network("5555555555554444") == .mastercard)
        #expect(CardNumber.network("2223003122003222") == .mastercard)
        #expect(CardNumber.network("378282246310005") == .amex)
    }

    @Test func formatsAndMasks() {
        #expect(CardNumber.formatted("4111111111111111") == "4111 1111 1111 1111")
        #expect(CardNumber.formatted("378282246310005") == "3782 822463 10005")
        #expect(CardNumber.masked("4111111111111111") == "•••• 1111")
    }

    @Test func normalisesExpiry() {
        #expect(CardNumber.normalisedExpiry("7/27") == nil)          // ambiguous, needs MM
        #expect(CardNumber.normalisedExpiry("07/27") == "07/27")
        #expect(CardNumber.normalisedExpiry("0727") == "07/27")
        #expect(CardNumber.normalisedExpiry("07/2027") == "07/27")
        #expect(CardNumber.normalisedExpiry("13/27") == nil)
    }

    @Test func extractsFromOCRLinesAndIgnoresSecurityCode() {
        let lines = ["BANK OF EXAMPLE", "4111 1111 1111 1111", "VALID THRU 09/28", "ALEX EXAMPLE", "CVV 123"]
        let result = CardNumber.extract(fromLines: lines)
        #expect(result.number == "4111111111111111")
        #expect(result.expiry == "09/28")
        #expect(result.name == "ALEX EXAMPLE")
    }
}
