import Testing
import Foundation
@testable import Typo

@Suite("QR payloads")
struct QRPayloadTests {
    @Test func wifiEscapesSpecialCharactersBackslashFirst() {
        let network = WiFiNetwork(ssid: #"Home;Net"#, password: #"p@ss:w,rd"\"#, security: .wpa)
        #expect(QRPayload.wifi(network) == #"WIFI:T:WPA;S:Home\;Net;P:p@ss\:w\,rd\"\\;;"#)
    }

    @Test func wifiRoundTrips() {
        let original = WiFiNetwork(ssid: "Café Guest", password: #"semi;colon:comma,quote"back\slash"#, security: .wpa, hidden: true)
        #expect(QRPayload.parseWiFi(QRPayload.wifi(original)) == original)
    }

    @Test func openNetworkHasNoPassword() {
        let network = WiFiNetwork(ssid: "Lobby", password: "ignored", security: .open)
        #expect(QRPayload.wifi(network) == "WIFI:T:nopass;S:Lobby;;")
        #expect(QRPayload.parseWiFi("WIFI:T:nopass;S:Lobby;;")?.security == .open)
    }

    @Test func parsesFieldsInAnyOrder() {
        let parsed = QRPayload.parseWiFi("WIFI:S:Office;P:secret123;T:WPA;H:false;;")
        #expect(parsed == WiFiNetwork(ssid: "Office", password: "secret123", security: .wpa, hidden: false))
    }

    @Test func classifiesScannedPayloads() {
        #expect(QRPayload.parse("https://www.swift.org") == .link(URL(string: "https://www.swift.org")!))
        #expect(QRPayload.parse("tel:+61400000000") == .phone("+61400000000"))
        #expect(QRPayload.parse("SMSTO:+61400000000:Hello") == .sms(number: "+61400000000", body: "Hello"))
        #expect(QRPayload.parse("geo:-37.822600,144.965400") == .location(latitude: -37.8226, longitude: 144.9654))
        #expect(QRPayload.parse("just some words") == .text("just some words"))
        if case .wifi = QRPayload.parse("WIFI:T:WPA;S:A;P:b;;") {} else { Issue.record("Wi-Fi not detected") }
        if case .contact = QRPayload.parse("BEGIN:VCARD\r\nVERSION:3.0\r\nEND:VCARD") {} else { Issue.record("vCard not detected") }
    }

    @Test func vCardEscapesValues() {
        var card = ContactCard()
        card.givenName = "Alex"
        card.familyName = "Example"
        card.organisation = "Acme; Pty, Ltd"
        let vcard = QRPayload.contact(card)
        #expect(vcard.contains("ORG:Acme\\; Pty\\, Ltd"))
        #expect(vcard.hasPrefix("BEGIN:VCARD\r\nVERSION:3.0"))
        #expect(vcard.hasSuffix("END:VCARD"))
    }

    @Test func draftKeepsWiFiPasswordOutOfStoredPayload() {
        var draft = CodeDraft()
        draft.type = .wifi
        draft.wifi = WiFiNetwork(ssid: "Guest", password: "do-not-store")
        #expect(!draft.storedPayload().contains("do-not-store"))
        #expect(draft.secret == "do-not-store")
        #expect(draft.message.contains("P:do-not-store;"))
    }
}
