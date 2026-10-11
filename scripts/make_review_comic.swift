#!/usr/bin/env swift
// Genera un cómic de prueba original (sin derechos de terceros) para la
// revisión de App Store: el mismo contenido en CBZ y en PDF.
//
// Uso, desde la raíz del repo:
//     swift scripts/make_review_comic.swift
// Salida: docs/review/Sample-Comic.cbz y docs/review/Sample-Comic.pdf
//
// Todo se dibuja con CoreGraphics: formas simples, colores y texto. No usa
// ninguna imagen, fuente ni personaje de terceros.

import AppKit
import CoreGraphics
import CoreText
import Foundation

// MARK: - Configuración

let pageSize = CGSize(width: 1600, height: 2400)
let margin: CGFloat = 70
let gutter: CGFloat = 40
let outputDir = URL(fileURLWithPath: "docs/review", isDirectory: true)
let title = "The Lighthouse Robot"

// MARK: - Utilidades de dibujo

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Dibuja texto centrado en un rectángulo. El contexto tiene el origen
/// abajo a la izquierda (sistema de CoreGraphics).
func drawText(_ text: String, in rect: CGRect, size: CGFloat, bold: Bool = false,
              color textColor: CGColor = color(0x111111), ctx: CGContext) {
    let font = NSFont.systemFont(ofSize: size, weight: bold ? .heavy : .medium)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributed = NSAttributedString(string: text, attributes: [
        .font: font,
        .foregroundColor: NSColor(cgColor: textColor) ?? .black,
        .paragraphStyle: paragraph,
    ])
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let fitted = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter, CFRange(), nil, CGSize(width: rect.width, height: .greatestFiniteMagnitude), nil
    )
    // Centrado vertical dentro del rectángulo.
    let textRect = CGRect(x: rect.minX, y: rect.midY - fitted.height / 2,
                          width: rect.width, height: fitted.height)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(), CGPath(rect: textRect, transform: nil), nil)
    CTFrameDraw(frame, ctx)
}

/// Bocadillo de diálogo con rabito apuntando a `tail`.
func speechBubble(_ text: String, in rect: CGRect, tail: CGPoint, ctx: CGContext) {
    ctx.saveGState()
    ctx.setFillColor(color(0xFFFFFF))
    ctx.setStrokeColor(color(0x111111))
    ctx.setLineWidth(6)
    let tailPath = CGMutablePath()
    tailPath.move(to: CGPoint(x: rect.midX - 30, y: rect.minY + 10))
    tailPath.addLine(to: tail)
    tailPath.addLine(to: CGPoint(x: rect.midX + 30, y: rect.minY + 10))
    ctx.addPath(tailPath)
    ctx.drawPath(using: .fillStroke)
    ctx.addEllipse(in: rect)
    ctx.drawPath(using: .fillStroke)
    ctx.restoreGState()
    drawText(text, in: rect.insetBy(dx: rect.width * 0.14, dy: rect.height * 0.12), size: 46, ctx: ctx)
}

/// Cartela rectangular de narración.
func caption(_ text: String, in rect: CGRect, ctx: CGContext) {
    ctx.setFillColor(color(0xFFE066))
    ctx.setStrokeColor(color(0x111111))
    ctx.setLineWidth(5)
    ctx.addRect(rect)
    ctx.drawPath(using: .fillStroke)
    drawText(text, in: rect.insetBy(dx: 20, dy: 10), size: 40, bold: true, ctx: ctx)
}

/// Fondo de viñeta: cielo degradado, mar y borde.
func panelBackground(_ rect: CGRect, sky: (UInt32, UInt32), sea: UInt32, ctx: CGContext) {
    ctx.saveGState()
    ctx.clip(to: rect)
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [color(sky.0), color(sky.1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    ctx.setFillColor(color(sea))
    ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.3))
    // Olas sencillas.
    ctx.setStrokeColor(color(0xFFFFFF, 0.5))
    ctx.setLineWidth(5)
    var x = rect.minX + 20
    while x < rect.maxX {
        let y = rect.minY + rect.height * 0.15 + CGFloat(Int(x) % 3) * 18
        ctx.move(to: CGPoint(x: x, y: y))
        ctx.addQuadCurve(to: CGPoint(x: x + 70, y: y), control: CGPoint(x: x + 35, y: y + 20))
        x += 130
    }
    ctx.strokePath()
    ctx.restoreGState()
}

