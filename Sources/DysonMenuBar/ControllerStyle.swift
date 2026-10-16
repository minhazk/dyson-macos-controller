import SwiftUI

/// The warm, monochrome surfaces used by the menu-bar controller.
enum ControllerStyle {
    static let background = Color(red: 0.032, green: 0.035, blue: 0.032)
    static let surface = Color(red: 0.105, green: 0.109, blue: 0.097)
    static let raisedSurface = Color(red: 0.16, green: 0.16, blue: 0.145)
    static let text = Color(red: 0.93, green: 0.93, blue: 0.90)
    static let secondary = Color(red: 0.66, green: 0.66, blue: 0.62)
    static let muted = Color(red: 0.40, green: 0.40, blue: 0.37)
    static let accent = Color(red: 0.72, green: 0.72, blue: 0.66)
    static let sliderFill = Color(red: 0.52, green: 0.52, blue: 0.47)
    static let outline = Color(red: 0.28, green: 0.28, blue: 0.25)

    static let tileGradient = LinearGradient(
        colors: [raisedSurface, surface],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
