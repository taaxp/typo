import SwiftUI

/// Draws a module matrix with a `CodeStyle`. Used for the live preview, the
/// presentation screen, widgets snapshots and PNG export (via `ImageRenderer`).
struct CodeCanvas: View {
    let matrix: ModuleMatrix
    let symbology: Symbology
    var style: CodeStyle = .default
    /// Quiet zone in modules. QR needs 4 by spec; we use 4 for 2D and 10 for 1D.
    var quietZone: Int { symbology.isLinear ? 10 : 4 }

    var body: some View {
        if symbology.isLinear {
            linear
        } else {
            matrixCanvas.aspectRatio(CGFloat(matrix.width + quietZone * 2) / CGFloat(matrix.height + quietZone * 2), contentMode: .fit)
        }
    }

    // MARK: 2D codes

    private var fillStyle: GraphicsContext.Shading {
        guard let name = style.fillHue else { return .color(Color(hex: CodeStyle.plainInk)) }
        let hue = Hues.named(name)
        // Deep end of the hue to its ink: always dark enough to scan.
        return .linearGradient(Gradient(colors: [hue.bottomColor.mix(with: hue.inkColor, by: 0.35), hue.inkColor]),
                               startPoint: .zero, endPoint: CGPoint(x: 1, y: 1))
    }

    private var eyeColor: Color {
        let name = style.eyeHue ?? style.fillHue
        guard let name else { return Color(hex: CodeStyle.plainInk) }
        return Hues.named(name).inkColor
    }

    private var matrixCanvas: some View {
        Canvas { ctx, size in
            let cols = CGFloat(matrix.width + quietZone * 2)
            let m = min(size.width, size.height) / cols          // module size in points
            let origin = CGPoint(x: (size.width - m * cols) / 2 + m * CGFloat(quietZone),
                                 y: (size.height - m * cols) / 2 + m * CGFloat(quietZone))
            let isQR = symbology == .qr
            let badgeRect = badgeModuleRect()

            func rect(_ x: Int, _ y: Int) -> CGRect {
                CGRect(x: origin.x + CGFloat(x) * m, y: origin.y + CGFloat(y) * m, width: m, height: m)
            }

            var path = Path()
            for y in 0..<matrix.height {
                for x in 0..<matrix.width where matrix[x, y] {
                    if isQR && inFinder(x, y) { continue }
                    if let badgeRect, badgeRect.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) { continue }
                    let r = rect(x, y)
                    switch style.moduleShape {
                    case .square:
                        path.addRect(r.insetBy(dx: -0.25, dy: -0.25))
                    case .rounded:
                        path.addRoundedRect(in: r.insetBy(dx: m * 0.04, dy: m * 0.04), cornerSize: CGSize(width: m * 0.3, height: m * 0.3))
                    case .dots:
                        path.addEllipse(in: r.insetBy(dx: m * 0.08, dy: m * 0.08))
                    case .fluid:
                        path.addEllipse(in: r)
                        if matrix[x + 1, y] && !(isQR && inFinder(x + 1, y)) { path.addRect(CGRect(x: r.midX, y: r.minY, width: m, height: m)) }
                        if matrix[x, y + 1] && !(isQR && inFinder(x, y + 1)) { path.addRect(CGRect(x: r.minX, y: r.midY, width: m, height: m)) }
                    }
                }
            }
            ctx.fill(path, with: fillStyle)

            if isQR {
                for (ex, ey) in [(0, 0), (matrix.width - 7, 0), (0, matrix.height - 7)] {
                    drawEye(ctx: &ctx, at: rect(ex, ey).origin, module: m)
                }
            }

            if let badgeRect, let badge = style.badge {
                let r = CGRect(x: origin.x + badgeRect.minX * m, y: origin.y + badgeRect.minY * m,
                               width: badgeRect.width * m, height: badgeRect.height * m).insetBy(dx: m * 0.4, dy: m * 0.4)
                ctx.fill(Path(roundedRect: r, cornerRadius: r.width * 0.28), with: .color(.white))
                let inner = r.insetBy(dx: r.width * 0.14, dy: r.height * 0.14)
                switch badge {
                case .symbol(let name):
                    var symbol = ctx.resolve(Image(systemName: name))
                    symbol.shading = .color(eyeColor)
                    ctx.draw(symbol, in: inner)
                case .emoji(let emoji):
                    ctx.draw(Text(emoji).font(.system(size: inner.height * 0.8)), in: inner)
                case .photo(let data):
                    if let image = PlatformImageDecoder.image(from: data) {
                        ctx.clip(to: Path(roundedRect: inner, cornerRadius: inner.width * 0.22))
                        ctx.draw(image.resizable(), in: inner)
                    }
                }
            }
        }
    }

    private func inFinder(_ x: Int, _ y: Int) -> Bool {
        let w = matrix.width, h = matrix.height
        return (x < 7 && y < 7) || (x >= w - 7 && y < 7) || (x < 7 && y >= h - 7)
    }

    /// Badge area in module coordinates, centred, ≤ 20% of the width, odd-aligned.
    private func badgeModuleRect() -> CGRect? {
        guard style.badge != nil, symbology == .qr else { return nil }
        let side = max(5, Int(Double(matrix.width) * 0.2) | 1)
        let start = (matrix.width - side) / 2
        return CGRect(x: start, y: start, width: side, height: side)
    }

    private func drawEye(ctx: inout GraphicsContext, at origin: CGPoint, module m: CGFloat) {
        let outer = CGRect(origin: origin, size: CGSize(width: 7 * m, height: 7 * m))
        let ring = outer.insetBy(dx: m * 0.5, dy: m * 0.5)
        let pupil = outer.insetBy(dx: 2 * m, dy: 2 * m)
        let colour = GraphicsContext.Shading.color(eyeColor)
        let lineWidth = m

        func shape(_ r: CGRect, _ kind: CodeStyle.EyeShape) -> Path {
            switch kind {
            case .square: return Path(r)
            case .rounded: return Path(roundedRect: r, cornerRadius: r.width * 0.28)
            case .circle: return Path(ellipseIn: r)
            case .leaf:
                let rad = r.width * 0.45
                return Path { p in
                    p.move(to: CGPoint(x: r.minX, y: r.minY))
                    p.addLine(to: CGPoint(x: r.maxX - rad, y: r.minY))
                    p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + rad), radius: rad)
                    p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
                    p.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY))
                    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - rad), radius: rad)
                    p.closeSubpath()
                }
            }
        }
        ctx.stroke(shape(ring, style.eyeShape), with: colour, lineWidth: lineWidth)
        ctx.fill(shape(pupil, style.eyeShape), with: colour)
    }

    // MARK: 1D codes

    private var linear: some View {
        Canvas { ctx, size in
            let cols = CGFloat(matrix.width + quietZone * 2)
            let m = size.width / cols
            var path = Path()
            var x = 0
            while x < matrix.width {
                if matrix[x, 0] {
                    var run = 1
                    while x + run < matrix.width && matrix[x + run, 0] { run += 1 }
                    path.addRect(CGRect(x: CGFloat(quietZone + x) * m, y: 0, width: CGFloat(run) * m, height: size.height))
                    x += run
                } else { x += 1 }
            }
            // Retail and member barcodes stay pure black for scanners.
            ctx.fill(path, with: .color(.black))
        }
        .aspectRatio(2.6, contentMode: .fit)
    }
}