func panelBorder(_ rect: CGRect, ctx: CGContext) {
    ctx.setStrokeColor(color(0x111111))
    ctx.setLineWidth(10)
    ctx.stroke(rect)
}

/// Faro con haz de luz opcional.
func lighthouse(base: CGPoint, height: CGFloat, beam: Bool, ctx: CGContext) {
    let width = height * 0.28
    if beam {
        ctx.setFillColor(color(0xFFF3B0, 0.55))
        let top = CGPoint(x: base.x, y: base.y + height * 0.92)
        ctx.move(to: top)
        ctx.addLine(to: CGPoint(x: top.x + height * 1.6, y: top.y + height * 0.35))
        ctx.addLine(to: CGPoint(x: top.x + height * 1.6, y: top.y - height * 0.25))
        ctx.closePath()
        ctx.fillPath()
    }
    // Torre con franjas.
    let stripes = 5
    for i in 0..<stripes {
        let y0 = base.y + CGFloat(i) * height * 0.8 / CGFloat(stripes)
        let inset = CGFloat(i) * width * 0.05
        ctx.setFillColor(i.isMultiple(of: 2) ? color(0xE63946) : color(0xFFFFFF))
        ctx.fill(CGRect(x: base.x - width / 2 + inset, y: y0,
                        width: width - inset * 2, height: height * 0.8 / CGFloat(stripes) + 1))
    }
    // Linterna y tejado.
    ctx.setFillColor(color(0xFFD60A))
    ctx.fill(CGRect(x: base.x - width * 0.3, y: base.y + height * 0.8, width: width * 0.6, height: height * 0.12))
    ctx.setFillColor(color(0x1D3557))
    ctx.move(to: CGPoint(x: base.x - width * 0.42, y: base.y + height * 0.92))
    ctx.addLine(to: CGPoint(x: base.x + width * 0.42, y: base.y + height * 0.92))
    ctx.addLine(to: CGPoint(x: base.x, y: base.y + height))
    ctx.closePath()
    ctx.fillPath()
}

/// El protagonista: un robot redondo. `mood` cambia los ojos.
enum Mood { case happy, worried, surprised }

func robot(center: CGPoint, size: CGFloat, mood: Mood, ctx: CGContext) {
    ctx.saveGState()
    ctx.setStrokeColor(color(0x111111))
    ctx.setLineWidth(size * 0.04)
    // Cuerpo.
    ctx.setFillColor(color(0x8ECAE6))
    let body = CGRect(x: center.x - size * 0.35, y: center.y - size * 0.5, width: size * 0.7, height: size * 0.55)
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: size * 0.1, cornerHeight: size * 0.1, transform: nil))
    ctx.drawPath(using: .fillStroke)
    // Cabeza.
    ctx.setFillColor(color(0xBDE0FE))
    let head = CGRect(x: center.x - size * 0.3, y: center.y + size * 0.02, width: size * 0.6, height: size * 0.42)
    ctx.addPath(CGPath(roundedRect: head, cornerWidth: size * 0.12, cornerHeight: size * 0.12, transform: nil))
    ctx.drawPath(using: .fillStroke)
    // Antena.
    ctx.move(to: CGPoint(x: center.x, y: head.maxY))
    ctx.addLine(to: CGPoint(x: center.x, y: head.maxY + size * 0.12))
    ctx.strokePath()
    ctx.setFillColor(color(0xFB8500))
    ctx.fillEllipse(in: CGRect(x: center.x - size * 0.05, y: head.maxY + size * 0.1, width: size * 0.1, height: size * 0.1))
    // Ojos.
    ctx.setFillColor(color(0x111111))
    let eyeY = head.midY + size * 0.03
    let eyeSize: CGFloat = mood == .surprised ? size * 0.12 : size * 0.08
    for dx in [-size * 0.12, size * 0.12] {
        ctx.fillEllipse(in: CGRect(x: center.x + dx - eyeSize / 2, y: eyeY - eyeSize / 2, width: eyeSize, height: eyeSize))
    }
    // Boca.
    let mouthY = head.minY + size * 0.1
    ctx.move(to: CGPoint(x: center.x - size * 0.1, y: mouthY))
    switch mood {
    case .happy:
        ctx.addQuadCurve(to: CGPoint(x: center.x + size * 0.1, y: mouthY), control: CGPoint(x: center.x, y: mouthY - size * 0.08))
    case .worried:
        ctx.addQuadCurve(to: CGPoint(x: center.x + size * 0.1, y: mouthY), control: CGPoint(x: center.x, y: mouthY + size * 0.06))
    case .surprised:
        ctx.addEllipse(in: CGRect(x: center.x - size * 0.04, y: mouthY - size * 0.04, width: size * 0.08, height: size * 0.08))
    }
    ctx.strokePath()
    // Panel del pecho.
    ctx.setFillColor(color(0xFFB703))
    ctx.fillEllipse(in: CGRect(x: center.x - size * 0.07, y: body.midY - size * 0.07, width: size * 0.14, height: size * 0.14))
    ctx.restoreGState()
}

