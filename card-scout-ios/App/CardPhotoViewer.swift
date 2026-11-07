import CardScoutCore
import SwiftUI
import UIKit

struct CardPhotoViewer: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var back = false
    @State private var original = false
    let cardID: String

    init(cardID: String, initialBack: Bool = false) {
        self.cardID = cardID
        _back = State(initialValue: initialBack)
    }

    var body: some View {
        if let card = store.library.cards.first(where: { $0.id == cardID }) {
            ZStack {
                Color.scoutPhotoBackdrop.ignoresSafeArea()
                LocalCardPhoto(name: back ? card.backFile : card.frontFile, maxPixel: 2600, original: original) { image, loading in
                    if let image {
                        ZoomableCardPhoto(image: image)
                            .id("\(back)-\(original)").padding(.horizontal, 10)
                            .accessibilityLabel(tr("\(card.title), \(back ? "Rückseite" : "Vorderseite")"))
                    } else if loading {
                        ProgressView(tr("Karte wird vorbereitet")).tint(.white).foregroundStyle(.white)
                    } else {
                        ScoutEmptyState(symbol: "photo", title: tr("Foto nicht verfügbar"))
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        ScoutEyebrow(tr("Deine Karte"))
                        Text(cardTitle(card)).font(.headline).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline).frame(width: 48, height: 48)
                            .background(Color.scoutElevated, in: Circle())
                    }.foregroundStyle(.white).accessibilityLabel(tr("Foto schließen"))
                }.padding(20).background(Color.scoutPhotoBackdrop)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 15) {
                    Toggle(tr("Originalfoto"), isOn: $original).tint(.scoutAccent)
                    if card.backFile != nil {
                        Picker(tr("Kartenseite"), selection: $back) {
                            Text(tr("Vorderseite")).tag(false)
                            Text(tr("Rückseite")).tag(true)
                        }.pickerStyle(.segmented)
                    }
                    Text(tr("Mit zwei Fingern zoomen")).font(.caption).foregroundStyle(Color.scoutMuted)
                }.padding(20).background(Color.scoutPhotoBackdrop)
            }
            .foregroundStyle(.white)
            .preferredColorScheme(.dark)
        } else {
            Button(tr("Schließen")) { dismiss() }
        }
    }
}

/// UIKit supplies native pan, pinch and accessible zoom actions without copying photos.
private struct ZoomableCardPhoto: UIViewRepresentable {
    let image: UIImage
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PhotoScrollView {
        let view = PhotoScrollView()
        view.delegate = context.coordinator
        context.coordinator.scroll = view
        view.minimumZoomScale = 1
        view.maximumZoomScale = 5
        view.bouncesZoom = true
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.contentInsetAdjustmentBehavior = .never
        view.imageView.contentMode = .scaleAspectFit
        view.imageView.image = image
        view.addSubview(view.imageView)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        view.addGestureRecognizer(tap)
        view.isAccessibilityElement = true
        view.accessibilityTraits = [.image]
        view.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Vergrößern", target: context.coordinator, selector: #selector(Coordinator.zoomIn)),
            UIAccessibilityCustomAction(name: "Verkleinern", target: context.coordinator, selector: #selector(Coordinator.zoomOut))
        ]
        return view
    }
    func updateUIView(_ view: PhotoScrollView, context: Context) {
        guard view.imageView.image !== image else { return }
        view.setZoomScale(1, animated: false)
        view.imageView.image = image
        view.invalidateImageLayout()
    }

    final class PhotoScrollView: UIScrollView {
        let imageView = UIImageView()
        private var previousSize = CGSize.zero
        func invalidateImageLayout() { previousSize = .zero; setNeedsLayout() }
        func centerImage() {
            let horizontal = max(0, (bounds.width - contentSize.width) / 2)
            let vertical = max(0, (bounds.height - contentSize.height) / 2)
            contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.size != previousSize, let image = imageView.image,
                  image.size.width > 0, image.size.height > 0 else { return }
            previousSize = bounds.size
            setZoomScale(1, animated: false)
            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            imageView.frame = CGRect(origin: .zero, size: fitted)
            contentSize = fitted
            centerImage()
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scroll: PhotoScrollView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { scroll?.imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { scroll?.centerImage() }
        @objc func doubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scroll else { return }
            let animated = !UIAccessibility.isReduceMotionEnabled
            if scroll.zoomScale > 1 { scroll.setZoomScale(1, animated: animated) }
            else {
                let point = recognizer.location(in: scroll.imageView)
                let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: animated)
            }
        }
        @objc func zoomIn() -> Bool {
            guard let scroll else { return false }
            scroll.setZoomScale(min(scroll.zoomScale * 2, scroll.maximumZoomScale), animated: false)
            return true
        }
        @objc func zoomOut() -> Bool {
            guard let scroll else { return false }
            scroll.setZoomScale(1, animated: false)
            return true
        }
    }
}
