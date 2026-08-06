#!/usr/bin/env swift

import AppKit

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let sourcePath = "\(scriptDir)/icon-source.png"

guard let sourceImage = NSImage(contentsOfFile: sourcePath) else {
    print("Failed to load \(sourcePath)")
    exit(1)
}

// 1. Inset artwork slightly (880x880) so edge background frames cleanly inside squircle
let cropSize: CGFloat = min(sourceImage.size.width, sourceImage.size.height) * 0.88
let cropRect = NSRect(
    x: (sourceImage.size.width - cropSize) / 2,
    y: (sourceImage.size.height - cropSize) / 2,
    width: cropSize, height: cropSize
)
let croppedImage = NSImage(size: cropRect.size)
croppedImage.lockFocus()
sourceImage.draw(in: NSRect(origin: .zero, size: cropRect.size), from: cropRect, operation: .copy, fraction: 1.0)
croppedImage.unlockFocus()

// 2. Render macOS App Icon format (1024x1024 canvas, 824x824 squircle, shadow)
func createMacIconBase(from image: NSImage) -> NSImage {
    let canvasSize = NSSize(width: 1024, height: 1024)
    let squircleSize = NSSize(width: 824, height: 824)
    let squircleRect = NSRect(
        x: (canvasSize.width - squircleSize.width) / 2,
        y: (canvasSize.height - squircleSize.height) / 2,
        width: squircleSize.width, height: squircleSize.height
    )
    
    let baseImage = NSImage(size: canvasSize)
    baseImage.lockFocus()
    
    NSGraphicsContext.current?.imageInterpolation = .high
    
    // Draw Shadow
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0.0, alpha: 0.45)
    shadow.shadowOffset = NSSize(width: 0, height: -25)
    shadow.shadowBlurRadius = 30
    
    // NSBezierPath continuous rounded rect (approx squircle)
    let path = NSBezierPath(roundedRect: squircleRect, xRadius: 185, yRadius: 185)
    
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    // Dark background base color (#121418)
    NSColor(red: 18/255.0, green: 20/255.0, blue: 24/255.0, alpha: 1.0).set()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    
    // Clip to squircle and draw image
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    image.draw(in: squircleRect, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    
    // Draw thin white specular gradient border line around squircle
    if let cgContext = NSGraphicsContext.current?.cgContext {
        cgContext.saveGState()
        let rimPath = CGPath(roundedRect: squircleRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
        cgContext.addPath(rimPath)
        cgContext.setLineWidth(2.5)
        cgContext.replacePathWithStrokedPath()
        cgContext.clip()
        
        let colors = [
            NSColor(white: 1.0, alpha: 0.65).cgColor,
            NSColor(white: 1.0, alpha: 0.25).cgColor,
            NSColor(white: 1.0, alpha: 0.08).cgColor
        ] as CFArray
        let locations: [CGFloat] = [0.0, 0.45, 1.0]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
            cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: squircleRect.midX, y: squircleRect.maxY),
                end: CGPoint(x: squircleRect.midX, y: squircleRect.minY),
                options: []
            )
        }
        cgContext.restoreGState()
    }

    baseImage.unlockFocus()
    return baseImage
}

let macIconBase = createMacIconBase(from: croppedImage)

func resizeImage(_ image: NSImage, to size: CGFloat) -> NSImage {
    let newImage = NSImage(size: NSSize(width: size, height: size))
    newImage.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy, fraction: 1.0)
    newImage.unlockFocus()
    return newImage
}

let sizes: [(CGFloat, String)] = [
    (16, "icon_16x16"),
    (32, "icon_16x16@2x"),
    (32, "icon_32x32"),
    (64, "icon_32x32@2x"),
    (128, "icon_128x128"),
    (256, "icon_128x128@2x"),
    (256, "icon_256x256"),
    (512, "icon_256x256@2x"),
    (512, "icon_512x512"),
    (1024, "icon_512x512@2x"),
]

let iconsetPath = "AppIcon.iconset"
let fm = FileManager.default
try? fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for (size, name) in sizes {
    let resized = resizeImage(macIconBase, to: size)
    guard let tiffData = resized.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(name)")
        continue
    }
    let path = "\(iconsetPath)/\(name).png"
    try! pngData.write(to: URL(fileURLWithPath: path))
    print("Generated \(path) (\(Int(size))x\(Int(size)))")
}

print("\nConverting to .icns...")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath]
try! process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Created AppIcon.icns")
} else {
    print("iconutil failed")
}

try? fm.removeItem(atPath: iconsetPath)
