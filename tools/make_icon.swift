#!/usr/bin/env swift
//
// REmu App Icon Generator
// Produces a 1024x1024 PNG suitable for iOS AppIcon.appiconset.
//
// Run:  swift tools/make_icon.swift
// Out:  Resources/Assets.xcassets/AppIcon.appiconset/icon.png
//

import AppKit
import CoreGraphics
import CoreText

let size: CGFloat = 1024
let outURL = URL(fileURLWithPath:
    "Resources/Assets.xcassets/AppIcon.appiconset/icon.png")

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Could not create bitmap context\n", stderr)
    exit(1)
}

// Flip coordinate system so (0,0) is top-left for text convenience
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// ---------- Palette ----------
let deepPurple = CGColor(red: 0.09, green: 0.05, blue: 0.22, alpha: 1)
let midPurple  = CGColor(red: 0.19, green: 0.09, blue: 0.42, alpha: 1)
let navy       = CGColor(red: 0.05, green: 0.07, blue: 0.18, alpha: 1)
let orange     = CGColor(red: 1.00, green: 0.56, blue: 0.13, alpha: 1)
let amber      = CGColor(red: 1.00, green: 0.78, blue: 0.25, alpha: 1)
let cyan       = CGColor(red: 0.25, green: 0.90, blue: 1.00, alpha: 1)
let magenta    = CGColor(red: 1.00, green: 0.30, blue: 0.65, alpha: 1)
let white      = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)

// ---------- 1. Background gradient ----------
let bgGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [deepPurple, midPurple, navy] as CFArray,
    locations: [0.0, 0.55, 1.0]
)!
ctx.saveGState()
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 0, y: 0),
    end:   CGPoint(x: size, y: size),
    options: []
)
ctx.restoreGState()

// ---------- 2. Soft radial glow behind CRT ----------
let glowGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 1.00, green: 0.55, blue: 0.20, alpha: 0.55),
        CGColor(red: 1.00, green: 0.55, blue: 0.20, alpha: 0.00)
    ] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.saveGState()
ctx.drawRadialGradient(
    glowGradient,
    startCenter: CGPoint(x: size/2, y: size*0.55),
    startRadius: 0,
    endCenter:   CGPoint(x: size/2, y: size*0.55),
    endRadius:   size*0.55,
    options: []
)
ctx.restoreGState()

// ---------- 3. CRT screen body (rounded rectangle) ----------
let screenInset: CGFloat = 150
let screenRect = CGRect(
    x: screenInset,
    y: screenInset + 40,
    width: size - 2*screenInset,
    height: size - 2*screenInset - 160
)
let screenCornerRadius: CGFloat = 120

// Outer bezel (dark with slight gradient)
let bezelPath = CGPath(
    roundedRect: screenRect.insetBy(dx: -40, dy: -40),
    cornerWidth: screenCornerRadius + 30,
    cornerHeight: screenCornerRadius + 30,
    transform: nil
)
ctx.saveGState()
ctx.addPath(bezelPath)
ctx.clip()
let bezelGrad = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.14, green: 0.10, blue: 0.22, alpha: 1),
        CGColor(red: 0.04, green: 0.03, blue: 0.10, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    bezelGrad,
    start: CGPoint(x: screenRect.minX, y: screenRect.minY),
    end:   CGPoint(x: screenRect.maxX, y: screenRect.maxY),
    options: []
)
ctx.restoreGState()

// Inner screen glow rim
ctx.saveGState()
ctx.addPath(CGPath(
    roundedRect: screenRect.insetBy(dx: -8, dy: -8),
    cornerWidth: screenCornerRadius + 6,
    cornerHeight: screenCornerRadius + 6,
    transform: nil
))
ctx.setStrokeColor(orange)
ctx.setLineWidth(6)
ctx.strokePath()
ctx.restoreGState()

