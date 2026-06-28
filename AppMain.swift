//
//  AppMain.swift
//  VocabScanner
//
//  Created by brian.khuong on 28/6/26.
//

import Foundation
import SwiftUI
import AVFoundation
import Combine
import Vision

// --------------------------------------------------
// MARK: - App Entry
// --------------------------------------------------
@main
struct VocabScannerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// --------------------------------------------------
// MARK: - ContentView
// --------------------------------------------------
struct ContentView: View {
    @StateObject private var cameraModel = CameraModel()
    var body: some View {
        TabView {
            BookshelfView()
                .tabItem { Label("Bookshelf", systemImage: "books.vertical.fill") }
            CameraCaptureView(camera: cameraModel)
                .tabItem { Label("Scan", systemImage: "camera.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.accentColor)
    }
}

struct BookshelfView: View {
    var body: some View {
        NavigationStack {
            Text("My Books").font(.largeTitle).navigationTitle("Bookshelf")
        }
    }
}

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Text("Settings").navigationTitle("Settings")
        }
    }
}

// --------------------------------------------------
// MARK: - CameraModel
// --------------------------------------------------
final class CameraModel: NSObject, ObservableObject {
    @Published var capturedImage: UIImage? = nil
    @Published var permissionDenied = false
    @Published var isSessionReady = false
    
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private var isSettingUp = false
    
    func setupCamera() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            permissionDenied = false
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.permissionDenied = false
                        self.configureSession()
                    } else {
                        self.permissionDenied = true
                    }
                }
            }
        case .denied, .restricted:
            permissionDenied = true
        @unknown default:
            permissionDenied = true
        }
    }
    
    private func configureSession() {
        guard !isSettingUp else { return }
        isSettingUp = true
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }
            self.session.sessionPreset = .photo
            
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.isSessionReady = false; self.isSettingUp = false }
                return
            }
            
            self.session.addInput(input)
            if self.session.canAddOutput(self.output) {
                self.session.addOutput(self.output)
            }
            
            self.session.commitConfiguration()
            self.session.startRunning()
            
            DispatchQueue.main.async {
                self.isSessionReady = self.session.isRunning
                self.isSettingUp = false
            }
            
            NotificationCenter.default.removeObserver(self)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(self.sessionWasInterrupted),
                                                   name: AVCaptureSession.wasInterruptedNotification,
                                                   object: self.session)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(self.sessionInterruptionEnded),
                                                   name: AVCaptureSession.interruptionEndedNotification,
                                                   object: self.session)
        }
    }
    
    @objc private func sessionWasInterrupted() {
        DispatchQueue.main.async { self.isSessionReady = false }
    }
    
    @objc private func sessionInterruptionEnded() {
        sessionQueue.async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async { self?.isSessionReady = self?.session.isRunning ?? false }
        }
    }
    
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async { self?.isSessionReady = false }
        }
        NotificationCenter.default.removeObserver(self)
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else { return }
        DispatchQueue.main.async {
            self.capturedImage = image
        }
    }
}

// --------------------------------------------------
// MARK: - CameraCaptureView
// --------------------------------------------------
struct CameraCaptureView: View {
    @ObservedObject var camera: CameraModel
    @State private var showWordSelection = false
    
