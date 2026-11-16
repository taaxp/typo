import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// Barcode formats Typo can draw.
enum Symbology: String, Codable, CaseIterable, Identifiable, Sendable {
    case qr, aztec, pdf417, code128, ean13, upcA

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qr: "QR code"
        case .aztec: "Aztec"
        case .pdf417: "PDF417"
        case .code128: "Code 128"
        case .ean13: "EAN-13"
        case .upcA: "UPC-A"
        }
    }

    /// 1D barcodes are drawn as bars and cannot be decorated.
    var isLinear: Bool { self == .code128 || self == .ean13 || self == .upcA }
}

enum QRCorrection: String, Codable, Sendable {
    case low = "L", medium = "M", quartile = "Q", high = "H"
}

/// A grid of dark (`true`) and light modules with no quiet zone.
struct ModuleMatrix: Equatable, Sendable {
    let width: Int
    let height: Int
    let bits: [Bool]

    subscript(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        return bits[y * width + x]
    }
}

enum CodeError: LocalizedError {
    case empty
    case invalidDigits(String)
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .empty: "There's nothing to encode yet."
        case .invalidDigits(let why): why
        case .generationFailed: "That content can't be turned into this kind of code."
        }
    }
}

enum CodeGenerator {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func matrix(for message: String, symbology: Symbology, correction: QRCorrection = .medium) throws -> ModuleMatrix {
        guard !message.isEmpty else { throw CodeError.empty }
        switch symbology {
        case .ean13:
            return try EAN.matrix(for: message, upc: false)
        case .upcA:
            return try EAN.matrix(for: message, upc: true)
        case .qr:
            let f = CIFilter.qrCodeGenerator()
            f.message = Data(message.utf8)
            f.correctionLevel = correction.rawValue
            return try read(f.outputImage, linear: false)
        case .aztec:
            let f = CIFilter.aztecCodeGenerator()
            f.message = Data(message.utf8)
            return try read(f.outputImage, linear: false)
        case .pdf417:
            let f = CIFilter.pdf417BarcodeGenerator()
            f.message = Data(message.utf8)
            return try read(f.outputImage, linear: false)
        case .code128:
            let f = CIFilter.code128BarcodeGenerator()
            // Code 128 in CoreImage takes ASCII only.
            guard let data = message.data(using: .ascii) else { throw CodeError.invalidDigits("Code 128 supports plain letters, numbers and symbols only.") }
            f.message = data
            f.quietSpace = 0
            return try read(f.outputImage, linear: true)
        }
    }

    /// Reads a 1-pixel-per-module CoreImage barcode into a matrix, trimming any
    /// quiet zone the generator added (so the renderer controls the margin).
    private static func read(_ image: CIImage?, linear: Bool) throws -> ModuleMatrix {
        guard let image, let cg = context.createCGImage(image, from: image.extent.integral) else {
            throw CodeError.generationFailed
        }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 255, count: w * h)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { throw CodeError.generationFailed }
        // Bitmap memory is top row first.
        var dark = pixels.map { $0 < 128 }
        var width = w, height = h
        if linear {
            // Use the middle row of a 1D barcode.
            let row = h / 2
            dark = Array(dark[(row * w)..<(row * w + w)])
            height = 1
        }
        return trim(ModuleMatrix(width: width, height: height, bits: dark))
    }

    static func trim(_ m: ModuleMatrix) -> ModuleMatrix {
        var minX = m.width, minY = m.height, maxX = -1, maxY = -1
        for y in 0..<m.height { for x in 0..<m.width where m[x, y] {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= minX, maxY >= minY else { return m }
        var bits: [Bool] = []
        for y in minY...maxY { for x in minX...maxX { bits.append(m[x, y]) } }
        return ModuleMatrix(width: maxX - minX + 1, height: maxY - minY + 1, bits: bits)
    }
}

/// EAN-13 and UPC-A. CoreImage has no generator for these retail formats, so
/// Typo encodes them itself. UPC-A is EAN-13 with a leading zero.
enum EAN {
    private static let left: [String] = ["0001101", "0011001", "0010011", "0111101", "0100011",
                                         "0110001", "0101111", "0111011", "0110111", "0001011"]
    private static let parity: [String] = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG",
                                           "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"]

    private static func right(_ d: Int) -> String { String(left[d].map { $0 == "0" ? "1" : "0" }) }
    private static func g(_ d: Int) -> String { String(right(d).reversed()) }

    /// Check digit for the first 12 (EAN-13) or 11 (UPC-A) digits.
    static func checkDigit(_ digits: [Int]) -> Int {
        // Weights alternate 1,3 from the left for EAN-13 (12 digits); UPC-A is the same after a leading 0.
        let padded = digits.count == 11 ? [0] + digits : digits
        let sum = padded.enumerated().reduce(0) { $0 + $1.element * ($1.offset % 2 == 0 ? 1 : 3) }
        return (10 - sum % 10) % 10
    }

    /// Normalises input to 13 digits with a valid check digit, or throws.
    static func normalised(_ input: String, upc: Bool) throws -> [Int] {
        let digits = input.compactMap { $0.wholeNumberValue }
        guard digits.count == input.filter({ !$0.isWhitespace }).count else {
            throw CodeError.invalidDigits("Use digits only.")
        }
        let body = upc ? 11 : 12
        switch digits.count {
        case body:
            let full = digits + [checkDigit(digits)]
            return upc ? [0] + full : full
        case body + 1:
            guard checkDigit(Array(digits.prefix(body))) == digits[body] else {
                throw CodeError.invalidDigits("The last digit doesn't match. Check the number on the card.")
            }
            return upc ? [0] + digits : digits
        default:
            throw CodeError.invalidDigits(upc ? "UPC-A numbers have 12 digits." : "EAN-13 numbers have 13 digits.")
        }
    }

    static func pattern(for digits13: [Int]) -> String {
        let first = digits13[0]
        var s = "101"
        for (i, d) in digits13[1...6].enumerated() {
            s += parity[first][parity[first].index(parity[first].startIndex, offsetBy: i)] == "L" ? left[d] : g(d)
        }
        s += "01010"
        for d in digits13[7...12] { s += right(d) }
        return s + "101"
    }

    static func matrix(for input: String, upc: Bool) throws -> ModuleMatrix {
        let digits = try normalised(input, upc: upc)
        let bits = pattern(for: digits).map { $0 == "1" }
        return ModuleMatrix(width: bits.count, height: 1, bits: bits)
    }
}
