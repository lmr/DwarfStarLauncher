import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: LayoutSubviews,
                      cache: inout Void) -> CGSize {
        var lines: [[LayoutSubview]] = [[]]
        var lineWidth: CGFloat = 0
        let maxWidth: CGFloat = proposal.width ?? .infinity

        for view in subviews {
            let viewSize = view.sizeThatFits(proposal)
            let viewWidth = viewSize.width
            if lineWidth + viewWidth > maxWidth && !lines.last!.isEmpty {
                lines.append([view])
                lineWidth = viewWidth
            } else {
                lines[lines.count - 1].append(view)
                lineWidth += viewWidth
            }
        }

        var height: CGFloat = 0
        for line in lines {
            if height > 0 { height += spacing }
            for view in line {
                let viewSize = view.sizeThatFits(proposal)
                height += viewSize.height
            }
        }

        var width: CGFloat = 0
        for line in lines {
            var lineW: CGFloat = 0
            for view in line {
                let viewSize = view.sizeThatFits(proposal)
                lineW += viewSize.width
            }
            lineW += CGFloat(line.count - 1) * spacing
            width = max(width, lineW)
        }

        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: LayoutSubviews,
                       cache: inout Void) {
        var lines: [[LayoutSubview]] = [[]]
        var lineWidth: CGFloat = 0
        let maxWidth: CGFloat = proposal.width ?? .infinity

        for view in subviews {
            let viewWidth = view.sizeThatFits(proposal).width
            if lineWidth + viewWidth > maxWidth && !lines.last!.isEmpty {
                lines.append([view])
                lineWidth = viewWidth
            } else {
                lines[lines.count - 1].append(view)
                lineWidth += viewWidth
            }
        }

        var y = bounds.minY

        for line in lines {
            var x = bounds.minX
            var lineHeight: CGFloat = 0
            for view in line {
                let viewSize = view.sizeThatFits(proposal)
                lineHeight = max(lineHeight, viewSize.height)
            }

            for view in line {
                let viewSize = view.sizeThatFits(proposal)
                let point = CGPoint(x: x, y: y + (lineHeight - viewSize.height) / 2)
                view.place(at: point, anchor: .topLeading, proposal: proposal)
                x += viewSize.width + spacing
            }

            y += lineHeight + spacing
        }
    }
}