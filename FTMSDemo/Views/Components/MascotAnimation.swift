import SwiftUI
import UIKit

struct MascotAnimation: UIViewRepresentable {
    private let frameRate = 12.0

    func makeUIView(context _: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Running mascot"

        let frames = MascotFrameCache.frames
        imageView.image = frames.first
        imageView.animationImages = frames
        imageView.animationDuration = Double(frames.count) / frameRate
        imageView.animationRepeatCount = 0
        imageView.startAnimating()
        return imageView
    }

    func updateUIView(_: UIImageView, context _: Context) {
        // Core Animation owns the frame loop; SwiftUI does not rebuild it.
    }
}

private enum MascotFrameCache {
    static let frames: [UIImage] = {
        guard let source = UIImage(named: "MascotRun")?.cgImage else { return [] }

        let columns = 6
        let rows = 3
        return (0..<(columns * rows)).compactMap { index in
            let column = index % columns
            let row = index / columns
            let left = Int(CGFloat(column) * CGFloat(source.width) / CGFloat(columns))
            let right = Int(CGFloat(column + 1) * CGFloat(source.width) / CGFloat(columns))
            let top = Int(CGFloat(row) * CGFloat(source.height) / CGFloat(rows))
            let bottom = Int(CGFloat(row + 1) * CGFloat(source.height) / CGFloat(rows))
            let rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
            guard let frame = source.cropping(to: rect) else { return nil }
            return UIImage(cgImage: frame, scale: 1, orientation: .up)
        }
    }()
}