/// Barco pequeño.
func boat(at point: CGPoint, size: CGFloat, ctx: CGContext) {
    ctx.setFillColor(color(0x6D4C41))
    ctx.move(to: CGPoint(x: point.x - size / 2, y: point.y))
    ctx.addLine(to: CGPoint(x: point.x + size / 2, y: point.y))
    ctx.addLine(to: CGPoint(x: point.x + size * 0.35, y: point.y - size * 0.18))
    ctx.addLine(to: CGPoint(x: point.x - size * 0.35, y: point.y - size * 0.18))
    ctx.closePath()
    ctx.fillPath()
    ctx.setFillColor(color(0xFFFFFF))
    ctx.move(to: CGPoint(x: point.x, y: point.y + size * 0.05))
    ctx.addLine(to: CGPoint(x: point.x, y: point.y + size * 0.6))
    ctx.addLine(to: CGPoint(x: point.x + size * 0.35, y: point.y + size * 0.05))
    ctx.closePath()
    ctx.fillPath()
}

func stars(in rect: CGRect, ctx: CGContext) {
    ctx.setFillColor(color(0xFFFFFF, 0.85))
    var seed: UInt32 = 7
    for _ in 0..<40 {
        seed = seed &* 1_103_515_245 &+ 12345
        let x = rect.minX + CGFloat(seed % 1000) / 1000 * rect.width
        seed = seed &* 1_103_515_245 &+ 12345
        let y = rect.minY + rect.height * 0.4 + CGFloat(seed % 1000) / 1000 * rect.height * 0.6
        ctx.fillEllipse(in: CGRect(x: x, y: y, width: 8, height: 8))
    }
}

// MARK: - Maquetación de viñetas

/// Divide el área útil de la página en filas de viñetas. `rows` indica
/// cuántas viñetas hay en cada fila.
func layout(rows: [Int]) -> [CGRect] {
    let content = CGRect(x: margin, y: margin, width: pageSize.width - margin * 2,
                         height: pageSize.height - margin * 2 - 60)
    let rowHeight = (content.height - gutter * CGFloat(rows.count - 1)) / CGFloat(rows.count)
    var rects: [CGRect] = []
    for (rowIndex, columns) in rows.enumerated() {
        // Primera fila arriba: en CoreGraphics la Y crece hacia arriba.
        let y = content.maxY - CGFloat(rowIndex + 1) * rowHeight - CGFloat(rowIndex) * gutter
        let width = (content.width - gutter * CGFloat(columns - 1)) / CGFloat(columns)
        for column in 0..<columns {
            rects.append(CGRect(x: content.minX + CGFloat(column) * (width + gutter), y: y, width: width, height: rowHeight))
        }
    }
    return rects
}

func pageNumber(_ number: Int, ctx: CGContext) {
    drawText("\(number)", in: CGRect(x: 0, y: 10, width: pageSize.width, height: 60), size: 34, ctx: ctx)
}

let day = (UInt32(0x90E0EF), UInt32(0xCAF0F8))
let dusk = (UInt32(0xF4A261), UInt32(0xFFDDD2))
let night = (UInt32(0x03045E), UInt32(0x023E8A))
let storm = (UInt32(0x495057), UInt32(0x6C757D))

