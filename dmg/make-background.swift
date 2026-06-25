//
//  make-background.swift — renders the DMG installer-window background.
//
//  A plain white field to match the app icon. The app and Applications icons
//  are positioned over it by the Finder layout in make-dmg.sh.
//
//  Usage: swift make-background.swift <output.png>
//

import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.png"

// Window content is 640×400 points; render at 2× for crisp Retina output.
let scale: CGFloat = 2
let W: CGFloat = 640, H: CGFloat = 400
let pw = Int(W * scale), ph = Int(H * scale)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pw, pixelsHigh: ph,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("Could not create bitmap") }

let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
let cg = ctx.cgContext

// White background.
cg.setFillColor(NSColor.white.cgColor)
cg.fill(CGRect(x: 0, y: 0, width: pw, height: ph))

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed") }
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) — \(pw)×\(ph)")
