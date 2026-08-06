import SwiftUI
import AppKit

public struct DraggableDivider: View {
    @Binding public var width: CGFloat
    public var minWidth: CGFloat
    public var maxWidth: CGFloat

    public init(width: Binding<CGFloat>, minWidth: CGFloat = 180, maxWidth: CGFloat = 500) {
        self._width = width
        self.minWidth = minWidth
        self.maxWidth = maxWidth
    }

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
        }
        .frame(width: 7)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let newWidth = width + value.translation.width
                    width = max(minWidth, min(maxWidth, newWidth))
                }
        )
    }
}

public struct DraggableHeightDivider: View {
    @Binding public var height: CGFloat
    public var minHeight: CGFloat
    public var maxHeight: CGFloat

    public init(height: Binding<CGFloat>, minHeight: CGFloat = 150, maxHeight: CGFloat = 600) {
        self._height = height
        self.minHeight = minHeight
        self.maxHeight = maxHeight
    }

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
        .frame(height: 7)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let newHeight = height + value.translation.height
                    height = max(minHeight, min(maxHeight, newHeight))
                }
        )
    }
}
