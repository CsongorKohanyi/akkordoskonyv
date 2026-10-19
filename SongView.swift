import SwiftUI
import UIKit

// MARK: - UIScrollView: szöveg (monospace) + opcionális kép, mindkét irányba görgethető

final class ContentScrollView: UIScrollView {
    let label = UILabel()
    let imageView = UIImageView()
    var songID: UUID?

    var image: UIImage? {
        didSet {
            imageView.image = image
            imageView.isHidden = (image == nil)
            dirty = true
            setNeedsLayout()
        }
    }

    private var dirty = true
    private var lastWidth: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.numberOfLines = 0
        addSubview(label)
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        addSubview(imageView)
        alwaysBounceVertical = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) nem támogatott") }

    func setText(_ s: NSAttributedString) {
        label.attributedText = s
        dirty = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard dirty || bounds.width != lastWidth else { return }
        dirty = false
        lastWidth = bounds.width

        let pad: CGFloat = 16
        let big: CGFloat = 100_000
        let size = label.sizeThatFits(CGSize(width: big, height: big))
        label.frame = CGRect(x: pad, y: 12, width: ceil(size.width), height: ceil(size.height))

        var contentW = label.frame.maxX + pad
        var contentH = label.frame.maxY + 12

        if let img = image, img.size.width > 0 {
            let w = max(bounds.width - 2 * pad, 1)
            let h = w * img.size.height / img.size.width
            imageView.frame = CGRect(x: pad, y: label.frame.maxY + 8, width: w, height: h)
            contentW = max(contentW, w + 2 * pad)
            contentH = imageView.frame.maxY + 12
        }

        let newSize = CGSize(width: contentW, height: contentH)
        if contentSize != newSize { contentSize = newSize }
    }
}

// MARK: - SwiftUI burkoló

struct SongView: UIViewRepresentable {
    let content: NSAttributedString
    let image: UIImage?
    let songID: UUID
    let scrolling: Bool
    let speed: Double
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ContentScrollView {
        let v = ContentScrollView()
        context.coordinator.scrollView = v
        return v
    }

    func updateUIView(_ v: ContentScrollView, context: Context) {
        let c = context.coordinator
        c.onEnd = onEnd

        if v.songID != songID {
            // új dal: újra az elejére
            v.songID = songID
            v.image = image
            v.setText(content)
            v.layoutIfNeeded()
            v.contentOffset = .zero
        } else if !(v.label.attributedText?.isEqual(to: content) ?? false) {
            // transzponálás / betűméret: a pozíció megmarad (keep_position)
            let off = v.contentOffset
            v.image = image
            v.setText(content)
            v.layoutIfNeeded()
            let maxY = max(0, v.contentSize.height - v.bounds.height)
            let maxX = max(0, v.contentSize.width - v.bounds.width)
            v.contentOffset = CGPoint(x: min(off.x, maxX), y: min(off.y, maxY))
        }
        c.setScrolling(scrolling, speed: speed)
    }

    static func dismantleUIView(_ uiView: ContentScrollView, coordinator: Coordinator) {
        coordinator.stop()
    }

    // MARK: automatikus görgetés (CADisplayLink, pixelpontos, folyamatos)

    final class Coordinator: NSObject {
        weak var scrollView: ContentScrollView?
        var onEnd: () -> Void = {}
        private var link: CADisplayLink?
        private var pointsPerSecond: Double = 15
        private var pos: CGFloat = 0

        func setScrolling(_ on: Bool, speed: Double) {
            pointsPerSecond = speed * 5          // 1…10 → 5…50 pont/mp
            if on {
                if link == nil {
                    pos = scrollView?.contentOffset.y ?? 0
                    let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
                    l.add(to: .main, forMode: .common)
                    link = l
                }
            } else {
                stop()
            }
        }

        func stop() {
            link?.invalidate()
            link = nil
        }

        @objc private func tick(_ l: CADisplayLink) {
            guard let sv = scrollView else { stop(); return }

            // ha az ujjaddal görgetsz, átveszed az irányítást
            if sv.isTracking || sv.isDragging || sv.isDecelerating {
                pos = sv.contentOffset.y
                return
            }

            let maxY = sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom
            if pos >= maxY {
                stop()
                DispatchQueue.main.async { self.onEnd() }
                return
            }
            let dt = l.targetTimestamp - l.timestamp
            pos += CGFloat(pointsPerSecond * dt)
            sv.contentOffset.y = min(pos, max(maxY, 0))
        }
    }
}