// MARK: - Páginas

typealias Page = (CGContext) -> Void

let pages: [Page] = [
    // 1. Portada.
    { ctx in
        let full = CGRect(origin: .zero, size: pageSize)
        panelBackground(full, sky: night, sea: 0x0077B6, ctx: ctx)
        stars(in: full, ctx: ctx)
        lighthouse(base: CGPoint(x: 520, y: 700), height: 1100, beam: true, ctx: ctx)
        robot(center: CGPoint(x: 1100, y: 980), size: 520, mood: .happy, ctx: ctx)
        drawText(title.uppercased(), in: CGRect(x: 80, y: 1950, width: 1440, height: 300), size: 130, bold: true,
                 color: color(0xFFD60A), ctx: ctx)
        drawText("A free sample comic for testing", in: CGRect(x: 80, y: 120, width: 1440, height: 100), size: 52,
                 color: color(0xFFFFFF), ctx: ctx)
    },
    // 2. Presentación.
    { ctx in
        let p = layout(rows: [1, 2, 1])
        panelBackground(p[0], sky: day, sea: 0x00B4D8, ctx: ctx)
        lighthouse(base: CGPoint(x: p[0].midX, y: p[0].minY + 120), height: 420, beam: false, ctx: ctx)
        caption("On a tiny island lived a tiny robot.", in: CGRect(x: p[0].minX + 30, y: p[0].maxY - 130, width: 900, height: 100), ctx: ctx)
        panelBackground(p[1], sky: day, sea: 0x00B4D8, ctx: ctx)
        robot(center: CGPoint(x: p[1].midX, y: p[1].midY - 40), size: 360, mood: .happy, ctx: ctx)
        speechBubble("Good morning, sea!", in: CGRect(x: p[1].minX + 40, y: p[1].maxY - 230, width: 560, height: 200),
                     tail: CGPoint(x: p[1].midX, y: p[1].midY + 140), ctx: ctx)
        panelBackground(p[2], sky: day, sea: 0x00B4D8, ctx: ctx)
        boat(at: CGPoint(x: p[2].midX, y: p[2].minY + 200), size: 260, ctx: ctx)
        caption("Its job: keep the light on for the boats.", in: CGRect(x: p[2].minX + 20, y: p[2].maxY - 140, width: p[2].width - 40, height: 110), ctx: ctx)
        panelBackground(p[3], sky: dusk, sea: 0x0096C7, ctx: ctx)
        lighthouse(base: CGPoint(x: p[3].minX + 300, y: p[3].minY + 110), height: 400, beam: true, ctx: ctx)
        robot(center: CGPoint(x: p[3].maxX - 330, y: p[3].midY - 30), size: 300, mood: .happy, ctx: ctx)
        caption("Every evening, without fail.", in: CGRect(x: p[3].maxX - 720, y: p[3].maxY - 130, width: 680, height: 100), ctx: ctx)
        p.forEach { panelBorder($0, ctx: ctx) }
        pageNumber(2, ctx: ctx)
    },
    // 3. La tormenta.
    { ctx in
        let p = layout(rows: [2, 1, 2])
        panelBackground(p[0], sky: storm, sea: 0x343A40, ctx: ctx)
        robot(center: CGPoint(x: p[0].midX, y: p[0].midY - 40), size: 320, mood: .worried, ctx: ctx)
        speechBubble("Those clouds look bad...", in: CGRect(x: p[0].minX + 20, y: p[0].maxY - 230, width: p[0].width - 40, height: 210),
                     tail: CGPoint(x: p[0].midX, y: p[0].midY + 130), ctx: ctx)
        panelBackground(p[1], sky: storm, sea: 0x343A40, ctx: ctx)
        // Rayo.
        ctx.setFillColor(color(0xFFD60A))
        let b = p[1]
        ctx.move(to: CGPoint(x: b.midX + 40, y: b.maxY - 40))
        ctx.addLine(to: CGPoint(x: b.midX - 80, y: b.midY))
        ctx.addLine(to: CGPoint(x: b.midX, y: b.midY))
        ctx.addLine(to: CGPoint(x: b.midX - 60, y: b.minY + 60))
        ctx.addLine(to: CGPoint(x: b.midX + 110, y: b.midY + 60))
        ctx.addLine(to: CGPoint(x: b.midX + 20, y: b.midY + 60))
        ctx.closePath()
        ctx.fillPath()
        drawText("KRAK!", in: CGRect(x: b.minX, y: b.midY - 60, width: b.width, height: 140), size: 120, bold: true,
                 color: color(0xFFFFFF), ctx: ctx)
        panelBackground(p[2], sky: night, sea: 0x023E8A, ctx: ctx)
        lighthouse(base: CGPoint(x: p[2].midX, y: p[2].minY + 100), height: 440, beam: false, ctx: ctx)
        caption("The light went out.", in: CGRect(x: p[2].minX + 60, y: p[2].maxY - 130, width: 620, height: 100), ctx: ctx)
        panelBackground(p[3], sky: night, sea: 0x023E8A, ctx: ctx)
        robot(center: CGPoint(x: p[3].midX, y: p[3].midY - 60), size: 320, mood: .surprised, ctx: ctx)
        speechBubble("Oh no!", in: CGRect(x: p[3].minX + 60, y: p[3].maxY - 220, width: 420, height: 190),
                     tail: CGPoint(x: p[3].midX, y: p[3].midY + 110), ctx: ctx)
        panelBackground(p[4], sky: night, sea: 0x023E8A, ctx: ctx)
        boat(at: CGPoint(x: p[4].midX, y: p[4].minY + 180), size: 280, ctx: ctx)
        caption("And a boat was coming home.", in: CGRect(x: p[4].minX + 20, y: p[4].maxY - 130, width: p[4].width - 40, height: 100), ctx: ctx)
        p.forEach { panelBorder($0, ctx: ctx) }
        pageNumber(3, ctx: ctx)
    },
    // 4. La idea.
    { ctx in
        let p = layout(rows: [1, 1, 2])
        panelBackground(p[0], sky: night, sea: 0x023E8A, ctx: ctx)
        robot(center: CGPoint(x: p[0].minX + 380, y: p[0].midY - 40), size: 380, mood: .worried, ctx: ctx)
        speechBubble("I need light. Any light!", in: CGRect(x: p[0].midX, y: p[0].midY - 40, width: 640, height: 240),
                     tail: CGPoint(x: p[0].minX + 520, y: p[0].midY + 80), ctx: ctx)
        panelBackground(p[1], sky: night, sea: 0x023E8A, ctx: ctx)
        robot(center: CGPoint(x: p[1].midX, y: p[1].midY - 60), size: 380, mood: .surprised, ctx: ctx)
        // Brillo del pecho.
        ctx.setFillColor(color(0xFFD60A, 0.45))
        ctx.fillEllipse(in: CGRect(x: p[1].midX - 160, y: p[1].midY - 260, width: 320, height: 320))
        caption("Wait... its chest could glow!", in: CGRect(x: p[1].minX + 30, y: p[1].maxY - 130, width: 820, height: 100), ctx: ctx)
        panelBackground(p[2], sky: night, sea: 0x023E8A, ctx: ctx)
        lighthouse(base: CGPoint(x: p[2].midX, y: p[2].minY + 100), height: 440, beam: false, ctx: ctx)
        caption("Up the stairs!", in: CGRect(x: p[2].minX + 40, y: p[2].maxY - 130, width: 460, height: 100), ctx: ctx)
        panelBackground(p[3], sky: night, sea: 0x023E8A, ctx: ctx)
        robot(center: CGPoint(x: p[3].midX, y: p[3].midY - 40), size: 320, mood: .happy, ctx: ctx)
        speechBubble("Full power!", in: CGRect(x: p[3].minX + 40, y: p[3].maxY - 220, width: 480, height: 190),
                     tail: CGPoint(x: p[3].midX, y: p[3].midY + 120), ctx: ctx)
        p.forEach { panelBorder($0, ctx: ctx) }
        pageNumber(4, ctx: ctx)
    },
    // 5. Final.
    { ctx in
        let p = layout(rows: [1, 2])
        panelBackground(p[0], sky: night, sea: 0x0077B6, ctx: ctx)
        stars(in: p[0], ctx: ctx)
        lighthouse(base: CGPoint(x: p[0].minX + 320, y: p[0].minY + 160), height: 760, beam: true, ctx: ctx)
        boat(at: CGPoint(x: p[0].maxX - 280, y: p[0].minY + 230), size: 280, ctx: ctx)
        caption("The light shone again.", in: CGRect(x: p[0].maxX - 760, y: p[0].maxY - 140, width: 720, height: 100), ctx: ctx)
        panelBackground(p[1], sky: dusk, sea: 0x0096C7, ctx: ctx)
        boat(at: CGPoint(x: p[1].midX, y: p[1].minY + 200), size: 260, ctx: ctx)
        speechBubble("Thank you, little robot!", in: CGRect(x: p[1].minX + 20, y: p[1].maxY - 260, width: p[1].width - 40, height: 230),
                     tail: CGPoint(x: p[1].midX, y: p[1].minY + 330), ctx: ctx)
        panelBackground(p[2], sky: day, sea: 0x00B4D8, ctx: ctx)
        robot(center: CGPoint(x: p[2].midX, y: p[2].midY - 40), size: 340, mood: .happy, ctx: ctx)
        caption("THE END", in: CGRect(x: p[2].midX - 200, y: p[2].maxY - 140, width: 400, height: 100), ctx: ctx)
        p.forEach { panelBorder($0, ctx: ctx) }
        pageNumber(5, ctx: ctx)
    },
    // 6. Contraportada con créditos y licencia.
    { ctx in
        ctx.setFillColor(color(0x1D3557))
        ctx.fill(CGRect(origin: .zero, size: pageSize))
        robot(center: CGPoint(x: pageSize.width / 2, y: 1500), size: 500, mood: .happy, ctx: ctx)
        drawText(title, in: CGRect(x: 100, y: 900, width: 1400, height: 160), size: 80, bold: true,
                 color: color(0xFFD60A), ctx: ctx)
        drawText("Original sample comic created by Raúl Gallego for testing comic reader apps.\n\nNo third-party characters, artwork or trademarks.\nReleased under CC0 (public domain): free to copy, share and use.",
                 in: CGRect(x: 160, y: 380, width: 1280, height: 480), size: 44, color: color(0xFFFFFF), ctx: ctx)
    },
]

