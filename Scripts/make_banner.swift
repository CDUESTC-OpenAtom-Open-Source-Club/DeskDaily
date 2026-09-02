// 生成 README 首屏品牌横幅（2200x1100，CoreGraphics 纯代码绘制）
// 用法: swift Scripts/make_banner.swift 输出路径.png
import AppKit

let arguments = CommandLine.arguments
let outPath = arguments.count > 1 ? arguments[1] : "banner.png"
let W: CGFloat = 2200
let H: CGFloat = 1100

let image = NSImage(size: NSSize(width: W, height: H))
image.lockFocusFlipped(false)  // AppKit 坐标：左下角原点，y 向上

// 渐变底：靛蓝 → 紫罗兰
NSGradient(colors: [
    NSColor(red: 85/255, green: 100/255, blue: 240/255, alpha: 1),
    NSColor(red: 139/255, green: 92/255, blue: 246/255, alpha: 1)
])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -55)

// 左上柔光（径向渐变，无硬边）
let glow = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.20),
    NSColor.white.withAlphaComponent(0)
])!
glow.draw(fromCenter: NSPoint(x: 200, y: 1050), radius: 0,
          toCenter: NSPoint(x: 1500, y: -200), radius: 1700)

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

// ---- 左侧：白色清单卡片（放大版应用图标母题）----
let card = NSRect(x: 170, y: 210, width: 560, height: 680)
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(red: 20/255, green: 12/255, blue: 60/255, alpha: 0.35)
shadow.shadowBlurRadius = 44
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()
NSColor.white.withAlphaComponent(0.97).setFill()
rounded(card, 56).fill()
NSGraphicsContext.current?.restoreGraphicsState()

func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> NSRect {
    NSRect(x: cx - r, y: cy - r, width: 2*r, height: 2*r)
}

// 第一行：渐变对勾圆 + 深色横条
let row1y = card.maxY - 150
let g1 = NSGradient(colors: [
    NSColor(red: 99/255, green: 102/255, blue: 241/255, alpha: 1),
    NSColor(red: 168/255, green: 85/255, blue: 247/255, alpha: 1)
])!
g1.draw(in: circle(card.minX + 105, row1y, 56), angle: -45)
NSColor.white.setStroke()
let check = NSBezierPath()
check.lineWidth = 17
check.lineCapStyle = .round
check.lineJoinStyle = .round
check.move(to: NSPoint(x: card.minX + 82, y: row1y + 2))
check.line(to: NSPoint(x: card.minX + 98, y: row1y - 16))
check.line(to: NSPoint(x: card.minX + 130, y: row1y + 20))
check.stroke()
NSColor(red: 120/255, green: 124/255, blue: 142/255, alpha: 0.85).setFill()
rounded(NSRect(x: card.minX + 190, y: row1y - 14, width: 280, height: 28), 14).fill()

// 第二行：空心圆 + 浅横条
let row2y = row1y - 150
NSColor(red: 178/255, green: 182/255, blue: 197/255, alpha: 1).setStroke()
let hollow = NSBezierPath(ovalIn: circle(card.minX + 105, row2y, 50))
hollow.lineWidth = 11
hollow.stroke()
NSColor(red: 120/255, green: 124/255, blue: 142/255, alpha: 0.40).setFill()
rounded(NSRect(x: card.minX + 190, y: row2y - 13, width: 210, height: 26), 13).fill()

// 第三行：闹钟徽章 + 横条（表意“提醒”）
let row3y = row2y - 170
let badge = circle(card.minX + 105, row3y, 52)
NSColor(red: 99/255, green: 102/255, blue: 241/255, alpha: 1).setFill()
NSBezierPath(ovalIn: badge).fill()
NSColor.white.setStroke()
let hands = NSBezierPath()
hands.lineWidth = 9
hands.lineCapStyle = .round
hands.move(to: NSPoint(x: badge.midX, y: badge.midY))
hands.line(to: NSPoint(x: badge.midX, y: badge.midY + 28))
hands.move(to: NSPoint(x: badge.midX, y: badge.midY))
hands.line(to: NSPoint(x: badge.midX + 20, y: badge.midY - 6))
hands.stroke()
NSColor(red: 120/255, green: 124/255, blue: 142/255, alpha: 0.40).setFill()
rounded(NSRect(x: card.minX + 190, y: row3y - 13, width: 240, height: 26), 13).fill()

// ---- 右侧：标题 + 副标题 ----
let title = NSAttributedString(string: "DeskDaily", attributes: [
    .font: NSFont.systemFont(ofSize: 168, weight: .bold),
    .foregroundColor: NSColor.white
])
title.draw(at: NSPoint(x: 880, y: 620))

let subtitle = NSAttributedString(string: "桌面日程清单 · AI 规划 · 本地优先", attributes: [
    .font: NSFont.systemFont(ofSize: 62, weight: .medium),
    .foregroundColor: NSColor.white.withAlphaComponent(0.88)
])
subtitle.draw(at: NSPoint(x: 888, y: 520))

// 底部三个特性胶囊
let pills = ["多计划表", "时段提醒", "统计热力图"]
var pillX: CGFloat = 892
for text in pills {
    let attr = NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: 38, weight: .semibold),
        .foregroundColor: NSColor.white
    ])
    let size = attr.size()
    let pillRect = NSRect(x: pillX, y: 400, width: size.width + 56, height: 78)
    NSColor.white.withAlphaComponent(0.16).setFill()
    rounded(pillRect, 39).fill()
    attr.draw(at: NSPoint(x: pillX + 28, y: 400 + (78 - size.height) / 2))
    pillX += pillRect.width + 28
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("无法编码 PNG")
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("banner -> \(outPath)")
