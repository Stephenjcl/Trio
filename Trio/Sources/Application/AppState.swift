import Foundation
import Observation
import SwiftUI
import UIKit

@Observable class AppState {
    func trioBackgroundColor(for colorScheme: ColorScheme) -> LinearGradient {
        colorScheme == .dark
            ? LinearGradient(
                gradient: Gradient(colors: [Color.bgDarkBlue, Color.bgDarkerDarkBlue]),
                startPoint: .top,
                endPoint: .bottom
            )
            : LinearGradient(
                gradient: Gradient(colors: [
                    // Subtle trans-flag wash: light blue → pink, low opacity to keep text legible
                    Color(red: 0.333, green: 0.804, blue: 0.988).opacity(0.12),
                    Color(red: 0.969, green: 0.659, blue: 0.722).opacity(0.12)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
    }
}
