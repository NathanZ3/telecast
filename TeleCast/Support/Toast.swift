import SwiftUI

/// A short message at the top of the screen, with an optional action ("Autoriser", "Ouvrir"…).
struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.id == rhs.id
    }
}

struct ToastView: View {
    let toast: Toast
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let title = toast.actionTitle, let action = toast.action {
                Button(title) {
                    action()
                    dismiss()
                }
                .font(.subheadline.bold())
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.horizontal, 12)
    }
}
