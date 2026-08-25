// 生成 1024x1024 应用图标（CoreGraphics 纯代码绘制，无外部依赖）
// 用法: swift Scripts/make_icon.swift 输出路径.png
import AppKit

let arguments = CommandLine.arguments
let outPath = arguments.count > 1 ? arguments[1] : "icon_1024.png"
let S: CGFloat = 1024

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: Int(S), height: Int(S),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

// 以“左上角为原点、y 向下”的坐标辅助
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: S - y - h, width: w, height: h)
}
func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x, y: S - y)
}
func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGRect {
    rect(cx - r, cy - r, 2 * r, 2 * r)
}
func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: rect(x, y, w, h), cornerWidth: r, cornerHeight: r, transform: nil)
}

// 圆角方形底 + 靛蓝→紫罗兰渐变
ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: S, height: S), cornerWidth: 232, cornerHeight: 232, transform: nil))
ctx.clip()

let bgGradient = CGGradient(
    colorsSpace: space,
    colors: [color(85, 100, 240), color(139, 92, 246)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

let highlight = CGGradient(
    colorsSpace: space,
    colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.20),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawRadialGradient(highlight, startCenter: CGPoint(x: 330, y: 760), startRadius: 0, endCenter: CGPoint(x: 330, y: 760), endRadius: 760, options: [])

// 白色清单卡片
ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 44, color: color(20, 12, 60, 0.35))
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.97))
ctx.addPath(rounded(196, 210, 632, 560, 54))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// 第一行：渐变对勾圆圈
let checkBounds = ellipse(296, 352, 62)
ctx.saveGState()
ctx.addEllipse(in: checkBounds)
ctx.clip()
let checkGradient = CGGradient(
    colorsSpace: space,
    colors: [color(99, 102, 241), color(168, 85, 247)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(checkGradient, start: CGPoint(x: checkBounds.minX, y: checkBounds.maxY), end: CGPoint(x: checkBounds.maxX, y: checkBounds.minY), options: [])
ctx.restoreGState()

ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(20)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.beginPath()
ctx.move(to: point(296 - 24, 352 + 2))
ctx.addLine(to: point(296 - 7, 352 + 19))
ctx.addLine(to: point(296 + 27, 352 - 17))
ctx.strokePath()

// 第二行：空心圆圈
ctx.setStrokeColor(color(178, 182, 197))
ctx.setLineWidth(13)
ctx.strokeEllipse(in: ellipse(296, 512, 62))

// 文字占位横线
func bar(_ y: CGFloat, _ x1: CGFloat, _ x2: CGFloat, _ h: CGFloat, _ alpha: CGFloat) {
    ctx.setFillColor(color(120, 124, 142, alpha))
    ctx.addPath(rounded(x1, y - h / 2, x2 - x1, h, h / 2))
    ctx.fillPath()
}
bar(359, 392, 700, 26, 0.82)
bar(519, 392, 636, 26, 0.42)

// 右下角小闹钟徽章
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(30, 18, 80, 0.45))
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fillEllipse(in: ellipse(742, 692, 128))
ctx.setShadow(offset: .zero, blur: 0, color: nil)

ctx.setStrokeColor(color(203, 205, 226))
ctx.setLineWidth(10)
ctx.strokeEllipse(in: ellipse(742, 692, 102))

ctx.setStrokeColor(color(88, 84, 238))
ctx.setLineWidth(17)
ctx.setLineCap(.round)
ctx.beginPath()
ctx.move(to: point(742, 692))
ctx.addLine(to: point(742, 692 - 56))
ctx.strokePath()
ctx.beginPath()
ctx.move(to: point(742, 692))
ctx.addLine(to: point(742 + 38, 692 + 6))
ctx.strokePath()
ctx.setFillColor(color(88, 84, 238))
ctx.fillEllipse(in: ellipse(742, 692, 11))

// 导出 PNG
guard let image = ctx.makeImage() else { fatalError("无法生成图像") }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("无法编码 PNG") }
try! png.write(to: URL(fileURLWithPath: outPath))
print("icon -> \(outPath)")
