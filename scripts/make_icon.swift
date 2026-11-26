// 生成 Toolula Tidy 的图标: 变色龙面前, 乱飞的彩色方块被收拾成整齐的方阵.
// 用法: swift scripts/make_icon.swift Resources/icon_source.png Resources
//   icon_source.png 里只取变色龙的形状 (上半部分), 颜色、背景、方块和文字都在这里画.
//   生成 Resources/toolula_tidy_icon.png, 再用 iconutil 做成 AppIcon.icns (见 README)
import AppKit
let src = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))!
let out = CommandLine.arguments[2]
let W = src.pixelsWide, H = src.pixelsHigh
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func makeCtx() -> CGContext { CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)! }
let base = makeCtx(); base.draw(src.cgImage!, in: CGRect(x: 0, y: 0, width: W, height: H))
let B = base.data!.assumingMemoryBound(to: UInt8.self)
func at(_ b: UnsafeMutablePointer<UInt8>, _ x: Int, _ y: Int) -> UnsafeMutablePointer<UInt8> { b + y * W * 4 + x * 4 }
func cg(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }

/// 只有变色龙的图 (透明底). color: 0 顶…1 底 → 颜色
func chameleon(_ color: (Double) -> (Double, Double, Double)) -> CGImage {
    let ctx = makeCtx(); let D = ctx.data!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<690 { for x in 0..<W {
        if (x > 712 && y < 286) || x > 790 { continue }   // 不要原来的闪光
        let p = at(B, x, y); guard p[3] == 255 else { continue }
        let m = max(0, min(1, (Double(p[1]) - 70) / 130)); guard m > 0 else { continue }
        let c = color((Double(y) - 173) / 480)
        let d = at(D, x, y)
        d[0] = UInt8(c.0 * m); d[1] = UInt8(c.1 * m); d[2] = UInt8(c.2 * m); d[3] = UInt8(255 * m)
    } }
    return ctx.makeImage()!
}
let blueCham = chameleon { t in (110 - 40 * t, 225 - 75 * t, 240 + 15 * t) }
let squircle = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)

/// 新画布: 上面为 0 的坐标, 已经裁成圆角方块
func canvas(_ bg: (CGContext) -> Void) -> CGContext {
    let c = makeCtx()
    c.translateBy(x: 0, y: CGFloat(H)); c.scaleBy(x: 1, y: -1)
    c.addPath(squircle); c.clip()
    bg(c)
    return c
}
func vgrad(_ c: CGContext, _ a: CGColor, _ b: CGColor, from: CGPoint = CGPoint(x: 512, y: 100), to: CGPoint = CGPoint(x: 512, y: 924)) {
    c.drawLinearGradient(CGGradient(colorsSpace: cs, colors: [a, b] as CFArray, locations: nil)!, start: from, end: to, options: [])
}
func glow(_ c: CGContext, _ at: CGPoint, _ r: CGFloat, _ col: CGColor) {
    c.drawRadialGradient(CGGradient(colorsSpace: cs, colors: [col, col.copy(alpha: 0)!] as CFArray, locations: nil)!,
                         startCenter: at, startRadius: 0, endCenter: at, endRadius: r, options: [])
}
/// 画变色龙: 把原图里 (srcCenter) 这一点放到 dst, 放大 scale 倍
func drawCham(_ c: CGContext, _ img: CGImage, srcCenter: CGPoint = CGPoint(x: 512, y: 413), dst: CGPoint, scale: CGFloat) {
    c.saveGState()
    c.translateBy(x: dst.x, y: dst.y); c.scaleBy(x: scale, y: scale); c.translateBy(x: -srcCenter.x, y: -srcCenter.y)
    // CGImage 在翻转的坐标里要再翻一次
    c.translateBy(x: 0, y: CGFloat(H)); c.scaleBy(x: 1, y: -1)
    c.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
    c.restoreGState()
}
func text(_ c: CGContext, _ s: String, size: CGFloat, centerX: CGFloat, baseline: CGFloat, colors: [CGColor]) {
    let f0 = NSFont.systemFont(ofSize: size, weight: .bold)
    let font = NSFont(descriptor: f0.fontDescriptor.withDesign(.rounded)!, size: size)!
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font]))
    let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    c.saveGState()
    c.translateBy(x: centerX - b.width / 2 - b.minX, y: baseline); c.scaleBy(x: 1, y: -1)
    c.textPosition = .zero; c.setTextDrawingMode(.clip); CTLineDraw(line, c)
    c.drawLinearGradient(CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: nil)!, start: CGPoint(x: 0, y: font.capHeight), end: CGPoint(x: 0, y: font.descender), options: [])
    c.restoreGState()
}
func box(_ c: CGContext, _ center: CGPoint, _ s: CGFloat, _ angle: CGFloat, _ col: CGColor, stroke: Bool = false) {
    c.saveGState(); c.translateBy(x: center.x, y: center.y); c.rotate(by: angle)
    c.addPath(CGPath(roundedRect: CGRect(x: -s / 2, y: -s / 2, width: s, height: s), cornerWidth: s * 0.24, cornerHeight: s * 0.24, transform: nil))
    if stroke { c.setStrokeColor(col); c.setLineWidth(s * 0.13); c.strokePath() } else { c.setFillColor(col); c.fillPath() }
    c.restoreGState()
}
func save(_ c: CGContext, _ name: String) {
    try! NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out + "/" + name))
}
let pink = cg(255, 105, 140)
let navyTop = cg(23, 33, 52), navyBottom = cg(9, 14, 25)

// 从乱到整齐
let c = canvas { c in vgrad(c, navyTop, navyBottom); glow(c, CGPoint(x: 410, y: 450), 400, cg(60, 130, 200, 0.35)) }
// 变色龙 + 方块整组的左右位置 (让整组在图标里居中)
let dx: CGFloat = -44
drawCham(c, blueCham, dst: CGPoint(x: 445 + dx, y: 448), scale: 0.92)
// 乱: 五颜六色、东倒西歪 (都在圆角里面, 不贴边)
let messy: [(CGFloat, CGFloat, CGFloat, CGFloat, CGColor)] = [
    (768, 205, 44, 0.55, cg(255, 105, 140)), (838, 228, 32, -0.5, cg(255, 190, 80)),
    (792, 282, 34, 0.95, cg(160, 125, 255)), (852, 300, 22, 0.3, cg(255, 105, 140))]
for m in messy { box(c, CGPoint(x: m.0 + dx, y: m.1), m.2, m.3, m.4) }
// 整齐: 统一的青→蓝, 排成方阵
for j in 0..<3 { for i in 0..<2 {
    let t = CGFloat(i + j) / 3
    box(c, CGPoint(x: 776 + dx + CGFloat(i) * 60, y: 400 + CGFloat(j) * 60), 48, 0, cg(115 - 40 * t, 225 - 70 * t, 245 + 10 * t))
} }
text(c, "Tidy", size: 150, centerX: 512, baseline: 862, colors: [cg(120, 225, 245), cg(80, 150, 255)])
save(c, "toolula_tidy_icon.png")
