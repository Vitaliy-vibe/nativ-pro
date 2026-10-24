// Иконка приложения Nativ Pro из tools/app/Logo/icon.svg (логотип владельца, 20.10): macOS сама читает SVG,
// поэтому градиенты и свечение отрисовываются точно. Запуск на Mac из tools/run_app.sh:
//   xcrun swift tools/app/render_icon.swift tools/app/Logo/icon.svg <папка>/AppIcon.appiconset
// Квадрат-«сквиркл» логотипа (16…496 из 512) вписывается в сетку значков macOS (100…924 из 1024), иначе macOS 26
// считает значок нестандартным и сажает его в серую подложку.
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let svg = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write("нужно: render_icon.swift <icon.svg> <AppIcon.appiconset>\n".data(using: .utf8)!)
    exit(1)
}
let out = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let scale: CGFloat = (824.0 / 1024.0) / (480.0 / 512.0)   // сквиркл логотипа → сквиркл сетки Apple
var images: [[String: String]] = []
for pt in [16, 32, 128, 256, 512] {
    for k in [1, 2] {
        let px = pt * k
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        let side = CGFloat(px) * scale
        let origin = (CGFloat(px) - side) / 2
        svg.draw(in: NSRect(x: origin, y: origin, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(pt)x\(pt)\(k == 2 ? "@2x" : "").png"
        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try png.write(to: out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(k)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted]).write(to: out.appendingPathComponent("Contents.json"))
print("иконка: \(images.count) размеров → \(out.path)")