    var body: some View {
        ZStack {
            if camera.isSessionReady {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            }
            
            if camera.capturedImage == nil {
                VStack {
                    Spacer()
                    Button(action: { camera.capturePhoto() }) {
                        ZStack {
                            Circle().fill(Color.white).frame(width: 70, height: 70)
                            Circle().stroke(Color.white.opacity(0.3), lineWidth: 5).frame(width: 80, height: 80)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            
            if camera.permissionDenied {
                VStack(spacing: 20) {
                    Image(systemName: "camera.fill").font(.system(size: 50)).foregroundColor(.secondary)
                    Text("Camera Access Required").font(.title2).fontWeight(.semibold)
                    Text("Please enable camera access in Settings.").multilineTextAlignment(.center).foregroundColor(.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if !camera.isSessionReady && !camera.permissionDenied {
                ProgressView("Starting camera…")
            }
        }
        .onAppear { if camera.capturedImage == nil { camera.setupCamera() } }
        .onDisappear { camera.stopSession() }
        .onChange(of: camera.capturedImage) { _, newImage in
            if newImage != nil {
                showWordSelection = true
            }
        }
        .fullScreenCover(isPresented: $showWordSelection) {
            if let image = camera.capturedImage {
                WordSelectionView(
                    image: image,
                    onDismiss: {
                        showWordSelection = false
                        camera.capturedImage = nil
                    },
                    onProcess: { selectedWords in
                        print("✅ Selected words: \(selectedWords)")
                        // TODO: Show collection save UI here
                        showWordSelection = false
                        camera.capturedImage = nil
                    }
                )
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

final class PreviewView: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(previewLayer)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

// --------------------------------------------------
// MARK: - Word Selection UI (SwiftUI Wrapper + UIKit VC)
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
// MARK: - WordBoxView (Interactive Box)
// --------------------------------------------------
class WordBoxView: UIView {
    let word: String
    var isSelectedWord: Bool = false {
        didSet {
            backgroundColor = isSelectedWord ? UIColor.yellow.withAlphaComponent(0.4) : UIColor.clear
            layer.borderColor = isSelectedWord ? UIColor.yellow.cgColor : UIColor.gray.withAlphaComponent(0.3).cgColor
        }
    }
    
    init(word: String, frame: CGRect) {
        self.word = word
        super.init(frame: frame)
        layer.borderWidth = 1
        layer.cornerRadius = 2
        self.isSelectedWord = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// --------------------------------------------------
// MARK: - Word Selection View Controller
// --------------------------------------------------
class WordSelectionViewController: UIViewController, UIScrollViewDelegate {
    var image: UIImage!
    var onDismiss: (() -> Void)?
    var onProcess: (([String]) -> Void)?
    
    private var scrollView: UIScrollView!
    private var imageView: UIImageView!
    private var overlayView: UIView! // Holds all our bounding boxes
    private var bottomBar: UIView!
    private var wordScrollView: UIScrollView!
    private var wordStackView: UIStackView!
    
    private var selectedWords: [String] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        setupScrollView()
        setupImageView()
        setupBottomBar()
        runOCR()
    }
    private func updateSelectedLabel() {
        // Clean old bubbles out of the stack
        wordStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        if selectedWords.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "0 words selected"
            emptyLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            emptyLabel.textColor = .placeholderText
            wordStackView.addArrangedSubview(emptyLabel)
        } else {
            for word in selectedWords {
                // Generate a sleek bubble layout for each word
                let tagView = UIView()
                tagView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.15)
                tagView.layer.cornerRadius = 12
                tagView.clipsToBounds = true
                
                let label = UILabel()
                label.text = word
                label.textColor = .systemBlue
                label.font = UIFont.systemFont(ofSize: 13, weight: .bold)
                label.translatesAutoresizingMaskIntoConstraints = false
                
                tagView.addSubview(label)
                
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: tagView.leadingAnchor, constant: 10),
                    label.trailingAnchor.constraint(equalTo: tagView.trailingAnchor, constant: -10),
                    label.topAnchor.constraint(equalTo: tagView.topAnchor, constant: 4),
                    label.bottomAnchor.constraint(equalTo: tagView.bottomAnchor, constant: -4)
                ])
                
                wordStackView.addArrangedSubview(tagView)
            }
            
            // Auto-scroll to the end of the scrollview so the newest word is always visible
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                let rightOffset = CGPoint(x: max(0, self.wordScrollView.contentSize.width - self.wordScrollView.bounds.width), y: 0)
                self.wordScrollView.setContentOffset(rightOffset, animated: true)
            }
        }
    }


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
        
        // Setup overlay view inside the image view
        overlayView = UIView()
        overlayView.isUserInteractionEnabled = true
        imageView.addSubview(overlayView)
    }
    
    private func setupBottomBar() {
        bottomBar = UIView()
        bottomBar.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.95)
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)
        
        // 1. Setup the horizontal ScrollView for selected words
        wordScrollView = UIScrollView()
        wordScrollView.showsHorizontalScrollIndicator = false
        wordScrollView.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(wordScrollView)
        
        // 2. Setup the StackView inside the ScrollView to hold word bubbles
        wordStackView = UIStackView()
        wordStackView.axis = .horizontal
        wordStackView.spacing = 8
        wordStackView.alignment = .center
        wordStackView.translatesAutoresizingMaskIntoConstraints = false
        wordScrollView.addSubview(wordStackView)
        
        // 3. Setup Buttons
        let clearButton = UIButton(type: .system)
        clearButton.setTitle("Clear", for: .normal)
        clearButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        clearButton.addTarget(self, action: #selector(clearSelection), for: .touchUpInside)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(clearButton)
        
        let processButton = UIButton(type: .system)
        processButton.setTitle("Process", for: .normal)
        processButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        processButton.addTarget(self, action: #selector(processWords), for: .touchUpInside)
        processButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(processButton)
        
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.systemRed, for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(cancelButton)
        
        // 4. Set constraints
        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 95),
            
            // Word List ScrollView Constraints
            wordScrollView.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 8),
            wordScrollView.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            wordScrollView.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16),
            wordScrollView.heightAnchor.constraint(equalToConstant: 32),
            
            // StackView Constraints inside ScrollView
            wordStackView.leadingAnchor.constraint(equalTo: wordScrollView.contentLayoutGuide.leadingAnchor),
            wordStackView.trailingAnchor.constraint(equalTo: wordScrollView.contentLayoutGuide.trailingAnchor),
            wordStackView.topAnchor.constraint(equalTo: wordScrollView.contentLayoutGuide.topAnchor),
            wordStackView.bottomAnchor.constraint(equalTo: wordScrollView.contentLayoutGuide.bottomAnchor),
            wordStackView.heightAnchor.constraint(equalTo: wordScrollView.heightAnchor),
            
            // Controls Row Constraints
            clearButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 20),
            clearButton.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -12),
            
            cancelButton.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -12),
            
            processButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -20),
            processButton.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -12)
        ])
        
        // 5. Populate initial label state safely
        updateSelectedLabel()
    }

    private func runOCR() {
        // Use your specialized method that returns bounding boxes
        WordDetector.recognizeWords(in: image) { [weak self] words in
            DispatchQueue.main.async {
                self?.drawWordBoxes(words)
            }
        }
    }
    
    private func drawWordBoxes(_ words: [DetectedWord]) {
        // Clear any existing boxes
        overlayView.subviews.forEach { $0.removeFromSuperview() }
        
        // Calculate the exact frame where the image is drawn inside the UIImageView
        let displayedRect = AVMakeRect(aspectRatio: image.size, insideRect: imageView.bounds)
        overlayView.frame = displayedRect
        
        for word in words {
            let box = word.boundingBox
            
            // Vision framework coordinates: origin is bottom-left, normalized (0.0 to 1.0)
            // UIKit coordinates: origin is top-left
            let x = box.origin.x * displayedRect.width
            let y = (1 - box.origin.y - box.height) * displayedRect.height
            let width = box.width * displayedRect.width
            let height = box.height * displayedRect.height
            
            let rect = CGRect(x: x, y: y, width: width, height: height)
            let boxView = WordBoxView(word: word.text, frame: rect)
            
            let tap = UITapGestureRecognizer(target: self, action: #selector(wordTapped(_:)))
            boxView.addGestureRecognizer(tap)
            
            overlayView.addSubview(boxView)
        }
    }
    
    @objc private func wordTapped(_ gesture: UITapGestureRecognizer) {
        guard let boxView = gesture.view as? WordBoxView else { return }
        
        boxView.isSelectedWord.toggle()
        
        if boxView.isSelectedWord {
            selectedWords.append(boxView.word)
        } else {
            if let index = selectedWords.firstIndex(of: boxView.word) {
                selectedWords.remove(at: index)
            }
        }
        
        // Use the new helper method instead of the hardcoded count string
        updateSelectedLabel()
    }

    @objc private func clearSelection() {
        selectedWords.removeAll()
        updateSelectedLabel() // Reset label text
        
        // Reset all visual states
        for case let boxView as WordBoxView in overlayView.subviews {
            boxView.isSelectedWord = false
        }
    }

    @objc private func processWords() {
        onProcess?(selectedWords)
    }
    
    @objc private func cancelTapped() {
        onDismiss?()
    }
    
    // MARK: - Zooming
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
        
        // Only update frames if we aren't zooming to prevent layout resetting during zoom
        if scrollView.zoomScale == 1.0 {
            scrollView.frame = view.bounds
            imageView.frame = scrollView.bounds
            scrollView.contentSize = imageView.bounds.size
            
            // Re-align the overlay view when layout changes (e.g., orientation change)
            let displayedRect = AVMakeRect(aspectRatio: image.size, insideRect: imageView.bounds)
            overlayView.frame = displayedRect
        }
    }
}

// --------------------------------------------------
// MARK: - WordDetector
// --------------------------------------------------
struct DetectedWord: Identifiable {
    let id = UUID()
    let text: String
    let boundingBox: CGRect
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
                let rawWords = lineText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                guard !rawWords.isEmpty else { continue }
                
                let totalChars = rawWords.reduce(0) { $0 + $1.count }
                var currentX: CGFloat = 0
                
                for rawWord in rawWords {
                    let proportion = CGFloat(rawWord.count) / CGFloat(totalChars)
                    let wordWidth = lineBox.width * proportion
                    let wordHeight = lineBox.height
                    let wordX = lineBox.origin.x + currentX
                    let wordY = lineBox.origin.y
                    let wordBox = CGRect(x: wordX, y: wordY, width: wordWidth, height: wordHeight)
                    
                    words.append(DetectedWord(text: rawWord, boundingBox: wordBox))
                    currentX += wordWidth
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
        
        request.recognitionLevel = .accurate
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
