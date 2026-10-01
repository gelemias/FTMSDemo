import SwiftUI
import UIKit

private struct RGBColor {
    let red: Double
    let green: Double
    let blue: Double
}

enum WorkoutTheme {
    static let ink = adaptive(
        light: RGBColor(red: 0.851, green: 0.839, blue: 0.816),
        dark: RGBColor(red: 0.200, green: 0.200, blue: 0.200)
    )
    static let panel = adaptive(
        light: RGBColor(red: 0.925, green: 0.918, blue: 0.890),
        dark: RGBColor(red: 0.149, green: 0.149, blue: 0.149)
    )
    static let panelRaised = adaptive(
        light: RGBColor(red: 0.616, green: 0.651, blue: 0.596),
        dark: RGBColor(red: 0.340, green: 0.360, blue: 0.330)
    )
    static let paper = adaptive(
        light: RGBColor(red: 0.149, green: 0.149, blue: 0.149),
        dark: RGBColor(red: 0.851, green: 0.839, blue: 0.816)
    )
    static let muted = adaptive(
        light: RGBColor(red: 0.380, green: 0.400, blue: 0.365),
        dark: RGBColor(red: 0.616, green: 0.651, blue: 0.596)
    )
    static let orange = Color(red: 1.0, green: 0.8, blue: 0.0)
    static let controlAccent = adaptive(
        light: RGBColor(red: 0.200, green: 0.200, blue: 0.200),
        dark: RGBColor(red: 1.0, green: 0.8, blue: 0.0)
    )
    static let primaryButtonForeground = adaptive(
        light: RGBColor(red: 0.149, green: 0.149, blue: 0.149),
        dark: RGBColor(red: 0.200, green: 0.200, blue: 0.200)
    )

    private static func adaptive(
        light: RGBColor,
        dark: RGBColor
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let values = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: values.red, green: values.green, blue: values.blue, alpha: 1)
        })
    }
}

struct RubberFloorTexture: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let markColor = colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.06)
            let highlightColor = colorScheme == .dark ? Color.black.opacity(0.12) : Color.white.opacity(0.26)

            for row in stride(from: 0.0, through: size.height + 16, by: 14) {
                for column in stride(from: 0.0, through: size.width + 16, by: 14) {
                    let offset = Int(row / 14).isMultiple(of: 2) ? 7.0 : 0.0
                    let xPosition = column + offset
                    let yPosition = row
                    let dot = CGRect(x: xPosition, y: yPosition, width: 2.2, height: 2.2)
                    context.fill(Path(ellipseIn: dot), with: .color(markColor))

                    if Int((xPosition + yPosition) / 14).isMultiple(of: 5) {
                        var seam = Path()
                        seam.move(to: CGPoint(x: xPosition + 4, y: yPosition + 7))
                        seam.addLine(to: CGPoint(x: xPosition + 10, y: yPosition + 10))
                        context.stroke(seam, with: .color(highlightColor), lineWidth: 0.7)
                    }
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

struct NoiseTexture: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let lightGrain = colorScheme == .dark ? Color.white : Color.black
            let darkGrain = colorScheme == .dark ? Color.black : Color.white

            for row in stride(from: 0.0, through: size.height + 8, by: 8) {
                for column in stride(from: 0.0, through: size.width + 8, by: 8) {
                    let cellX = Int(column / 8)
                    let cellY = Int(row / 8)
                    var hash = UInt32(truncatingIfNeeded: cellX &* 374_761_393 &+ cellY &* 668_265_263)
                    hash ^= hash >> 13
                    hash &*= 1_274_126_177
                    hash ^= hash >> 16

                    let density = Double(hash % 1000) / 1000
                    guard density > 0.30 else { continue }

                    let jitterX = Double((hash >> 8) % 7)
                    let jitterY = Double((hash >> 16) % 7)
                    let dotSize = density > 0.84 ? 1.45 : 1.0
                    let dotColor = density > 0.68 ? lightGrain : darkGrain
                    let opacity = density > 0.84 ? 0.070 : 0.035
                    let dot = CGRect(x: column + jitterX, y: row + jitterY, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: dot), with: .color(dotColor.opacity(opacity)))
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

extension View {
    func panelNoise(cornerRadius: CGFloat, enabled: Bool = true) -> some View {
        overlay {
            if enabled {
                NoiseTexture()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
    }
}

struct TrainingPlanRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

struct DataRow: View {
    let label: String
    let value: Double?
    let unit: String

    init(label: String, value: Double?, unit: String) {
        self.label = label
        self.value = value
        self.unit = unit
    }

    init(label: String, value: Int?, unit: String) {
        self.label = label
        if let integerValue = value {
            self.value = Double(integerValue)
        } else {
            self.value = nil
        }
        self.unit = unit
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)
            Spacer()
            if let value {
                Text(String(format: "%.1f %@", value, unit))
                    .font(.headline)
                    .bold()
            } else {
                Text("--")
            }
        }
    }
}
