import Testing
import Foundation
import CoreGraphics
@testable import Typo

@Suite("Barcodes and rendering")
struct BarcodeTests {
    @Test func eanCheckDigit() throws {
        // Example numbers from public EAN/UPC documentation.
        #expect(EAN.checkDigit([4, 0, 0, 6, 3, 8, 1, 3, 3, 3, 9, 3]) == 1)
        #expect(try EAN.normalised("400638133393", upc: false).last == 1)
        #expect(throws: CodeError.self) { try EAN.normalised("4006381333932", upc: false) }
        #expect(try EAN.normalised("036000291452", upc: true).count == 13)
    }

    @Test func eanPatternHas95Modules() throws {
        let m = try CodeGenerator.matrix(for: "4006381333931", symbology: .ean13)
        #expect(m.width == 95 && m.height == 1)
        #expect(m[0, 0] && !m[1, 0] && m[2, 0])   // start guard 101
    }

    @Test func qrMatrixIsSquareWithFinders() throws {
        let m = try CodeGenerator.matrix(for: "https://www.swift.org", symbology: .qr)
        #expect(m.width == m.height)
        #expect(m.width >= 21)
        // Top-left finder: dark 7×7 border.
        #expect((0..<7).allSatisfy { m[$0, 0] && m[0, $0] })
    }

    /// Every style preset must still scan after decoration.
    @MainActor
    @Test(arguments: CodeStyle.presets.map(\.name))
    func presetsScan(_ name: String) async throws {
        var style = try #require(CodeStyle.presets.first { $0.name == name }).style
        style.caption = "Scan for Wi-Fi"
        let message = QRPayload.wifi(WiFiNetwork(ssid: "Guest", password: "p;a:s,s"))
        let matrix = try CodeGenerator.matrix(for: message, symbology: .qr, correction: style.correction)
        let image = try #require(CodeExporter.cgImage(matrix: matrix, symbology: .qr, style: style))
        #expect(await ScanCheck.verify(image, expecting: message) == .scans)
    }

    @MainActor
    @Test func badgeForcesHighCorrectionAndStillScans() async throws {
        var style = CodeStyle.presets[1].style
        style.badge = .symbol("wifi")
        #expect(style.correction == .high)
        let matrix = try CodeGenerator.matrix(for: "https://example.com/menu", symbology: .qr, correction: style.correction)
        let image = try #require(CodeExporter.cgImage(matrix: matrix, symbology: .qr, style: style))
        #expect(await ScanCheck.verify(image, expecting: "https://example.com/menu") == .scans)
    }
}
