import AppKit
import SwiftUI

struct SwipeCardAction: Identifiable {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var id: String { title }
}

struct AccountSwipeCard<Content: View>: View {
    let id: UUID
    @Binding var revealedCard: UUID?
    let copy: (() -> Void)?
    let shortcuts: [SwipeCardAction]
    let remove: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var dragging = false

    private let actionWidth: CGFloat = 66
    private var leftActions: [SwipeCardAction] {
        shortcuts + (remove.map { [.init(title: "移除", icon: "trash", color: .red, action: $0)] } ?? [])
    }
    private var leftWidth: CGFloat { CGFloat(leftActions.count) * actionWidth }

    var body: some View {
        content()
            .offset(x: offset)
            .background(alignment: offset > 0 ? .leading : .trailing) {
                if offset > 0, let copy {
                    actionPanel([.init(title: "复制", icon: "document.on.document", color: .blue, action: copy)], width: offset)
                } else if offset < 0, !leftActions.isEmpty {
                    actionPanel(leftActions, width: -offset)
                }
            }
            .background {
                HorizontalCardScroll { delta, phase, width in
                    switch phase {
                    case .changed:
                        if !dragging {
                            revealedCard = id
                            dragging = true
                        }
                        let minimum = leftActions.isEmpty ? 0 : -width
                        let maximum = copy == nil ? 0 : width
                        offset = min(max(offset + delta, minimum), maximum)
                    case .ended:
                        dragging = false
                        let triggerDistance = offset < 0
                            ? min(width, max(width * 0.54, leftWidth + 42))
                            : min(width * 0.54, 225)
                        if triggerDistance > 0, abs(offset) >= triggerDistance,
                           let action = offset > 0 ? copy : remove {
                            run(action)
                        } else {
                            settle(to: abs(offset) < 36 ? 0 : (offset > 0 ? actionWidth : -min(leftWidth, width)))
                        }
                    case .cancelled:
                        dragging = false
                        settle(to: 0)
                    }
                }
                .accessibilityHidden(true)
            }
            .clipped()
            .onChange(of: revealedCard) {
                if revealedCard != id, offset != 0 {
                    dragging = false
                    settle(to: 0)
                }
            }
            .onChange(of: remove != nil) {
                if remove == nil, offset < 0 { settle(to: 0) }
            }
    }

    private func actionPanel(_ actions: [SwipeCardAction], width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(actions) { item in
                let isLast = actions.last?.id == item.id
                Button { run(item.action) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon).font(.system(size: 15, weight: .medium))
                        Text(item.title).font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .fixedSize()
                    .frame(width: isLast ? max(actionWidth, width - CGFloat(actions.count - 1) * actionWidth) : actionWidth)
                    .frame(maxHeight: .infinity)
                    .background(item.color)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: width, alignment: offset > 0 ? .trailing : .leading)
        .clipped()
        .opacity(min(width / 28, 1))
        .allowsHitTesting(!dragging)
    }

    private func run(_ action: () -> Void) {
        settle(to: 0)
        action()
    }

    private func settle(to value: CGFloat) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { offset = value }
        if value == 0, revealedCard == id { revealedCard = nil }
    }
}

private struct HorizontalCardScroll: NSViewRepresentable {
    enum Phase { case changed, ended, cancelled }
    let onScroll: (CGFloat, Phase, CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollObserver { ScrollObserver() }

    func updateNSView(_ view: ScrollObserver, context: Context) {
        view.onScroll = onScroll
    }

    static func dismantleNSView(_ view: ScrollObserver, coordinator: ()) {
        view.stop()
    }

    final class ScrollObserver: WindowScrollObserver {
        var onScroll: ((CGFloat, Phase, CGFloat) -> Void)?
        private var tracking = false
        private var vertical = false
        private var wheelEnd: Task<Void, Never>?

        override func resetScroll() {
            wheelEnd?.cancel()
            wheelEnd = nil
            tracking = false
            vertical = false
        }

        override func consumeScroll(_ event: NSEvent, at point: NSPoint) -> Bool {
            let phase = event.phase
            if phase.contains(.mayBegin) || phase.contains(.began) {
                if tracking { finish(.cancelled) }
                vertical = false
            }
            if phase.contains(.cancelled) || phase.contains(.ended) {
                let wasTracking = tracking
                if tracking { finish(phase.contains(.cancelled) ? .cancelled : .ended) }
                vertical = false
                return wasTracking
            }
            let x = event.scrollingDeltaX
            let y = event.scrollingDeltaY
            if !tracking {
                guard !vertical, visibleRect.contains(point) else { return false }
                if abs(y) >= abs(x), y != 0 {
                    vertical = !phase.isEmpty
                    return false
                }
                guard abs(x) > abs(y) else { return false }
                tracking = true
            }
            let direction: CGFloat = event.hasPreciseScrollingDeltas && !event.isDirectionInvertedFromDevice ? -1 : 1
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 9
            onScroll?(x * direction * scale, .changed, bounds.width)
            if phase.isEmpty {
                wheelEnd?.cancel()
                wheelEnd = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(130))
                    guard !Task.isCancelled else { return }
                    self?.finish(.ended)
                }
            }
            return true
        }

        private func finish(_ phase: Phase) {
            tracking = false
            wheelEnd?.cancel()
            wheelEnd = nil
            onScroll?(0, phase, bounds.width)
        }
    }
}
