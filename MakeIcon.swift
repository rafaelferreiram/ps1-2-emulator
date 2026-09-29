import AppKit
import ImageIO
import QuartzCore

let original = URL(fileURLWithPath: CommandLine.arguments[1])
let target = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard let source = CGImageSourceCreateWithURL(original as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { fatalError("Logo inválido") }

/// macOS 27 Dock icons sit on a squircle inside the square canvas.
/// Measured from the system Calendar icon at 256 px: the plate is 210 px,
/// centered, with a continuous corner of about 43 px.
func dockIcon(from image: CGImage, pixels: Int) -> CGImage {
    let canvas = CGFloat(pixels)
    let plate = canvas * (210.0 / 256.0)
    let origin = (canvas - plate) / 2
    // Continuous corners draw a little tighter than this radius, so the
    // value is tuned until the silhouette matches a system Dock icon.
    let radius = plate * (49.0 / 210.0)
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                            bytesPerRow: pixels * 4, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

    let layer = CALayer()
    layer.bounds = CGRect(x: 0, y: 0, width: plate, height: plate)
    layer.contentsScale = 1
    layer.contentsGravity = .resize
    layer.contents = image
    layer.cornerRadius = radius
    layer.cornerCurve = .continuous
    layer.masksToBounds = true
    layer.isGeometryFlipped = false

    context.translateBy(x: origin, y: origin)
    layer.render(in: context)
    guard let masked = context.makeImage() else { fatalError("Falha ao arredondar o ícone") }
    return masked
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let suffix = scale == 2 ? "@2x" : ""
        let url = target.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, dockIcon(from: image, pixels: pixels), nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Falha ao gerar ícone") }
    }
}

func lengthData(_ value: Int) -> Data {
    var bigEndian = UInt32(value).bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}
let entries = [
    ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
    ("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png"),
    ("ic11", "icon_16x16@2x.png"), ("ic12", "icon_32x32@2x.png"),
    ("ic13", "icon_128x128@2x.png"), ("ic14", "icon_256x256@2x.png")
]
var elements = Data()
for (type, filename) in entries {
    let png = try Data(contentsOf: target.appendingPathComponent(filename))
    elements.append(Data(type.utf8))
    elements.append(lengthData(png.count + 8))
    elements.append(png)
}
var container = Data("icns".utf8)
container.append(lengthData(elements.count + 8))
container.append(elements)
try container.write(to: URL(fileURLWithPath: CommandLine.arguments[3]), options: .atomic)
