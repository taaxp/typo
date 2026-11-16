import Foundation
import CoreGraphics
import Vision

/// Confirms a rendered code actually scans, using Vision (iOS 18 / macOS 15+).
/// Used after every style change in the studio and in unit tests.
enum ScanCheck {
    enum Result: Equatable {
        case scans
        case wrongContent(String)
        case unreadable
    }

    static func verify(_ image: CGImage, expecting message: String) async -> Result {
        let request = DetectBarcodesRequest()
        guard let observations = try? await request.perform(on: image, orientation: nil), !observations.isEmpty else {
            return .unreadable
        }
        let payloads = observations.compactMap(\.payloadString)
        if payloads.contains(message) { return .scans }
        return payloads.first.map { .wrongContent($0) } ?? .unreadable
    }

    /// Every code payload found in an image (QR codes in screenshots and photos).
    static func payloads(in image: CGImage) async -> [String] {
        let request = DetectBarcodesRequest()
        let observations = (try? await request.perform(on: image, orientation: nil)) ?? []
        return observations.compactMap(\.payloadString)
    }

    static func payloads(in data: Data) async -> [String] {
        let request = DetectBarcodesRequest()
        let observations = (try? await request.perform(on: data, orientation: nil)) ?? []
        return observations.compactMap(\.payloadString)
    }
}
