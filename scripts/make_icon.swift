import AppKit
let src = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))!
let W = src.pixelsWide, H = src.pixelsHigh
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(src.cgImage!, in: CGRect(x: 0, y: 0, width: W, height: H))
// 1. 抹掉底部文字: 直接读画好的像素, 每一行用文字左右两侧的背景色横向插值
let buf = ctx.data!.assumingMemoryBound(to: UInt8.self)
let bpr = ctx.bytesPerRow
func px(_ x: Int, _ y: Int) -> UnsafeMutablePointer<UInt8> { buf + y * bpr + x * 4 }   // 内存里第 0 行就是图片最上面一行
let L = 190, R = 835, top = 728, bottom = 862
for y in top..<bottom {
    let a = px(L, y), b = px(R, y)
    for x in (L + 1)..<R {
        let t = Double(x - L) / Double(R - L)
        let p = px(x, y)
        for c in 0..<4 { p[c] = UInt8((Double(a[c]) * (1 - t) + Double(b[c]) * t).rounded()) }
    }
}
// 2. 写 "Tidy": 绿→青渐变, 和变色龙同一套颜色
let font = NSFont.systemFont(ofSize: 150, weight: .heavy)
let str = NSAttributedString(string: "Tidy", attributes: [.font: font, .kern: 1])
let line = CTLineCreateWithAttributedString(str)
let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
let ox = (CGFloat(W) - bounds.width) / 2 - bounds.minX
let oy = CGFloat(H) - 852 - bounds.minY            // 文字底边在 y=852
ctx.saveGState()
ctx.textPosition = CGPoint(x: ox, y: oy)
ctx.setTextDrawingMode(.clip)
CTLineDraw(line, ctx)
let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
    CGColor(srgbRed: 0.66, green: 0.95, blue: 0.40, alpha: 1),
    CGColor(srgbRed: 0.40, green: 0.93, blue: 0.62, alpha: 1),
    CGColor(srgbRed: 0.20, green: 0.88, blue: 0.93, alpha: 1)] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: ox, y: 0), end: CGPoint(x: ox + bounds.width, y: 0), options: [])
ctx.restoreGState()
let out = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
