import SwiftUI

/// A text field that turns what is typed into removable tokens.
/// A comma finishes a token; Return finishes it and submits.
struct TokenField: View {
    let placeholder: String
    @Binding var tokens: [String]
    @Binding var draft: String
    var onSubmit: () -> Void = {}

    @FocusState private var isFocused: Bool

    var body: some View {
        TokenFlowLayout(spacing: 5, lineSpacing: 5) {
            ForEach(tokens, id: \.self) { token in
                TokenChip(text: token) {
                    tokens.removeAll { $0 == token }
                }
            }
            TextField(tokens.isEmpty ? placeholder : "", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .frame(height: 22)
                .focused($isFocused)
                .onSubmit {
                    AppModel.commit(&draft, into: &tokens)
                    onSubmit()
                }
                .onChange(of: draft) { _, text in
                    if text.contains(where: { ",;\n".contains($0) }) {
                        AppModel.commit(&draft, into: &tokens)
                    }
                }
                .onKeyPress(.delete) {
                    // Backspace in an empty field takes back the last token.
                    guard draft.isEmpty, !tokens.isEmpty else { return .ignored }
                    tokens.removeLast()
                    return .handled
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minHeight: 32)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isFocused ? Color.accentColor.opacity(0.9) : Color(nsColor: .separatorColor),
                              lineWidth: isFocused ? 2 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .onChange(of: isFocused) { _, focused in
            if !focused { AppModel.commit(&draft, into: &tokens) }
        }
        .animation(.easeOut(duration: 0.15), value: tokens)
    }
}

private struct TokenChip: View {
    let text: String
    let remove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isHovered ? Color.primary : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Убрать")
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: 22)
        .background(Color.accentColor.opacity(isHovered ? 0.28 : 0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { isHovered = $0 }
    }
}

/// Lays tokens out left to right, wrapping as needed. The last subview is the text field
/// and takes whatever is left of its line.
private struct TokenFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat
    var minimumFieldWidth: CGFloat = 130

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let frames = arrange(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        func wrap() {
            x = 0
            y += lineHeight + lineSpacing
            lineHeight = 0
        }
        for (index, subview) in subviews.enumerated() {
            var size = subview.sizeThatFits(.unspecified)
            if index == subviews.count - 1 {
                if width - x < minimumFieldWidth, x > 0 { wrap() }
                size.width = max(width - x, min(minimumFieldWidth, width))
            } else {
                size.width = min(size.width, width)
                if x + size.width > width, x > 0 { wrap() }
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return frames
    }
}
