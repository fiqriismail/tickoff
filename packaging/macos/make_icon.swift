// Draws the app icon: an indigo rounded square with a white check mark.
// Usage: swift make_icon.swift <output.png>
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let inset = 100.0
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let body = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.30)
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.shadowBlurRadius = 28
shadow.set()
NSColor(red: 0.31, green: 0.35, blue: 0.90, alpha: 1).setFill()
body.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(
    starting: NSColor(red: 0.49, green: 0.51, blue: 1.00, alpha: 1),
    ending: NSColor(red: 0.31, green: 0.35, blue: 0.90, alpha: 1)
)!.draw(in: body, angle: -90)

let check = NSBezierPath()
check.move(to: NSPoint(x: 330, y: 520))
check.line(to: NSPoint(x: 460, y: 390))
check.line(to: NSPoint(x: 710, y: 650))
check.lineWidth = 92
check.lineCapStyle = .round
check.lineJoinStyle = .round
NSColor.white.setStroke()
check.stroke()

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
