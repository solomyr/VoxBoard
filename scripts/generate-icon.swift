import AppKit
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let dark = NSColor(srgbRed: 0.045, green: 0.065, blue: 0.15, alpha: 1)
let light = NSColor(srgbRed: 0.11, green: 0.19, blue: 0.32, alpha: 1)
NSGradient(starting: dark, ending: light)!.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: 45)
let heights: [CGFloat] = [150, 300, 470, 300, 150]
for (index, height) in heights.enumerated() {
 let x = CGFloat(224 + index * 116)
 NSColor(srgbRed: 0.32, green: 0.94, blue: 0.79, alpha: 1).setFill()
 NSBezierPath(roundedRect: NSRect(x: x, y: (1024 - height) / 2 + 10, width: 88, height: height), xRadius: 44, yRadius: 44).fill()
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
