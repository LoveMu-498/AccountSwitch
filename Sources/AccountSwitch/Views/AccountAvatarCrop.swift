import AppKit
import SwiftUI

struct AccountAvatarCrop: View {
    let image: CGImage
    let editingSavedAvatar: Bool
    let cancel: () -> Void
    let apply: (Data) -> Void
    @GestureState private var drag: CGSize = .zero
    @GestureState private var pinch: MagnifyGesture.Value?
    @State private var position: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var failed = false

    private let viewport = CGSize(width: 412, height: 246)
    private var fitScale: CGFloat {
        let fit = min(viewport.width / CGFloat(image.width), viewport.height / CGFloat(image.height))
        return editingSavedAvatar ? min(fit, 184 / CGFloat(min(image.width, image.height))) : fit
    }
    private var diameter: CGFloat { min(184, CGFloat(min(image.width, image.height)) * fitScale) }
    private var previewZoom: CGFloat { limitedZoom(zoom * (pinch?.magnification ?? 1)) }

    private func imageSize(at zoom: CGFloat) -> CGSize {
        CGSize(width: CGFloat(image.width) * fitScale * zoom, height: CGFloat(image.height) * fitScale * zoom)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("裁剪头像").font(.title3.weight(.semibold))
            preview
            Text("双指移动图片，捏合缩放").font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: "minus.magnifyingglass").accessibilityHidden(true)
                Slider(value: $zoom, in: 1...3) { Text("缩放") }
                    .labelsHidden()
                    .accessibilityLabel("缩放")
                Image(systemName: "plus.magnifyingglass").accessibilityHidden(true)
            }
            .frame(maxWidth: 240)
            .onChange(of: zoom) { position = clamped(position, at: zoom) }
            if failed {
                Label("无法处理这张图片，请选择其他图片。", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
            Divider()
            HStack {
                Button("重置") {
                    zoom = 1
                    position = .zero
                }
                Spacer()
                Button("取消", action: cancel).keyboardShortcut(.cancelAction)
                Button("使用图片", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
    }

    private var preview: some View {
        let imageSize = imageSize(at: previewZoom)
        let translated = pinch.map { anchoredPosition(at: previewZoom, anchor: $0.startAnchor) } ?? position
        let center = clamped(CGSize(width: translated.width + drag.width, height: translated.height + drag.height),
                             at: previewZoom)
        return Rectangle()
            .fill(Color.black.opacity(0.24))
            .frame(width: viewport.width, height: viewport.height)
            .overlay {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: imageSize.width, height: imageSize.height)
                    .offset(x: center.width, y: center.height)
            }
            .overlay {
                CropShade(diameter: diameter)
                    .fill(.black.opacity(0.56), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                Circle()
                    .strokeBorder(.white.opacity(0.92), lineWidth: 1.5)
                    .frame(width: diameter, height: diameter)
                    .allowsHitTesting(false)
            }
            .clipShape(.rect(cornerRadius: 12))
            .background {
                CropTrackpadPan { if pinch == nil { move($0) } }
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .local)
                    .updating($drag) { value, translation, _ in translation = value.translation }
                    .onEnded { value in move(value.translation) }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, gesture, _ in gesture = value }
                    .onEnded { value in
                        let target = limitedZoom(zoom * value.magnification)
                        position = clamped(anchoredPosition(at: target, anchor: value.startAnchor), at: target)
                        zoom = target
                    }
            )
            .focusable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("圆形头像预览")
            .accessibilityHint("使用方向键移动图片")
            .onMoveCommand { direction in
                switch direction {
                case .left: move(CGSize(width: -8, height: 0))
                case .right: move(CGSize(width: 8, height: 0))
                case .up: move(CGSize(width: 0, height: -8))
                case .down: move(CGSize(width: 0, height: 8))
                @unknown default: break
                }
            }
    }

    private func move(_ delta: CGSize) {
        position = clamped(CGSize(width: position.width + delta.width, height: position.height + delta.height),
                           at: zoom)
    }

    private func limitedZoom(_ value: CGFloat) -> CGFloat { min(max(value, 1), 3) }

    private func anchoredPosition(at target: CGFloat, anchor: UnitPoint) -> CGSize {
        let ratio = target / zoom
        let x = (anchor.x - 0.5) * viewport.width
        let y = (anchor.y - 0.5) * viewport.height
        return CGSize(width: x + (position.width - x) * ratio, height: y + (position.height - y) * ratio)
    }

    private func clamped(_ value: CGSize, at zoom: CGFloat) -> CGSize {
        let imageSize = imageSize(at: zoom)
        let x = max(0, (imageSize.width - diameter) / 2)
        let y = max(0, (imageSize.height - diameter) / 2)
        return CGSize(width: min(max(value.width, -x), x), height: min(max(value.height, -y), y))
    }

    private func save() {
        let scale = fitScale * zoom
        let imageSize = imageSize(at: zoom)
        let center = clamped(position, at: zoom)
        let side = max(1, Int((diameter / scale).rounded(.down)))
        let x = min(image.width - side, max(0, Int((((imageSize.width - diameter) / 2 - center.width) / scale).rounded())))
        let y = min(image.height - side, max(0, Int((((imageSize.height - diameter) / 2 - center.height) / scale).rounded())))
        guard let data = AccountAvatar.encodeCrop(image, rect: CGRect(x: x, y: y, width: side, height: side)) else {
            failed = true
            return
        }
        apply(data)
    }
}

private struct CropTrackpadPan: NSViewRepresentable {
    let onPan: (CGSize) -> Void

    func makeNSView(context: Context) -> PanObserver { PanObserver() }

    func updateNSView(_ view: PanObserver, context: Context) {
        view.onPan = onPan
    }

    static func dismantleNSView(_ view: PanObserver, coordinator: ()) { view.stop() }

    final class PanObserver: WindowScrollObserver {
        var onPan: ((CGSize) -> Void)?

        override func consumeScroll(_ event: NSEvent, at point: NSPoint) -> Bool {
            guard visibleRect.contains(point), !event.phase.contains(.cancelled),
                  event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0
            else { return false }
            let scale: CGFloat = event.hasPreciseScrollingDeltas
                ? (event.isDirectionInvertedFromDevice ? 1 : -1)
                : 8
            let y = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : -event.scrollingDeltaY
            onPan?(CGSize(width: event.scrollingDeltaX * scale, height: y * scale))
            return true
        }
    }
}

private struct CropShade: Shape {
    let diameter: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.addRect(rect)
            path.addEllipse(in: CGRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2,
                                       width: diameter, height: diameter))
        }
    }
}
