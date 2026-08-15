import AppKit

// The icon is drawn in code: no binary asset in the repository, and the artwork always
// matches the source. Run: swift make-icon.swift <folder.iconset>

let canvas: CGFloat = 1024

func draw(in ctx: CGContext) {
    // Body: 824×824 centred on a 1024 canvas — the standard macOS icon grid.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(srgbRed: 0.40, green: 0.44, blue: 0.93, alpha: 1),
            CGColor(srgbRed: 0.09, green: 0.10, blue: 0.33, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 512, y: 924),
                           end: CGPoint(x: 512, y: 100),
                           options: [])
    ctx.restoreGState()

    // Crescent: a circle minus an offset circle.
    let outer = CGPath(ellipseIn: CGRect(x: 185, y: 205, width: 450, height: 450), transform: nil)
    let inner = CGPath(ellipseIn: CGRect(x: 310, y: 227, width: 405, height: 405), transform: nil)
    ctx.addPath(outer.subtracting(inner))
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillPath()

    // Zzz trailing off towards the upper right.
    for (text, point, size) in [("z", CGPoint(x: 612, y: 545), 195.0),
                                ("z", CGPoint(x: 752, y: 672), 140.0)] {
        let descriptor = NSFont.systemFont(ofSize: size, weight: .black).fontDescriptor
            .withDesign(.rounded) ?? NSFont.systemFont(ofSize: size, weight: .black).fontDescriptor
        let font = NSFont(descriptor: descriptor, size: size) ?? NSFont.boldSystemFont(ofSize: size)
        (text as NSString).draw(at: point, withAttributes: [
            .font: font,
            .foregroundColor: NSColor.white,
        ])
    }
}

func render(pixels: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("could not create a context for \(pixels)px")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    draw(in: context.cgContext)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode the \(pixels)px PNG")
    }
    return data
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("one argument required: path to the .iconset\n".utf8))
    exit(2)
}
let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try render(pixels: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(pixels: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("icons written to \(iconset.path)")