// MARK: - Renderizado

func renderBitmap(_ page: Page) -> Data {
    let ctx = CGContext(data: nil, width: Int(pageSize.width), height: Int(pageSize.height), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fill(CGRect(origin: .zero, size: pageSize))
    // CoreText necesita el contexto gráfico de AppKit para resolver colores.
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    page(ctx)
    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])!
}

let fm = FileManager.default
try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

// CBZ: un ZIP con las páginas numeradas en orden.
let staging = fm.temporaryDirectory.appendingPathComponent("review-comic-\(UUID().uuidString)", isDirectory: true)
try fm.createDirectory(at: staging, withIntermediateDirectories: true)
for (index, page) in pages.enumerated() {
    let name = String(format: "page%02d.jpg", index + 1)
    try renderBitmap(page).write(to: staging.appendingPathComponent(name))
}
let cbzURL = outputDir.appendingPathComponent("Sample-Comic.cbz")
try? fm.removeItem(at: cbzURL)
let zip = Process()
zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
zip.currentDirectoryURL = staging
// -X: sin atributos extendidos de macOS; -0: las JPEG ya van comprimidas.
zip.arguments = ["-X", "-0", "-q", cbzURL.standardizedFileURL.path] +
    (1...pages.count).map { String(format: "page%02d.jpg", $0) }
try zip.run()
zip.waitUntilExit()
try? fm.removeItem(at: staging)

// PDF: las mismas páginas, dibujadas en vectorial.
let pdfURL = outputDir.appendingPathComponent("Sample-Comic.pdf")
var mediaBox = CGRect(origin: .zero, size: pageSize)
let pdf = CGContext(pdfURL as CFURL, mediaBox: &mediaBox,
                    [kCGPDFContextTitle as String: title, kCGPDFContextAuthor as String: "Raúl Gallego"] as CFDictionary)!
for page in pages {
    pdf.beginPDFPage(nil)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: false)
    page(pdf)
    pdf.endPDFPage()
}
pdf.closePDF()

print("Generado: \(cbzURL.path)")
print("Generado: \(pdfURL.path)")
