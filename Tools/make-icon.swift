import AppKit

// Иконка рисуется кодом: в репозитории не лежит бинарник, и картинка
// гарантированно соответствует исходнику. Запуск: swift make-icon.swift <папка.iconset>

let canvas: CGFloat = 1024

func draw(in ctx: CGContext) {
    // Корпус: 824×824 по центру холста 1024 — стандартная сетка иконок macOS.
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

    // Месяц: круг минус смещённый круг.
    let outer = CGPath(ellipseIn: CGRect(x: 185, y: 205, width: 450, height: 450), transform: nil)
    let inner = CGPath(ellipseIn: CGRect(x: 310, y: 227, width: 405, height: 405), transform: nil)
    ctx.addPath(outer.subtracting(inner))
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillPath()

    // Zzz по диагонали вверх-вправо.
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
        fatalError("не удалось создать контекст для \(pixels)px")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    draw(in: context.cgContext)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("не удалось закодировать PNG \(pixels)px")
    }
    return data
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("нужен один аргумент: путь к .iconset\n".utf8))
    exit(2)
}
let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try render(pixels: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(pixels: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("иконки записаны в \(iconset.path)")