/// A finished, shareable code: background plate, optional frame and caption.
struct CodeCard: View {
    let matrix: ModuleMatrix
    let symbology: Symbology
    var style: CodeStyle = .default
    var humanReadable: String? = nil

    var body: some View {
        let hue = Hues.named(style.fillHue ?? "Fog")
        VStack(spacing: 14) {
            CodeCanvas(matrix: matrix, symbology: symbology, style: style)
                .padding(symbology.isLinear ? 12 : 0)
                .background(plate, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            if let humanReadable, symbology.isLinear {
                Text(humanReadable).font(.system(.title3, design: .monospaced).weight(.semibold)).tracking(2)
                    .foregroundStyle(.black)
            }
            if style.showFrame && !style.caption.isEmpty {
                Text(style.caption)
                    .font(.headline)
                    .foregroundStyle(hue.inkColor)
            }
        }
        .padding(style.showFrame ? 22 : 0)
        .background {
            if style.showFrame {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(hue.softGradient)
                    .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(.white.opacity(0.55)))
                    .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 1))
            }
        }
    }

    private var plate: AnyShapeStyle {
        switch style.background {
        case .white, .clear: AnyShapeStyle(Color.white)
        case .soft:
            // Very pale tint: keeps contrast with the dark modules high.
            AnyShapeStyle(Hues.named(style.fillHue ?? "Fog").topColor.mix(with: .white, by: 0.8))
        }
    }
}

/// PNG export of a `CodeCard`.
@MainActor
enum CodeExporter {
    static func png(matrix: ModuleMatrix, symbology: Symbology, style: CodeStyle, humanReadable: String? = nil,
                    width: CGFloat = 900) -> Data? {
        let card = CodeCard(matrix: matrix, symbology: symbology, style: style, humanReadable: humanReadable)
            .frame(width: width)
            .padding(style.showFrame ? 0 : 24)
            .background(style.background == .clear && style.showFrame ? Color.clear : Color.white)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        #if canImport(UIKit)
        return renderer.uiImage?.pngData()
        #elseif canImport(AppKit)
        guard let cg = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        #endif
    }

    static func cgImage(matrix: ModuleMatrix, symbology: Symbology, style: CodeStyle, width: CGFloat = 600) -> CGImage? {
        let renderer = ImageRenderer(content: CodeCard(matrix: matrix, symbology: symbology, style: style)
            .frame(width: width).padding(24).background(Color.white))
        renderer.scale = 1
        return renderer.cgImage
    }
}

/// Decodes small badge photos on either platform.
enum PlatformImageDecoder {
    static func image(from data: Data) -> Image? {
        #if canImport(UIKit)
        UIImage(data: data).map { Image(uiImage: $0) }
        #elseif canImport(AppKit)
        NSImage(data: data).map { Image(nsImage: $0) }
        #endif
    }
}
