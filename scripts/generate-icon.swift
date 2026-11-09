// Draws the VoxBoard app icon (1024×1024, opaque): five rounded waveform bars on a deep blue gradient.
// Usage: swift scripts/generate-icon.swift Sayboard/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let colors = [CGColor(srgbRed: 0.045, green: 0.065, blue: 0.15, alpha: 1),
              CGColor(srgbRed: 0.11, green: 0.19, blue: 0.32, alpha: 1)] as CFArray
let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size, y: size), options: [])
context.setFillColor(CGColor(srgbRed: 0.32, green: 0.94, blue: 0.79, alpha: 1))
let heights: [CGFloat] = [150, 300, 470, 300, 150]
for (index, height) in heights.enumerated() {
  let rect = CGRect(x: CGFloat(224 + index * 116), y: (1024 - height) / 2, width: 88, height: height)
  context.addPath(CGPath(roundedRect: rect, cornerWidth: 44, cornerHeight: 44, transform: nil))
  context.fillPath()
}
let image = context.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
precondition(CGImageDestinationFinalize(destination))
