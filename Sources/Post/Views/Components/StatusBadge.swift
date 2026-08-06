import SwiftUI

public struct MethodBadge: View {
    public let method: HTTPMethod

    public init(method: HTTPMethod) {
        self.method = method
    }

    public var body: some View {
        Text(method.rawValue)
            .font(.caption2.bold())
            .monospaced()
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }

    private var color: Color {
        switch method {
        case .get: return .blue
        case .post: return .green
        case .put: return .orange
        case .delete: return .red
        case .patch: return .purple
        case .head, .options: return .secondary
        }
    }
}

public struct StatusCodeBadge: View {
    public let code: Int
    public let text: String

    public init(code: Int, text: String = "") {
        self.code = code
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text("\(code)")
                .font(.caption.bold())
                .monospaced()
            if !text.isEmpty {
                Text(text)
                    .font(.caption)
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }

    private var color: Color {
        switch code {
        case 200..<300: return .green
        case 300..<400: return .blue
        case 400..<500: return .orange
        case 500..<600: return .red
        default: return .secondary
        }
    }
}
