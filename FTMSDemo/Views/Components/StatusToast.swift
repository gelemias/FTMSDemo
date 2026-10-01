import SwiftUI
import UIKit
import Combine

@MainActor
final class StatusToastWindowManager: ObservableObject {
    private var window: UIWindow?
    private var dismissalWorkItem: DispatchWorkItem?
    private var isShowing = false
    private var toastID = UUID()

    func show(message: String, showsProgress: Bool) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        let toastWindow: UIWindow
        let shouldAnimateIn = !isShowing
        if let existingWindow = window, existingWindow.windowScene === scene {
            toastWindow = existingWindow
        } else {
            toastWindow = UIWindow(windowScene: scene)
            toastWindow.windowLevel = .alert
            toastWindow.backgroundColor = .clear
            toastWindow.isOpaque = false
            window = toastWindow
        }

        let controller = UIHostingController(rootView: GlobalStatusToastView(message: message, showsProgress: showsProgress))
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        toastWindow.rootViewController = controller
        toastWindow.isUserInteractionEnabled = false
        toastWindow.isHidden = false

        toastID = UUID()
        isShowing = true
        toastWindow.layer.removeAllAnimations()
        if shouldAnimateIn {
            toastWindow.alpha = 0
            toastWindow.transform = CGAffineTransform(translationX: 0, y: -28)
            UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 0.84,
                           initialSpringVelocity: 0.25,
                           options: [.beginFromCurrentState, .allowUserInteraction]) {
                toastWindow.alpha = 1
                toastWindow.transform = .identity
            }
        } else {
            toastWindow.alpha = 1
            toastWindow.transform = .identity
        }

        dismissalWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.hide() }
        dismissalWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: workItem)
    }

    private func hide() {
        guard isShowing, let window else { return }
        isShowing = false
        let hidingToastID = toastID
        UIView.animate(withDuration: 0.24, delay: 0, options: [.beginFromCurrentState, .curveEaseIn]) {
            window.alpha = 0
            window.transform = CGAffineTransform(translationX: 0, y: -28)
        } completion: { [weak self, weak window] _ in
            guard let self, self.toastID == hidingToastID else { return }
            window?.isHidden = true
            window?.alpha = 1
            window?.transform = .identity
        }
    }
}

private struct GlobalStatusToastView: View {
    let message: String
    let showsProgress: Bool

    var body: some View {
        VStack {
            HStack(spacing: 8) {
                if showsProgress {
                    ProgressView().controlSize(.small).tint(WorkoutTheme.controlAccent)
                        .frame(width: 22, height: 22)
                        .background(WorkoutTheme.controlAccent.opacity(0.12)).clipShape(Circle())
                } else {
                    Image(systemName: message == "No treadmills found." ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(WorkoutTheme.controlAccent)
                        .frame(width: 22, height: 22)
                        .background(WorkoutTheme.controlAccent.opacity(0.12)).clipShape(Circle())
                }
                Text(message).font(.caption.weight(.semibold)).lineLimit(2)
                    .truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: 300)
            .background(WorkoutTheme.panel).clipShape(Capsule()).panelNoise(cornerRadius: 20)
            .overlay(Capsule().stroke(WorkoutTheme.paper.opacity(0.12)))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 5).padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.clear)
    }
}
