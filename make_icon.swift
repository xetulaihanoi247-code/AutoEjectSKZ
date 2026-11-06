// Vẽ icon AutoEject (nút bấm 3D) → AppIcon.iconset (iconutil đóng gói thành .icns)
import Cocoa

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

func gradient(_ colors: [CGColor], _ locs: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locs)!
}

func circle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
}

func vertical(_ ctx: CGContext, _ g: CGGradient, _ rect: CGRect) {
    ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY), options: [])
}

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // ---- Vỏ squircle ----
    let inset = s * 0.1
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let w = rect.width
    let radius = w * 0.2237
    let body = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    let c = CGPoint(x: rect.midX, y: rect.midY)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.014), blur: s * 0.035, color: rgb(0, 0, 0, 0.4))
    ctx.addPath(body); ctx.setFillColor(rgb(0, 0, 0)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    // Nền vỏ: xám xanh đậm, sáng nhẹ ở trên
    vertical(ctx, gradient([rgb(0.27, 0.30, 0.42), rgb(0.12, 0.13, 0.22), rgb(0.07, 0.08, 0.15)], [0, 0.5, 1]), rect)
    // Ánh sáng mép trên của vỏ
    ctx.addPath(body); ctx.setLineWidth(w * 0.012)
    ctx.setStrokeColor(rgb(1, 1, 1, 0.28)); ctx.strokePath()
    ctx.restoreGState()

    // ---- Hốc lõm tròn chứa nút ----
    let wellR = w * 0.385
    let wellC = CGPoint(x: c.x, y: c.y)
    // mép sáng dưới hốc (ánh sáng chiếu từ trên xuống)
    ctx.saveGState()
    ctx.addPath(circle(CGPoint(x: wellC.x, y: wellC.y - w * 0.012), wellR))
    ctx.setFillColor(rgb(1, 1, 1, 0.16)); ctx.fillPath()
    ctx.restoreGState()
    // lòng hốc: tối, đậm ở trên
    ctx.saveGState()
    ctx.addPath(circle(wellC, wellR)); ctx.clip()
    vertical(ctx, gradient([rgb(0.01, 0.02, 0.05), rgb(0.05, 0.07, 0.14)]),
             CGRect(x: wellC.x - wellR, y: wellC.y - wellR, width: 2 * wellR, height: 2 * wellR))
    ctx.restoreGState()

    // ---- Nút bấm: thân (độ dày) ----
    let btnR = w * 0.325
    let depth = w * 0.055
    let baseC = CGPoint(x: c.x, y: c.y - w * 0.012)         // đáy nút
    let topC = CGPoint(x: c.x, y: c.y - w * 0.012 + depth)  // mặt nút nổi lên

    // bóng nút đổ xuống hốc
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.018), blur: s * 0.03, color: rgb(0, 0, 0, 0.6))
    ctx.addPath(circle(baseC, btnR)); ctx.setFillColor(rgb(0.05, 0.14, 0.45)); ctx.fillPath()
    ctx.restoreGState()
    // thân nút (từ đáy lên mặt) — sẫm hơn mặt
    ctx.saveGState()
    let side = CGMutablePath()
    side.addPath(circle(baseC, btnR)); side.addPath(circle(topC, btnR))
    side.addRect(CGRect(x: c.x - btnR, y: baseC.y, width: 2 * btnR, height: depth))
    ctx.addPath(side); ctx.clip()
    vertical(ctx, gradient([rgb(0.20, 0.45, 0.98), rgb(0.05, 0.16, 0.55)]),
             CGRect(x: c.x - btnR, y: baseC.y - btnR, width: 2 * btnR, height: 2 * btnR + depth))
    ctx.restoreGState()

    // ---- Mặt nút ----
    ctx.saveGState()
    ctx.addPath(circle(topC, btnR)); ctx.clip()
    let faceRect = CGRect(x: topC.x - btnR, y: topC.y - btnR, width: 2 * btnR, height: 2 * btnR)
    vertical(ctx, gradient([rgb(0.55, 0.88, 1.0), rgb(0.22, 0.58, 1.0), rgb(0.36, 0.30, 0.95)], [0, 0.5, 1]), faceRect)
    // quầng sáng mềm phía dưới (phản xạ)
    ctx.drawRadialGradient(gradient([rgb(0.35, 0.95, 0.90, 0.55), rgb(0.35, 0.95, 0.90, 0)]),
                           startCenter: CGPoint(x: topC.x, y: topC.y - btnR * 0.95), startRadius: 0,
                           endCenter: CGPoint(x: topC.x, y: topC.y - btnR * 0.95), endRadius: btnR * 0.85, options: [])
    ctx.restoreGState()

    // viền sáng bên trong mặt nút (sáng trên, mờ dưới)
    ctx.saveGState()
    ctx.addPath(circle(topC, btnR - w * 0.004)); ctx.clip()
    let rimW = w * 0.016
    ctx.addPath(circle(topC, btnR - w * 0.004)); ctx.setLineWidth(rimW * 2)
    ctx.replacePathWithStrokedPath(); ctx.clip()
    vertical(ctx, gradient([rgb(1, 1, 1, 0.95), rgb(1, 1, 1, 0.05)], [0, 0.65]), faceRect)
    ctx.restoreGState()

    // vệt bóng kính nửa trên
    ctx.saveGState()
    let glossRect = CGRect(x: topC.x - btnR * 0.80, y: topC.y + btnR * 0.05,
                           width: btnR * 1.60, height: btnR * 0.90)
    ctx.addPath(CGPath(ellipseIn: glossRect, transform: nil))
    ctx.clip()
    ctx.addPath(circle(topC, btnR - w * 0.012)); ctx.clip()
    vertical(ctx, gradient([rgb(1, 1, 1, 0.55), rgb(1, 1, 1, 0.04)]), glossRect)
    ctx.restoreGState()

    // ---- Ký hiệu eject khắc nổi ----
    let tw = w * 0.30, th = w * 0.165
    let gy = topC.y - w * 0.005
    let triBottom = gy - w * 0.005
    func glyph(dx: CGFloat, dy: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let tri = CGMutablePath()
        tri.move(to: CGPoint(x: c.x - tw / 2 + dx, y: triBottom + dy))
        tri.addLine(to: CGPoint(x: c.x + tw / 2 + dx, y: triBottom + dy))
        tri.addLine(to: CGPoint(x: c.x + dx, y: triBottom + th + dy))
        tri.closeSubpath()
        p.addPath(tri)
        let bw = tw * 1.04, bh = w * 0.055
        p.addPath(CGPath(roundedRect: CGRect(x: c.x - bw / 2 + dx, y: triBottom - w * 0.028 - bh + dy, width: bw, height: bh),
                         cornerWidth: bh * 0.3, cornerHeight: bh * 0.3, transform: nil))
        return p
    }
    func fillGlyph(_ path: CGPath, _ color: CGColor, round: CGFloat) {
        ctx.setFillColor(color); ctx.setStrokeColor(color)
        ctx.setLineJoin(.round); ctx.setLineWidth(round)
        ctx.addPath(path); ctx.drawPath(using: .fillStroke)
    }
    let r = w * 0.02
    // bóng đổ của ký hiệu xuống mặt nút
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.012, color: rgb(0.02, 0.08, 0.35, 0.65))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    fillGlyph(glyph(dx: 0, dy: 0), rgb(1, 1, 1), round: r)
    ctx.endTransparencyLayer()
    ctx.restoreGState()
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (base, name) in [(16, "16x16"), (32, "32x32"), (128, "128x128"), (256, "256x256"), (512, "512x512")] {
    try! render(size: base).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
    try! render(size: base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(name)@2x.png"))
}
