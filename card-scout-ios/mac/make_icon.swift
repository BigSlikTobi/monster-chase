import AppKit

// Small vector mark: a scarlet card stack and a white football seam. No third-party art.
let pixels = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
let c = graphics.cgContext
c.setFillColor(CGColor(red: 0.035, green: 0.045, blue: 0.065, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
func card(_ rect: CGRect, color: CGColor, angle: CGFloat) {
    c.saveGState(); c.translateBy(x: 512, y: 512); c.rotate(by: angle); c.translateBy(x: -512, y: -512)
    c.setFillColor(color); c.addPath(CGPath(roundedRect: rect, cornerWidth: 58, cornerHeight: 58, transform: nil)); c.fillPath(); c.restoreGState()
}
card(CGRect(x: 272, y: 199, width: 494, height: 630), color: CGColor(red: 0.31, green: 0.13, blue: 0.16, alpha: 1), angle: -0.24)
card(CGRect(x: 265, y: 194, width: 494, height: 630), color: CGColor(red: 0.66, green: 0.19, blue: 0.23, alpha: 1), angle: -0.12)
card(CGRect(x: 259, y: 190, width: 494, height: 630), color: CGColor(red: 0.97, green: 0.26, blue: 0.27, alpha: 1), angle: 0)
c.setStrokeColor(CGColor(gray: 1, alpha: 0.96)); c.setLineWidth(26); c.setLineCap(.round)
c.move(to: CGPoint(x: 365, y: 514)); c.addCurve(to: CGPoint(x: 653, y: 514), control1: CGPoint(x: 430, y: 665), control2: CGPoint(x: 584, y: 665))
c.addCurve(to: CGPoint(x: 365, y: 514), control1: CGPoint(x: 584, y: 363), control2: CGPoint(x: 430, y: 363)); c.strokePath()
c.setLineWidth(18); c.move(to: CGPoint(x: 440, y: 514)); c.addLine(to: CGPoint(x: 578, y: 514)); c.strokePath()
for x in [473, 509, 545] { c.move(to: CGPoint(x: x, y: 485)); c.addLine(to: CGPoint(x: x, y: 543)); c.strokePath() }
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