// Screen glass (dark with gradient)
ctx.saveGState()
let screenPath = CGPath(
    roundedRect: screenRect,
    cornerWidth: screenCornerRadius,
    cornerHeight: screenCornerRadius,
    transform: nil
)
ctx.addPath(screenPath)
ctx.clip()
let screenGrad = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.06, green: 0.02, blue: 0.14, alpha: 1),
        CGColor(red: 0.18, green: 0.04, blue: 0.28, alpha: 1),
        CGColor(red: 0.04, green: 0.01, blue: 0.10, alpha: 1)
    ] as CFArray,
    locations: [0, 0.5, 1]
)!
ctx.drawLinearGradient(
    screenGrad,
    start: CGPoint(x: screenRect.minX, y: screenRect.minY),
    end:   CGPoint(x: screenRect.maxX, y: screenRect.maxY),
    options: []
)

// ---------- 4. Scanlines inside screen ----------
ctx.setBlendMode(.plusLighter)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.04))
ctx.setLineWidth(2)
var y = screenRect.minY
while y < screenRect.maxY {
    ctx.move(to: CGPoint(x: screenRect.minX, y: y))
    ctx.addLine(to: CGPoint(x: screenRect.maxX, y: y))
    y += 8
}
ctx.strokePath()
ctx.setBlendMode(.normal)

// ---------- 5. "RE" big retro letters with chromatic offsets ----------
let letters = "RE"
let fontSize: CGFloat = 380

// Pick a bold rounded / display font available on macOS
let candidateFonts = ["Avenir Next Heavy", "Helvetica Neue Bold",
                      "Futura-CondensedExtraBold", "HelveticaNeue-CondensedBlack",
                      "Arial Black"]
var ctFont: CTFont = CTFontCreateWithName("Helvetica-Bold" as CFString,
                                          fontSize, nil)
for name in candidateFonts {
    if let nsFont = NSFont(name: name, size: fontSize) {
        ctFont = nsFont as CTFont
        break
    }
}

func drawText(_ s: String, color: CGColor, offset: CGPoint) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: ctFont,
        .foregroundColor: color
    ]
    let attr = NSAttributedString(string: s, attributes: attrs)
    let line = CTLineCreateWithAttributedString(attr)

    // Typographic metrics for width & capHeight-based vertical centering.
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var leading: CGFloat = 0
    let typoWidth = CGFloat(
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
    )
    let capHeight = CTFontGetCapHeight(ctFont)

    // In our outer y-down (flipped) context:
    //   baseline.y = midY + capHeight/2   →  visual center of caps lands on midY
    let baseX = screenRect.midX - typoWidth/2 + offset.x
    let baseY = screenRect.midY + capHeight/2 + offset.y

    ctx.saveGState()
    ctx.translateBy(x: baseX, y: baseY)
    ctx.scaleBy(x: 1, y: -1) // flip locally so CTLineDraw renders right-side up
    ctx.textMatrix = .identity
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

// Chromatic aberration: cyan left, magenta right, main white+orange center
ctx.saveGState()
ctx.addPath(screenPath)
ctx.clip()
ctx.setBlendMode(.screen)
drawText(letters, color: cyan,    offset: CGPoint(x: -14, y:  0))
drawText(letters, color: magenta, offset: CGPoint(x:  14, y:  0))
ctx.setBlendMode(.normal)

// Main letters: orange outline + white fill feel
drawText(letters, color: orange, offset: CGPoint(x: 0, y: 8))
drawText(letters, color: white,  offset: CGPoint(x: 0, y: 0))

// Subtle highlight on top half of letters
ctx.restoreGState()

// ---------- 6. Screen vignette ----------
ctx.saveGState()
ctx.addPath(screenPath)
ctx.clip()
let vignette = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0, green: 0, blue: 0, alpha: 0.0),
        CGColor(red: 0, green: 0, blue: 0, alpha: 0.55)
    ] as CFArray,
    locations: [0.55, 1.0]
)!
ctx.drawRadialGradient(
    vignette,
    startCenter: CGPoint(x: screenRect.midX, y: screenRect.midY),
    startRadius: 0,
    endCenter:   CGPoint(x: screenRect.midX, y: screenRect.midY),
    endRadius:   max(screenRect.width, screenRect.height) * 0.75,
    options: []
)
ctx.restoreGState()
// End of screen clip
ctx.restoreGState()

