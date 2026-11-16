import SwiftUI

extension PolishStyle {
    /// Each style has its own hue so the choices are easy to tell apart.
    var hue: Hue {
        switch self {
        case .tidy: Hues.named("Sage")
        case .professional: Hues.named("Ocean")
        case .friendly: Hues.named("Blush")
        case .concise: Hues.named("Amber")
        case .prompt: Hues.named("Dusk")
        }
    }
}
