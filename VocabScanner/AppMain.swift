import SwiftUI
import AVFoundation           // required for AVMakeRect
import Vision
import UIKit

// --------------------------------------------------
// MARK: - Word Selection View (SwiftUI wrapper)
// --------------------------------------------------
struct WordSelectionView: UIViewControllerRepresentable {
    let image: UIImage
    let onDismiss: () -> Void
    let onProcess: ([String]) -> Void

    func makeUIViewController(context: Context) -> WordSelectionViewController {
        let vc = WordSelectionViewController()
        vc.image = image
        vc.onDismiss = onDismiss
        vc.onProcess = onProcess
        return vc
    }

    func updateUIViewController(_ uiViewController: WordSelectionViewController, context: Context) {}
}

// --------------------------------------------------
// MARK: - UIKit View Controller
// --------------------------------------------------
class WordSelectionViewController: UIViewController, UIScrollViewDelegate {
    var image: UIImage!
    var onDismiss: (() -> Void)?
    var onProcess: (([String]) -> Void)?

    private var scrollView: UIScrollView!
    private var imageView: UIImageView!
    private var boxesContainer: UIView!
    private var wordBoxes: [UUID: UIView] = [:]
    private var selectedWordIDs = Set<UUID>()
    private var detectedWords: [DetectedWord] = []
    private var bottomBar: UIView!
    private var selectedLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupScrollView()
        setupImageView()
        setupBottomBar()
        runOCR()
    }

    // MARK: - Setup
    private func setupScrollView() {
        scrollView = UIScrollView(frame: view.bounds)
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)
    }

    private func setupImageView() {
        imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.frame = scrollView.bounds
        scrollView.addSubview(imageView)
        scrollView.contentSize = imageView.bounds.size

        boxesContainer = UIView(frame: imageView.bounds)
        boxesContainer.isUserInteractionEnabled = true
        imageView.addSubview(boxesContainer)
    }

    private func setupBottomBar() {
        bottomBar = UIView()
        bottomBar.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.9)
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)

        selectedLabel = UILabel()
        selectedLabel.text = "0 words selected"
        selectedLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        selectedLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(selectedLabel)

        let clearButton = UIButton(type: .system)
        clearButton.setTitle("Clear", for: .normal)
        clearButton.addTarget(self, action: #selector(clearSelection), for: .touchUpInside)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(clearButton)

        let processButton = UIButton(type: .system)
        processButton.setTitle("Process", for: .normal)
        processButton.addTarget(self, action: #selector(processWords), for: .touchUpInside)
        processButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(processButton)

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 60),

            selectedLabel.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            selectedLabel.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 8),

            clearButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 20),
            clearButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            processButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -20),
            processButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            cancelButton.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            cancelButton.topAnchor.constraint(equalTo: selectedLabel.bottomAnchor, constant: 4)
        ])
    }

    // MARK: - OCR
    private func runOCR() {
        WordDetector.recognizeWords(in: image) { [weak self] words in
            DispatchQueue.main.async {
                self?.detectedWords = words
                self?.drawWordBoxes(words)
            }
        }
    }

    // MARK: - Drawing word boxes
    private func drawWordBoxes(_ words: [DetectedWord]) {
        boxesContainer.subviews.forEach { $0.removeFromSuperview() }
        wordBoxes.removeAll()

        guard let image = image else { return }
        let imageViewSize = imageView.bounds.size
        let displayedRect = AVMakeRect(aspectRatio: image.size, insideRect: imageView.bounds)

        for word in words {
            let norm = word.boundingBox
            let x = displayedRect.origin.x + norm.origin.x * displayedRect.width
            let y = displayedRect.origin.y + (1 - norm.origin.y - norm.height) * displayedRect.height
            let w = norm.width * displayedRect.width
            let h = norm.height * displayedRect.height

            let box = UIView(frame: CGRect(x: x, y: y, width: w, height: h))
            box.backgroundColor = UIColor.white.withAlphaComponent(0.3)
            box.layer.borderColor = UIColor.systemBlue.cgColor
            box.layer.borderWidth = 1.0
            box.accessibilityLabel = word.id.uuidString
            box.isUserInteractionEnabled = true

            let tap = UITapGestureRecognizer(target: self, action: #selector(wordBoxTapped(_:)))
            box.addGestureRecognizer(tap)

            boxesContainer.addSubview(box)
            wordBoxes[word.id] = box
        }

        // Restore previous selection highlights
        for id in selectedWordIDs {
            if let box = wordBoxes[id] {
                box.backgroundColor = UIColor.yellow.withAlphaComponent(0.4)
            }
        }

        selectedLabel.text = "\(selectedWordIDs.count) word(s) selected"
    }

    @objc private func wordBoxTapped(_ gesture: UITapGestureRecognizer) {
        guard let box = gesture.view,
              let idString = box.accessibilityLabel,
              let id = UUID(uuidString: idString) else { return }

        if selectedWordIDs.contains(id) {
            selectedWordIDs.remove(id)
            box.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        } else {
            selectedWordIDs.insert(id)
            box.backgroundColor = UIColor.yellow.withAlphaComponent(0.4)
        }
        selectedLabel.text = "\(selectedWordIDs.count) word(s) selected"
    }

    @objc private func clearSelection() {
        selectedWordIDs.removeAll()
        for (id, box) in wordBoxes {
            box.backgroundColor = selectedWordIDs.contains(id)
                ? UIColor.yellow.withAlphaComponent(0.4)
                : UIColor.white.withAlphaComponent(0.3)
        }
        selectedLabel.text = "0 words selected"
    }

    @objc private func processWords() {
        let selected = detectedWords.filter { selectedWordIDs.contains($0.id) }.map { $0.text }
        onProcess?(selected)
    }

    @objc private func cancelTapped() {
        onDismiss?()
    }

    // MARK: - UIScrollViewDelegate
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
        imageView.frame.origin = CGPoint(x: offsetX, y: offsetY)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        imageView.frame = scrollView.bounds
        scrollView.contentSize = imageView.bounds.size
        boxesContainer.frame = imageView.bounds
        if !detectedWords.isEmpty {
            drawWordBoxes(detectedWords)   // redraw with correct layout
        }
    }
}

// --------------------------------------------------
// MARK: - WordDetector (word‑level bounding boxes)
// --------------------------------------------------
struct DetectedWord: Identifiable {
    let id = UUID()
    let text: String
    let boundingBox: CGRect   // normalized (0…1), Vision's bottom‑left origin
}

final class WordDetector {
    static func recognizeWords(in image: UIImage, completion: @escaping ([DetectedWord]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation],
                  error == nil else {
                completion([])
                return
            }

            var words: [DetectedWord] = []
            for observation in observations {
                guard let topCandidate = observation.topCandidates(1).first else { continue }
                let lineText = topCandidate.string
                let lineBox = observation.boundingBox
                let wordsInLine = lineText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                for word in wordsInLine {
                    words.append(DetectedWord(text: word, boundingBox: lineBox))
                }
            }

            words.sort { w1, w2 in
                let y1 = w1.boundingBox.origin.y + w1.boundingBox.height
                let y2 = w2.boundingBox.origin.y + w2.boundingBox.height
                if abs(y1 - y2) > 0.01 { return y1 > y2 }
                return w1.boundingBox.origin.x < w2.boundingBox.origin.x
            }
            completion(words)
        }
        request.recognitionLevel = VNRequestTextRecognitionLevel.accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ ui: UIImage.Orientation) {
        switch ui {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