// ---------- 7. Little gamepad silhouette under the screen ----------
let padY: CGFloat = screenRect.maxY + 72
let padCenterX = size / 2
let padWidth: CGFloat = 360
let padHeight: CGFloat = 96

// Body (rounded capsule shape)
let padRect = CGRect(
    x: padCenterX - padWidth/2,
    y: padY - padHeight/2,
    width: padWidth,
    height: padHeight
)
ctx.saveGState()
let padPath = CGPath(
    roundedRect: padRect,
    cornerWidth: padHeight/2,
    cornerHeight: padHeight/2,
    transform: nil
)
ctx.addPath(padPath)
ctx.clip()
let padGrad = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.22, green: 0.14, blue: 0.38, alpha: 1),
        CGColor(red: 0.10, green: 0.05, blue: 0.20, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    padGrad,
    start: CGPoint(x: padRect.minX, y: padRect.minY),
    end:   CGPoint(x: padRect.minX, y: padRect.maxY),
    options: []
)
ctx.restoreGState()

// Gamepad rim stroke
ctx.saveGState()
ctx.addPath(padPath)
ctx.setStrokeColor(CGColor(red: 1, green: 0.56, blue: 0.13, alpha: 0.85))
ctx.setLineWidth(4)
ctx.strokePath()
ctx.restoreGState()

// D-Pad (left)
let dpadSize: CGFloat = 44
let dpadCenter = CGPoint(x: padRect.minX + 70, y: padRect.midY)
let dpadH = CGRect(
    x: dpadCenter.x - dpadSize/2,
    y: dpadCenter.y - dpadSize/6,
    width: dpadSize,
    height: dpadSize/3
)
let dpadV = CGRect(
    x: dpadCenter.x - dpadSize/6,
    y: dpadCenter.y - dpadSize/2,
    width: dpadSize/3,
    height: dpadSize
)
ctx.setFillColor(white)
ctx.fill(dpadH)
ctx.fill(dpadV)

// Action buttons (right) — 4 little circles in diamond
let abCenter = CGPoint(x: padRect.maxX - 70, y: padRect.midY)
let abRadius: CGFloat = 12
let abOffset: CGFloat = 22
func dot(_ p: CGPoint, _ c: CGColor) {
    ctx.setFillColor(c)
    ctx.fillEllipse(in: CGRect(
        x: p.x - abRadius,
        y: p.y - abRadius,
        width: abRadius*2,
        height: abRadius*2))
}
dot(CGPoint(x: abCenter.x,            y: abCenter.y - abOffset), amber)
dot(CGPoint(x: abCenter.x + abOffset, y: abCenter.y),            orange)
dot(CGPoint(x: abCenter.x,            y: abCenter.y + abOffset), cyan)
dot(CGPoint(x: abCenter.x - abOffset, y: abCenter.y),            magenta)

// ---------- 8. Final outer rounded mask (iOS handles corners, but soften) ----------
// iOS applies its own icon mask; we leave square but smooth the very corners.

// ---------- 9. Export ----------
guard let cgImage = ctx.makeImage() else {
    fputs("Failed to create CGImage\n", stderr)
    exit(1)
}
let rep = NSBitmapImageRep(cgImage: cgImage)
rep.size = NSSize(width: size, height: size)
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}
try? FileManager.default.createDirectory(
    at: outURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
do {
    try pngData.write(to: outURL)
    print("OK → \(outURL.path)  (\(pngData.count) bytes)")
} catch {
    fputs("Write error: \(error)\n", stderr)
    exit(1)
}
