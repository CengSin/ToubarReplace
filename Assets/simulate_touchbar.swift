import Foundation
import CoreGraphics

func createSimulatedTouchBarImage() -> UIImage? {
    let width: CGFloat = 800
    let height: CGFloat = 50
    let imageRect = CGRect(x: 0, y: 0, width: width, height: height)
    
    UIGraphicsBeginImageContextWithOptions(imageRect.size, false, 2.0)  // Retina
    
    let context = UIGraphicsGetCurrentContext()!
    
    // 背景
    UIColor.black.setFill()
    context.fill(imageRect)
    
    // 左侧功能键区域
    UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1).setFill()
    context.fill(CGRect(x: 0, y: 0, width: 120, height: height))
    
    // 中间区域
    UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1).setFill()
    context.fill(CGRect(x: 120, y: 0, width: 560, height: height))
    
    // 右侧媒体控制
    UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1).setFill()
    context.fill(CGRect(x: 680, y: 0, width: 120, height: height))
    
    // 绘制按钮模拟
    UIColor.white.setFill()
    let buttonSize: CGFloat = 38
    let buttonY: CGFloat = 6
    
    // 功能键按钮
    for i in 0..<4 {
        context.fillEllipse(in: CGRect(x: 10 + CGFloat(i) * 30, y: buttonY, width: buttonSize, height: buttonSize))
    }
    
    // 媒体控制按钮
    let mediaX = 700.0
    context.fillEllipse(in: CGRect(x: mediaX, y: buttonY, width: buttonSize, height: buttonSize))
    context.fillEllipse(in: CGRect(x: mediaX + 45, y: buttonY, width: buttonSize, height: buttonSize))
    
    // 文字标签（简化）
    let attrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: UIColor.white
    ]
    
    "Esc".draw(at: CGPoint(x: 15, y: 28), withAttributes: attrs)
    "Media".draw(at: CGPoint(x: mediaX + 8, y: 28), withAttributes: attrs)
    
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return image
}

createSimulatedTouchBarImage()?.pngData()?.write(to: URL(fileURLWithPath: "/Users/cengsin/agent-projects/toubar-replace/ToubarReplace/Assets/touchbar_simulated.png"), atomically: true)
print("模拟 Touch Bar 图片已生成: /Users/cengsin/agent-projects/toubar-replace/ToubarReplace/Assets/touchbar_simulated.png")
