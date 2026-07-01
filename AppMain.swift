//
//  AppMain.swift
//  VocabScanner
//
//  Created by brian.khuong on 28/6/26.
//

import Foundation
import SwiftUI
import SwiftData
import AVFoundation
import Combine
import Vision
import Translation
import NaturalLanguage

// --------------------------------------------------
// MARK: - App Entry
// --------------------------------------------------
@main
struct VocabScannerApp: App {
    @Environment(\.scenePhase) private var scenePhase  // ← this was missing

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Book.self, VocabCard.self, ActivityLog.self])  // ← removed duplicate
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                APIWarmup.shared.warmUpAll()
            }
        }
    }
}

// --------------------------------------------------
// MARK: - SwiftData Models
// --------------------------------------------------
@Model
final class Book {
    var title: String
    var author: String
    var dateAdded: Date
    
    @Relationship(deleteRule: .cascade)
    var cards: [VocabCard] = []
    
    init(title: String, author: String = "") {
        self.title = title
        self.author = author
        self.dateAdded = Date()
    }
}

enum DictionaryMode: String, CaseIterable, Identifiable {
    case bestMatch
    case allSenses
    
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .bestMatch: return "Best Match (Contextual)"
        case .allSenses: return "Multiple Senses"
        }
    }
}

struct DictionarySense: Codable, Identifiable, Hashable {
    var id = UUID()
    var definition: String
    var example: String?
    var wordType: String?
    var registerLabel: String?
    var pronunciationAudioURL: String?
    var isBestMatch: Bool = false
}

@Model
final class VocabCard {

    var word: String
    var pronunciation: String?
    var definition: String?
    var dictionaryExample: String? = nil
    var pronunciationAudioURL: String? = nil
    var wordType: String? = nil
    var registerLabel: String? = nil
    var origin: String? = nil
    var contextSentence: String
    var translation: String
    
    var easeFactor: Double = 2.5
    var interval: Int = 0
    var repetitions: Int = 0
    var nextReviewDate: Date
    
    var book: Book?
    
    var sortOrder: Int = 0
    
    var senses: [DictionarySense]? = nil

    
    init(word: String, contextSentence: String, translation: String = "", pronunciation: String = "", definition: String = "", dictionaryExample: String? = nil, pronunciationAudioURL: String? = nil, wordType: String? = nil, registerLabel: String? = nil, origin: String? = nil) {
        self.word = word
        self.contextSentence = contextSentence
        self.translation = translation
        self.pronunciation = pronunciation
        self.definition = definition
        self.dictionaryExample = dictionaryExample
        self.pronunciationAudioURL = pronunciationAudioURL
        self.nextReviewDate = Date()
        self.wordType = wordType
        self.registerLabel = registerLabel
        self.origin = origin
    }
}

// --------------------------------------------------
// MARK: - ContentView
// --------------------------------------------------
struct ContentView: View {
    @StateObject private var cameraModel = CameraModel()
    @State private var dueCount = 0
    @State private var selectedTab = 0
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView(selection: $selectedTab) {
            BookshelfView()
                .tabItem { Label("Bookshelf", systemImage: "books.vertical.fill") }
                .tag(0)
            
            CameraCaptureView(camera: cameraModel, isActive: selectedTab == 1)
                .tabItem { Label("Scan", systemImage: "camera.fill") }
                .tag(1)
            
            ReviewSessionView()
                .tabItem {
                    Label("Review", systemImage: "repeat.circle.fill")
                }
                .badge(dueCount)
                .tag(2)
            
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(.accentColor)
        .task {
            await updateDueCount()
        }
    }

    private func updateDueCount() async {
        let context = modelContext
        let now = Date()
        let predicate = #Predicate<VocabCard> { $0.nextReviewDate <= now }
        let descriptor = FetchDescriptor<VocabCard>(predicate: predicate)
        do {
            let count = try context.fetchCount(descriptor)
            await MainActor.run { dueCount = count }
        } catch {
            print("Failed to fetch due count: \(error)")
        }
    }
}
// --------------------------------------------------
// MARK: - Bookshelf Tab Views
// --------------------------------------------------
struct BookshelfView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.title) private var books: [Book]
    @State private var showMergeSheet = false
    @State private var showImporter = false
    @State private var showGrid = false
    var body: some View {
        NavigationStack {
            List {
                // Activity tracker at the top
                Section {
                    // Only show grid when Bookshelf is visible (slight performance gain)
                    if showGrid {
                        ActivityGridView()
                            .padding(.vertical, 8)
                    }
                }

                if books.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("Your bookshelf is empty.")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("Go to the 'Scan' tab to capture some words.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(books) { book in
                        NavigationLink(destination: BookDetailView(book: book)) {
                            HStack {
                                Image(systemName: "book.closed.fill")
                                    .foregroundColor(.accentColor)
                                    .font(.title2)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.title)
                                        .font(.headline)
                                    Text(String(book.cards.count) + " word(s)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: deleteBooks)
                }
            }
            .navigationTitle("Bookshelf")
            .onAppear { showGrid = true }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showMergeSheet = true
                    } label: {
                        Label("Merge Books", systemImage: "arrow.triangle.merge")
                    }
                }
            }
            .sheet(isPresented: $showMergeSheet) {
                MergeBooksView()
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                onCompletion: handleImport
            )
        }
    }
    
    private func deleteBooks(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(books[index])
        }
    }
    
    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let data = try Data(contentsOf: url)
                let bookExport = try JSONDecoder().decode(BookExport.self, from: data)
                // Create a new book with imported cards
                let newBook = Book(title: bookExport.title, author: bookExport.author)
                modelContext.insert(newBook)
                for (index, cardExport) in bookExport.cards.enumerated() {
                    let card = cardExport.toVocabCard()
                    card.sortOrder = index
                    modelContext.insert(card)
                    newBook.cards.append(card)
                    card.book = newBook
                }
                try? modelContext.save()
            } catch {
                print("Import failed: \(error)")
            }
        case .failure(let error):
            print("File picker error: \(error)")
        }
    }
}

struct BookDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var book: Book          // Changed to @Bindable for editing
    @State private var isEditingTitle = false
    @State private var newTitle = ""
    @State private var searchText = ""

    // Export state
    @State private var isExporting = false
    @State private var exportData: Data?

    // Filtered cards based on search
    var filteredCards: [VocabCard] {
        if searchText.isEmpty {
            return book.cards.sorted { $0.sortOrder < $1.sortOrder }
        } else {
            return book.cards.filter {
                $0.word.localizedCaseInsensitiveContains(searchText) ||
                ($0.definition?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                $0.contextSentence.localizedCaseInsensitiveContains(searchText)
            }.sorted { $0.sortOrder < $1.sortOrder }
        }
    }

    var body: some View {
        List {
            ForEach(filteredCards) { card in
                // ... (same card row content as before, unchanged)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(card.word)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.accentColor)
                        Button {
                            print("[Audio] Word speaker tapped")
                            SpeechService.pronounce(word: card.word, audioURL: card.pronunciationAudioURL)
                        } label: {
                            Image(systemName: "speaker.wave.2")
                                .font(.title3)
                                .frame(width: 32, height: 32)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        if let pronunciation = card.pronunciation, !pronunciation.isEmpty, pronunciation != "N/A" {
                            Text(pronunciation)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    
                    // Definition
                    // 👇 NEW: Replaced the old definition views with the new paging component
                    MultiSensePagingView(card: card)

                    
                    // Extra dictionary info
                    if let wt = card.wordType {
                        Text(wt)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    if let reg = card.registerLabel {
                        Text(reg)
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                    if let orig = card.origin {
                        Text("Origin: \(orig)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Dictionary example
                    if let dictEx = card.dictionaryExample, !dictEx.isEmpty {
                        HStack(spacing: 8) {
                            Rectangle()
                                .fill(Color.orange.opacity(0.4))
                                .frame(width: 3)
                            Text(dictEx)
                                .font(.subheadline)
                                .foregroundColor(.orange)
                            Spacer()
                            Button {
                                print("[Audio] Dictionary example speaker tapped")
                                SpeechService.speak(text: dictEx)
                            } label: {
                                Image(systemName: "speaker.wave.2")
                                    .font(.caption)
                                    .frame(width: 28, height: 28)
                                    .background(Color.gray.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.leading, 4)
                    }
                    
                    // Context sentence
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Context Sentence:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        Text(card.contextSentence)
                            .font(.footnote)
                            .italic()
                        if !card.translation.isEmpty && card.translation != "Translation unavailable" {
                            Text(card.translation)
                                .font(.footnote)
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 6)
            }
            .onDelete(perform: deleteCards)
            .onMove(perform: moveCards)          // ← drag to reorder
        }
        .navigationTitle(book.title)
        .searchable(text: $searchText, prompt: "Search words, definitions, sentences")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        newTitle = book.title
                        isEditingTitle = true
                    } label: {
                        Label("Edit Title", systemImage: "pencil")
                    }
                    Button {
                        exportBook()
                    } label: {
                        Label("Export as JSON", systemImage: "square.and.arrow.up")
                    }
                    EditButton()     // built‑in button to enable moving rows
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Edit Book Title", isPresented: $isEditingTitle) {
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    book.title = newTitle
                    try? modelContext.save()
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: ExportDocument(data: exportData ?? Data()),
            contentType: .json,
            defaultFilename: "\(book.title.replacingOccurrences(of: " ", with: "_")).json"
        ) { result in
            // Handle export result if needed
        }
    }

    private func deleteCards(at offsets: IndexSet) {
        for index in offsets {
            let card = filteredCards[index]
            modelContext.delete(card)
        }
        try? modelContext.save()
    }

    private func moveCards(from source: IndexSet, to destination: Int) {
        var cards = book.cards.sorted { $0.sortOrder < $1.sortOrder }
        cards.move(fromOffsets: source, toOffset: destination)
        // Reassign sortOrder to reflect new order
        for (index, card) in cards.enumerated() {
            card.sortOrder = index
        }
        try? modelContext.save()
    }

    private func exportBook() {
        let exportCards = book.cards.map { VocabCardExport(from: $0) }
        let bookExport = BookExport(title: book.title, author: book.author, cards: exportCards)
        do {
            let data = try JSONEncoder().encode(bookExport)
            exportData = data
            isExporting = true
        } catch {
            print("Export failed: \(error)")
        }
    }
}

// Helper for fileExporter
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}

struct SettingsView: View {
    // Persisted settings
    @AppStorage("maxDailyReviews") private var maxDailyReviews = 20        // 0 = unlimited
    @AppStorage("notificationHour") private var notificationHour = 9       // 24‑hour format
    @AppStorage("notificationMinute") private var notificationMinute = 0
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("learningStyle") private var learningStyle = LearningStyle.definitionFirst.rawValue
    @AppStorage("hintSource") private var hintSource = "dictionary"
    @AppStorage("dictionaryMode") private var dictionaryMode = DictionaryMode.bestMatch.rawValue
    @State private var showTimePicker = false


    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Reviews
                Section {
                    Stepper("Max reviews per day: \(maxDailyReviews == 0 ? "Unlimited" : "\(maxDailyReviews)")",
                            value: $maxDailyReviews, in: 0...100, step: 5)
                    if maxDailyReviews > 0 {
                        Text("You will see up to \(maxDailyReviews) due cards each day.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("All due cards will be shown.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("Daily Reviews", systemImage: "repeat.circle")
                }

                // MARK: - Notifications
                Section {
                    Toggle("Enable Daily Reminder", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, newValue in
                            if newValue {
                                requestNotificationPermissionIfNeeded()
                            } else {
                                cancelAllNotifications()
                            }
                        }

                    if notificationsEnabled {
                        Button {
                            showTimePicker = true
                        } label: {
                            HStack {
                                Text("Reminder Time")
                                Spacer()
                                Text(formattedTime)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if showTimePicker {
                            DatePicker(
                                "Select time",
                                selection: Binding(
                                    get: { Date.from(hour: notificationHour, minute: notificationMinute) },
                                    set: { newDate in
                                        let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                                        notificationHour = components.hour ?? 9
                                        notificationMinute = components.minute ?? 0
                                        scheduleNotification()
                                    }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                        }
                    }
                } header: {
                    Label("Notifications", systemImage: "bell")
                } footer: {
                    if notificationsEnabled {
                        Text("You'll receive a daily reminder to review your vocabulary.")
                    }
                }

                // MARK: - Learning Style
                Section {
                    Picker("Flashcard Style", selection: $learningStyle) {
                        ForEach(LearningStyle.allCases) { style in
                            Text(style.displayName).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.menu)

                    if let currentStyle = LearningStyle(rawValue: learningStyle) {
                        Text(currentStyle.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("Learning Style", systemImage: "brain.head.profile")
                }

                // MARK: - Hint Source
                Section {
                    Picker("Hint Source", selection: $hintSource) {
                        Text("Dictionary Example").tag("dictionary")
                        Text("Book Sentence (blanked)").tag("book")
                    }
                    .pickerStyle(.menu)

                    if hintSource == "dictionary" {
                        Text("The dictionary's example sentence will be shown during review (if available).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("The book's sentence with the word blanked will be shown as the hint.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("Hint", systemImage: "lightbulb")
                }
                
                // MARK: - Dictionary Mode
                Section {
                    Picker("Dictionary Mode", selection: $dictionaryMode) {
                        ForEach(DictionaryMode.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    if dictionaryMode == DictionaryMode.bestMatch.rawValue {
                        Text("Automatically shows the definition that best matches your book's sentence on the first page.")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        Text("Shows multiple dictionary meanings in standard order. You can swipe through them.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                } header: {
                    Label("Dictionary", systemImage: "text.book.closed")
                }
            }
            .navigationTitle("Settings")

        }
        .onAppear {
            // Schedule notification if already enabled (e.g., after app restart)
            if notificationsEnabled {
                requestNotificationPermissionIfNeeded()
                scheduleNotification()
            }
        }
    }

    // MARK: - Helpers

    private var formattedTime: String {
        let hour = notificationHour % 12 == 0 ? 12 : notificationHour % 12
        let ampm = notificationHour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", hour, notificationMinute, ampm)
    }

    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if !granted {
                DispatchQueue.main.async {
                    notificationsEnabled = false
                }
            }
        }
    }

    private func scheduleNotification() {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to review!"
        content.body = "You have vocabulary cards due today. Keep your streak going!"
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = notificationHour
        dateComponents.minute = notificationMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "dailyReviewReminder", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification scheduling error: \(error.localizedDescription)")
            }
        }
    }

    private func cancelAllNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["dailyReviewReminder"])
    }
}

// MARK: - Learning style enum
enum LearningStyle: String, CaseIterable, Identifiable {
    case definitionFirst
    case wordFirst
    case cloze

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .definitionFirst: return "Definition First"
        case .wordFirst: return "Word First"
        case .cloze: return "Cloze (Sentence blanked)"
        }
    }

    var description: String {
        switch self {
        case .definitionFirst: return "You see the definition → hint (sentence) → answer (word + translation)."
        case .wordFirst: return "You see the word → recall meaning → tap for translation/sentence."
        case .cloze: return "Sentence with the word blanked → guess the word → reveal."
        }
    }
}

// Helper to create Date from hour/minute
extension Date {
    static func from(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date()
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
    private var isConfigured = false
    
    func startCamera() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            permissionDenied = false
            sessionQueue.async { [weak self] in
                guard let self = self else { return }
                if !self.isConfigured {
                    self.configureSession()
                }
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                DispatchQueue.main.async {
                    self.isSessionReady = self.session.isRunning
                }
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.permissionDenied = false
                        self.startCamera()
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
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        
        session.commitConfiguration()
        isConfigured = true
    }
    
    func stopCamera() {
        sessionQueue.async { [weak self] in
            if self?.session.isRunning == true {
                self?.session.stopRunning()
            }
            DispatchQueue.main.async {
                self?.isSessionReady = false
            }
        }
    }
    
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(), let image = UIImage(data: imageData) else { return }
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
    let isActive: Bool          // ← new
    @State private var showWordSelection = false
    @State private var selectedWordsToTranslate: [DetectedWord] = []
    @State private var finalItemsToSave: [PendingVocabItem] = []
    @State private var showSaveSheet = false
    @State private var isProcessing = false
    @State private var translationTask: Task<Void, Never>? = nil
    
    var body: some View {
        ZStack {
            if camera.isSessionReady {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            }
            
            if !isProcessing && camera.capturedImage == nil {
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
                }
                .padding()
            } else if !camera.isSessionReady && !camera.permissionDenied {
                ProgressView("Starting camera...")
            }
            
            if isProcessing {
                VStack {
                    ProgressView("Analyzing & Translating...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                        .foregroundColor(.white)
                }
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                camera.startCamera()
            } else {
                camera.stopCamera()
            }
        }
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
                        camera.startCamera()
                    },
                    onProcess: { selectedWords in
                        selectedWordsToTranslate = selectedWords
                        showWordSelection = false
                        camera.capturedImage = nil
                        isProcessing = true
                        
                        translationTask?.cancel()
                        translationTask = Task {
                            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6 s
                            
                            if Task.isCancelled { return }
                            
                            let session = TranslationSession(
                                installedSource: Locale.Language(identifier: "en-US"),
                                target: Locale.Language(identifier: "vi-VN")
                            )
                            
                            var pending = await MainActor.run {
                                selectedWordsToTranslate.map {
                                    PendingVocabItem(word: $0.text, originalSentence: $0.contextSentence)
                                }
                            }
                            
                            for i in pending.indices {
                                if Task.isCancelled { break }
                                do {
                                    let response = try await session.translate(pending[i].originalSentence)
                                    pending[i].translatedSentence = response.targetText
                                } catch {
                                    pending[i].translatedSentence = "Translation unavailable"
                                    print("Translation error: \(error.localizedDescription)")
                                }
                            }
                            
                            await MainActor.run {
                                self.finalItemsToSave = pending
                                self.isProcessing = false
                                self.showSaveSheet = true
                            }
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showSaveSheet, onDismiss: {
            self.selectedWordsToTranslate = []
            self.finalItemsToSave = []
            self.translationTask?.cancel()
            self.translationTask = nil
            camera.startCamera()
        }) {
            SaveToCollectionView(itemsToSave: $finalItemsToSave)
        }
    }
}

// --------------------------------------------------
// MARK: - Camera Preview Components
// --------------------------------------------------
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
    let onProcess: ([DetectedWord]) -> Void
    
    func makeUIViewController(context: Context) -> WordSelectionViewController {
        let vc = WordSelectionViewController()
        vc.image = image
        vc.onDismiss = onDismiss
        vc.onProcess = onProcess
        return vc
    }
    
    func updateUIViewController(_ uiViewController: WordSelectionViewController, context: Context) {}
}

class WordBoxView: UIView {
    let detectedWord: DetectedWord
    var isSelectedWord: Bool = false {
        didSet { updateAppearance() }
    }
    var isPhrase: Bool = false {
        didSet { updateAppearance() }
    }
    
    init(detectedWord: DetectedWord, frame: CGRect) {
        self.detectedWord = detectedWord
        super.init(frame: frame)
        layer.borderWidth = 1
        layer.cornerRadius = 2
        updateAppearance()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func updateAppearance() {
        if isSelectedWord {
            backgroundColor = UIColor.yellow.withAlphaComponent(0.4)
        } else {
            backgroundColor = isPhrase ? UIColor.systemTeal.withAlphaComponent(0.15) : UIColor.clear
        }
        
        if isPhrase {
            layer.borderColor = UIColor.systemTeal.withAlphaComponent(0.7).cgColor
            layer.borderWidth = 2
        } else {
            layer.borderColor = isSelectedWord ? UIColor.yellow.cgColor : UIColor.gray.withAlphaComponent(0.3).cgColor
            layer.borderWidth = 1
        }
    }
}

// --------------------------------------------------
// MARK: - SaveToCollectionView
// --------------------------------------------------
struct SaveToCollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Book.title) private var books: [Book]
    
    @Binding var itemsToSave: [PendingVocabItem]
    
    @State private var selectedBook: Book? = nil
    @State private var newBookTitle = ""
    @State private var isCreatingNewBook = false
    @AppStorage("dictionaryMode") private var dictionaryMode = DictionaryMode.bestMatch.rawValue

    
    var body: some View {
        NavigationStack {
            VStack {
                Form {
                    Section("Save to Book") {
                        Toggle("Create New Book", isOn: $isCreatingNewBook)
                        
                        if isCreatingNewBook {
                            TextField("Book Title (e.g., 'Atomic Habits')", text: $newBookTitle)
                        } else {
                            Picker("Select Book", selection: $selectedBook) {
                                Text("Select a book...").tag(nil as Book?)
                                ForEach(books) { book in
                                    Text(book.title).tag(book as Book?)
                                }
                            }
                        }
                    }
                    
                    Section("Words & Sentences to Import") {
                        if itemsToSave.isEmpty {
                            ProgressView("Analyzing text...")
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            ForEach(0..<itemsToSave.count, id: \.self) { index in
                                VocabItemRowView(item: $itemsToSave[index])
                            }
                        }
                    }
                }
                
                Button(action: saveCards) {
                    Text("Save " + String(itemsToSave.count) + " Word(s)")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .disabled(isSaveDisabled)
            }
            .navigationTitle("Save Vocabulary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                Task {
                    await lookupDefinitionsAndPronunciations()
                }
            }
        }
    }
    
    private var isSaveDisabled: Bool {
        if isCreatingNewBook {
            return newBookTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            return selectedBook == nil
        }
    }
    
    private func lookupDefinitionsAndPronunciations() async {
        for i in itemsToSave.indices {
            let word = itemsToSave[i].word.trimmingCharacters(in: .punctuationCharacters)
            
            // Try Merriam‑Webster first
            do {
                if let mwResult = try await MerriamWebster.lookup(word: word),
                   !mwResult.senses.isEmpty {

                    // Clear any stale isBestMatch flags before reordering
                    var senses = mwResult.senses
                    for j in senses.indices { senses[j].isBestMatch = false }

                    // Primary path: ask LLM to pick the best sense using sentence context
                    if let wsdResult = await LLMWSD.selectBestSense(
                        word: word,
                        sentence: itemsToSave[i].originalSentence,
                        senses: senses
                    ) {
                        // Pull the winner out, flag it, reinsert at front
                        var best = senses.remove(at: wsdResult.bestIndex)
                        best.isBestMatch = wsdResult.confidence >= 0.75
                        senses.insert(best, at: 0)
                    } else {
                        // Offline fallback: use local heuristic ranking
                        print("[LLMWSD] Unavailable, falling back to local ranking")
                        senses = rankSenses(senses,
                                            contextSentence: itemsToSave[i].originalSentence,
                                            word: word,
                                            mode: dictionaryMode)
                    }

                    await MainActor.run {
                        itemsToSave[i].senses = senses

                        if let bestSense = senses.first {
                            itemsToSave[i].definition = bestSense.definition
                            itemsToSave[i].dictionaryExample = bestSense.example
                            itemsToSave[i].wordType = bestSense.wordType
                            itemsToSave[i].registerLabel = bestSense.registerLabel
                            itemsToSave[i].pronunciationAudioURL = bestSense.pronunciationAudioURL
                        }

                        if let pron = mwResult.pronunciation {
                            itemsToSave[i].pronunciation = pron
                        } else {
                            itemsToSave[i].pronunciation = "N/A"
                        }
                        itemsToSave[i].origin = mwResult.origin

                        print("[MW Debug] Successfully resolved \(senses.count) senses.")
                    }
                    continue
                }
            } catch {
                print("Merriam‑Webster error: \(error)")
            }
            
            // Fallback to free Dictionary API
            await lookupFreeDictionary(for: i)
        }
    }
    private func rankSenses(_ senses: [DictionarySense], contextSentence: String, word: String, mode: String) -> [DictionarySense] {
        guard !senses.isEmpty else { return [] }

        // Declared before lemmatizedWords since Swift requires local vars to be
        // declared lexically before any nested function references them.
        let stopWords: Set<String> = ["a", "an", "the", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with",
                                      "by", "as", "is", "are", "was", "were", "be", "been", "being", "it", "this", "that",
                                      "he", "she", "they", "we", "i", "you", "his", "her", "their", "my", "your", "has",
                                      "have", "had", "do", "does", "did", "out", "from", "up", "down", "which", "who", "whom"]

        // Lemmatize so inflected forms match their dictionary headword (e.g. "flew" -> "fly",
        // "wings" -> "wing"). Without this, keyword overlap misses real matches and is
        // dominated by incidental single-word coincidences.
        func lemmatizedWords(from text: String) -> Set<String> {
            let tagger = NLTagger(tagSchemes: [.lemma])
            tagger.string = text
            var result = Set<String>()
            tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma) { tag, range in
                let lemma = (tag?.rawValue ?? String(text[range])).lowercased()
                if !lemma.isEmpty && !stopWords.contains(lemma) {
                    result.insert(lemma)
                }
                return true
            }
            return result
        }

        // Clear any stale flags from a prior ranking pass (e.g. dictionaryMode toggled
        // after senses were already computed/cached).
        var senses = senses
        for i in senses.indices { senses[i].isBestMatch = false }

        if mode == DictionaryMode.allSenses.rawValue {
            var ordered = senses
            ordered[0].isBestMatch = true
            return ordered
        }

        // 1. POS detection with full lexical class
        // Tokenize into whole words and match the exact token, rather than range(of:),
        // which can match a substring (e.g. "cat" inside "category") or the wrong
        // occurrence of a repeated word.
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = contextSentence

        let wordTokenizer = NLTokenizer(unit: .word)
        wordTokenizer.string = contextSentence
        var matchedRange: Range<String.Index>? = nil
        wordTokenizer.enumerateTokens(in: contextSentence.startIndex..<contextSentence.endIndex) { tokenRange, _ in
            if contextSentence[tokenRange].caseInsensitiveCompare(word) == .orderedSame {
                matchedRange = tokenRange
                return false // stop at first whole-word match
            }
            return true
        }
        let anchor = matchedRange?.lowerBound ?? contextSentence.startIndex
        let (contextTag, _) = tagger.tag(at: anchor, unit: .word, scheme: .lexicalClass)
        let contextPos = contextTag?.rawValue ?? ""

        // Map dictionary sense wordType to canonical POS
        func canonicalPOS(from sense: DictionarySense) -> String {
            guard let type = sense.wordType?.lowercased() else { return "" }
            if type.contains("verb") { return "Verb" }
            if type.contains("noun") { return "Noun" }
            if type.contains("adjective") { return "Adjective" }
            if type.contains("adverb") { return "Adverb" }
            if type.contains("pronoun") { return "Pronoun" }
            return type
        }

        // 2. Build context keywords with TF‑IDF‑like weighting across all senses
        let cleanContext = contextSentence.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let contextWords = lemmatizedWords(from: contextSentence)

        // IDF‑like weights: log(totalSenses / document frequency)
        let totalSenses = Double(senses.count)
#if DEBUG
for sense in senses {
    print("[RankDebug] word='\(word)' rawType='\(sense.wordType ?? "nil")' canonical='\(canonicalPOS(from: sense))' contextPOS='\(contextPos)'")
}
#endif
        var wordDocCount: [String: Int] = [:]
        for sense in senses {
            let text = "\(sense.definition) \(sense.example ?? "")"
            let uniqueWords = lemmatizedWords(from: text)
            for w in uniqueWords {
                wordDocCount[w, default: 0] += 1
            }
        }

        // 3. Scoring
        let embedding = NLEmbedding.sentenceEmbedding(for: .english)
        let contextEmbedding = embedding?.vector(for: cleanContext)
        #if DEBUG
        print("[RankDebug] embedding available: \(embedding != nil), contextEmbedding available: \(contextEmbedding != nil)")
        #endif

        // First pass: compute raw component scores per sense (no weighting yet).
        struct RawScore {
            let sense: DictionarySense
            let posScore: Double
            let keywordScore: Double
            let semanticScore: Double
            let exampleScore: Double
            let hasExample: Bool
        }

        var rawScores: [RawScore] = senses.map { sense in
            let senseText = "\(sense.definition) \(sense.example ?? "")"
            let senseWordsSet = lemmatizedWords(from: senseText)

            // A. POS match score
            var posScore = 0.0
            let sensePOS = canonicalPOS(from: sense)
            if !sensePOS.isEmpty && !contextPos.isEmpty {
                if sensePOS == contextPos {
                    posScore = 1.0
                } else if (sensePOS == "Adjective" && contextPos == "Adverb") ||
                          (sensePOS == "Adverb" && contextPos == "Adjective") {
                    posScore = 0.5
                } else if (contextPos == "Noun" && sensePOS == "Adjective") ||
                          (contextPos == "Verb" && sensePOS == "Adverb") {
                    posScore = -0.5
                } else {
                    posScore = -1.5
                }
            }

            // B. Word-embedding-based content overlap. Exact-string / lemma matching misses
            // inflected and related forms (e.g. "flew" vs "flies" vs "wing"/"wings") because
            // NLTagger's .lemma scheme frequently fails to normalize irregular or
            // context-ambiguous words. Instead, compare each context content word's embedding
            // against each sense content word's embedding and take the best match per word —
            // this captures near-synonyms and inflections without requiring exact equality.
            // B. Word-embedding-based content overlap.
            var keywordScore = 0.0
            if let wordEmbedding = embedding {
                // Exclude the word being looked up from context keywords — it matches
                // every sense equally (all definitions are definitions *of* that word),
                // so it contributes no discriminating signal, only noise.
                let filteredContextWords = contextWords.filter {
                    $0.lowercased() != word.lowercased()
                }

                for cWord in filteredContextWords {
                    guard let cVec = wordEmbedding.vector(for: cWord) else { continue }
                    var bestSim = 0.0
                    for sWord in senseWordsSet {
                        // Also skip the target word inside sense vocabulary
                        guard sWord.lowercased() != word.lowercased() else { continue }
                        guard let sVec = wordEmbedding.vector(for: sWord) else { continue }
                        let dot = zip(cVec, sVec).map(*).reduce(0, +)
                        let magA = sqrt(cVec.map { $0 * $0 }.reduce(0, +))
                        let magB = sqrt(sVec.map { $0 * $0 }.reduce(0, +))
                        guard magA > 0, magB > 0 else { continue }
                        let cosine = dot / (magA * magB)
                        if cosine > bestSim { bestSim = cosine }
                    }
                    // Raised from 0.4 to 0.65 — only count genuinely close semantic
                    // matches (near-synonyms, inflected forms like flew/fly), not the
                    // broad background similarity all English words share in embedding space.
                    if bestSim > 0.65 {
                        let docFreq = Double(wordDocCount[cWord] ?? 1)
                        let idf = log(totalSenses / max(docFreq, 1))
                        keywordScore += bestSim * max(idf, 0.1)
                    }
                }
            }
            // C. Semantic distance (cosine similarity) — raw, will be centered below
            var semanticScore = 0.0
            if let contextVec = contextEmbedding, let senseVec = embedding?.vector(for: senseText) {
                let dot = zip(contextVec, senseVec).map(*).reduce(0, +)
                let magA = sqrt(contextVec.map { $0 * $0 }.reduce(0, +))
                let magB = sqrt(senseVec.map { $0 * $0 }.reduce(0, +))
                if magA > 0 && magB > 0 {
                    semanticScore = (dot / (magA * magB) + 1) / 2
                }
            }

            // D. Example sentence bonus — raw, will be centered below.
            // Only computed when an example exists; senses without one are excluded
            // from the mean rather than silently scored as 0, so lacking an example
            // doesn't get punished relative to senses that have one.
            var exampleScore = 0.0
            let hasExample = sense.example != nil && !(sense.example!.isEmpty)
            if hasExample, let contextVec = contextEmbedding, let exampleVec = embedding?.vector(for: sense.example!.lowercased()) {
                let dot = zip(contextVec, exampleVec).map(*).reduce(0, +)
                let magA = sqrt(contextVec.map { $0 * $0 }.reduce(0, +))
                let magB = sqrt(exampleVec.map { $0 * $0 }.reduce(0, +))
                if magA > 0 && magB > 0 {
                    exampleScore = (dot / (magA * magB) + 1) / 2
                }
            }

            return RawScore(sense: sense, posScore: posScore, keywordScore: keywordScore,
                             semanticScore: semanticScore, exampleScore: exampleScore, hasExample: hasExample)
        }

        // Center semantic score around the mean across all senses of this word —
        // this removes NLEmbedding's baseline noise (unrelated sentences routinely
        // cosine ~0.5-0.7) and keeps only the *relative* signal.
        let meanSemantic = rawScores.map { $0.semanticScore }.reduce(0, +) / Double(max(rawScores.count, 1))

        // Center example score only across senses that actually HAVE an example,
        // so senses without one aren't compared against a mean that includes their
        // own forced zero (which would over-reward having an example at all).
        let withExample = rawScores.filter { $0.hasExample }
        let meanExample = withExample.isEmpty ? 0.0 : withExample.map { $0.exampleScore }.reduce(0, +) / Double(withExample.count)

        var scored: [(DictionarySense, Double)] = rawScores.map { raw in
            let centeredSemantic = raw.semanticScore - meanSemantic
            // Senses without an example contribute 0 (neutral), not a penalty;
            // senses with an example are scored relative to the example-bearing mean.
            let centeredExample = raw.hasExample ? (raw.exampleScore - meanExample) : 0.0

            let finalScore = (raw.posScore * 2.0) + (raw.keywordScore * 0.8) + (centeredSemantic * 1.5) + (centeredExample * 1.5)
            #if DEBUG
            print("[RankDebug] '\(word)' '\(raw.sense.definition.prefix(40))' pos=\(raw.posScore) kw=\(raw.keywordScore) sem=\(centeredSemantic) ex=\(centeredExample) hasExample=\(raw.hasExample) final=\(finalScore)")
            #endif
            return (raw.sense, finalScore)
        }

        // Sort descending by score (higher = better)
        scored.sort { $0.1 > $1.1 }
        var sortedSenses = scored.map { $0.0 }
        sortedSenses[0].isBestMatch = true
#if DEBUG
for (sense, score) in scored {
    print("[RankDebug] '\(word)' candidate: \(sense.definition.prefix(50))... score=\(score)")
}
#endif
        return sortedSenses
    }


    private func lookupFreeDictionary(for index: Int) async {
        let word = itemsToSave[index].word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        guard let encodedWord = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/" + encodedWord) else {
            await setFallbackDefinition(for: index)
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                await setFallbackDefinition(for: index)
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let firstEntry = json.first {
                
                let phoneticText = firstEntry["phonetic"] as? String ?? ""
                var extractedPhonetic = phoneticText
                
                if extractedPhonetic.isEmpty, let phoneticsList = firstEntry["phonetics"] as? [[String: Any]] {
                    for ph in phoneticsList {
                        if let text = ph["text"] as? String, !text.isEmpty {
                            extractedPhonetic = text
                            break
                        }
                    }
                }
                
                var extractedDefinition = ""
                if let meanings = firstEntry["meanings"] as? [[String: Any]],
                   let firstMeaning = meanings.first,
                   let definitions = firstMeaning["definitions"] as? [[String: Any]],
                   let firstDef = definitions.first,
                   let defText = firstDef["definition"] as? String {
                    extractedDefinition = defText
                }
                
                // Also grab example from the free dictionary, if any
                var extractedExample: String? = nil
                if let meanings = firstEntry["meanings"] as? [[String: Any]],
                   let firstMeaning = meanings.first,
                   let definitions = firstMeaning["definitions"] as? [[String: Any]],
                   let firstDef = definitions.first,
                   let example = firstDef["example"] as? String {
                    extractedExample = example
                }
                
                await MainActor.run {
                    itemsToSave[index].pronunciation = extractedPhonetic.isEmpty ? "N/A" : extractedPhonetic
                    itemsToSave[index].definition = extractedDefinition.isEmpty ? "Definition not found." : extractedDefinition
                    itemsToSave[index].dictionaryExample = extractedExample
                }
            } else {
                await setFallbackDefinition(for: index)
            }
        } catch {
            await setFallbackDefinition(for: index)
        }
    }
    
    private func setFallbackDefinition(for index: Int) async {
        await MainActor.run {
            itemsToSave[index].definition = "Definition not found."
            itemsToSave[index].pronunciation = "N/A"
            itemsToSave[index].dictionaryExample = nil
        }
    }
    
    private func saveCards() {
        let bookToUse: Book
        if isCreatingNewBook {
            let trimmedTitle = newBookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let newBook = Book(title: trimmedTitle)
            modelContext.insert(newBook)
            bookToUse = newBook
        } else if let selectedBook = selectedBook {
            bookToUse = selectedBook
        } else { return }
        
        for item in itemsToSave {
            let card = VocabCard(
                word: item.word,
                contextSentence: item.originalSentence,
                translation: item.translatedSentence,
                pronunciation: item.pronunciation,
                definition: item.definition,
                dictionaryExample: item.dictionaryExample,
                pronunciationAudioURL: item.pronunciationAudioURL,
                wordType: item.wordType,
                registerLabel: item.registerLabel,
                origin: item.origin
            )
            card.senses = item.senses          // ← save the multi‑sense array
            modelContext.insert(card)
            card.book = bookToUse
            bookToUse.cards.append(card)
            SpeechService.preloadAudio(from: item.pronunciationAudioURL)
        }
        
        try? modelContext.save()
        // Log activity for each word saved
        for _ in itemsToSave {
            ActivityLogger.logWordAdded(context: modelContext)
        }
        dismiss()
    }
}

struct VocabItemRowView: View {
    @Binding var item: PendingVocabItem
    @State private var currentPage = 0 // Tracks which sense we are currently viewing
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. Header Row (Word + Pronunciation + Translated Status)
            HStack(alignment: .firstTextBaseline) {
                Text(item.word).font(.headline).foregroundColor(.accentColor)
                Button {
                    print("[Audio] Word speaker tapped (save sheet)")
                    SpeechService.pronounce(word: item.word, audioURL: item.pronunciationAudioURL)
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.headline)
                        .frame(width: 28, height: 28)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                
                if !item.pronunciation.isEmpty && item.pronunciation != "N/A" {
                    Text(item.pronunciation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1)).cornerRadius(4)
                }
                
                Spacer()
                
                if item.translatedSentence.isEmpty {
                    ProgressView()
                } else if item.translatedSentence != "Translation unavailable" {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                }
            }
            
            // Global Word Info (Origin)
            if let orig = item.origin {
                Text("Origin: \(orig)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // 2. MULTI-SENSE DICTIONARY UI 👈
            if !item.senses.isEmpty {
                if item.senses.indices.contains(currentPage) {
                    let sense = item.senses[currentPage]
                    
                    VStack(alignment: .leading, spacing: 8) {
                        // Best Match Badge (Only on Page 1)
                        if currentPage == 0 && sense.isBestMatch {
                            Text("✨ Best Match")
                                .font(.caption2).fontWeight(.bold)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.yellow.opacity(0.3))
                                .foregroundColor(.orange)
                                .cornerRadius(8)
                        }
                        
                        HStack {
                            if let wt = sense.wordType {
                                Text(wt).font(.caption).foregroundColor(.blue)
                            }
                            if let reg = sense.registerLabel {
                                Text(reg).font(.caption).foregroundColor(.purple)
                            }
                        }
                        
                        // Definition
                        HStack(alignment: .top) {
                            Rectangle().fill(Color.accentColor.opacity(0.4)).frame(width: 3)
                            Text(sense.definition)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true) // Prevents layout stretching
                        }
                        
                        // Example
                        if let dictExample = sense.example, !dictExample.isEmpty {
                            HStack(alignment: .top) {
                                Rectangle().fill(Color.orange.opacity(0.4)).frame(width: 3)
                                Text(dictExample)
                                    .font(.footnote)
                                    .foregroundColor(.orange)
                                    .fixedSize(horizontal: false, vertical: true) // Prevents layout stretching
                                Spacer()
                                Button {
                                    print("[Audio] Dictionary example speaker tapped")
                                    SpeechService.speak(text: dictExample)
                                } label: {
                                    Image(systemName: "speaker.wave.2")
                                        .font(.caption)
                                        .frame(width: 28, height: 28)
                                        .background(Color.gray.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.leading, 4)
                    .id(currentPage) // Forces immediate view swap to lock card height
                }
                
                // 3. NAVIGATION PILL (Only shows if there are multiple alternative senses)
                if item.senses.count > 1 {
                    HStack {
                        Spacer()
                        HStack(spacing: 16) {
                            Button(action: {
                                if currentPage > 0 { currentPage -= 1 }
                            }) {
                                Image(systemName: "chevron.left")
                                    .foregroundColor(currentPage > 0 ? .primary : .secondary.opacity(0.5))
                                    .padding(.horizontal, 8)
                                    .contentShape(Rectangle()) // Easier hit target
                            }
                            .buttonStyle(.plain) // Prevents SwiftUI row button conflicts
                            
                            Text("\(currentPage + 1) / \(item.senses.count)")
                                .font(.caption).fontWeight(.medium).monospacedDigit()
                            
                            Button(action: {
                                if currentPage < item.senses.count - 1 { currentPage += 1 }
                            }) {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(currentPage < item.senses.count - 1 ? .primary : .secondary.opacity(0.5))
                                    .padding(.horizontal, 8)
                                    .contentShape(Rectangle()) // Easier hit target
                            }
                            .buttonStyle(.plain) // Prevents SwiftUI row button conflicts
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                
            } else if !item.definition.isEmpty {
                // Fallback for single-definition legacy loading
                HStack(spacing: 8) {
                    Rectangle().fill(Color.accentColor.opacity(0.4)).frame(width: 2)
                    Text(item.definition).font(.subheadline).foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.leading, 4)
            } else {
                Text("Searching dictionary definition...").font(.caption).foregroundColor(.secondary)
            }
            
            // 4. Context Sentence & Translation
            VStack(alignment: .leading, spacing: 4) {
                Text(item.originalSentence)
                    .font(.caption).italic().foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if !item.translatedSentence.isEmpty && item.translatedSentence != "Translation unavailable" {
                    Text(item.translatedSentence).font(.caption).foregroundColor(.green)
                        .fixedSize(horizontal: false, vertical: true)
                } else if item.translatedSentence == "Translation unavailable" {
                    Text(item.translatedSentence).font(.caption).foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Multi-Sense Paging View
struct MultiSensePagingView: View {
    let card: VocabCard // Using the final VocabCard model
    @State private var currentPage = 0

    var body: some View {
        // Ensure we have senses to display
        if let senses = card.senses, !senses.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // Dynamic Height Content (No TabView)
                if senses.indices.contains(currentPage) {
                    let sense = senses[currentPage]
                    
                    VStack(alignment: .leading, spacing: 10) {
                        // PAGE 1 EXCLUSIVES
                        if currentPage == 0 {
                            if sense.isBestMatch {
                                Text("✨ Best Match")
                                    .font(.caption2).fontWeight(.bold)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.yellow.opacity(0.3))
                                    .foregroundColor(.orange)
                                    .cornerRadius(8)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                 Text(card.contextSentence).font(.callout).italic().foregroundColor(.secondary)
                                 if !card.translation.isEmpty { Text(card.translation).font(.caption).foregroundColor(.green) }
                            }
                            .padding(.bottom, 8)
                        }
                        
                        // DICTIONARY CONTENT (All Pages)
                        if let wt = sense.wordType {
                            Text(wt).font(.caption).foregroundColor(.blue)
                        }
                        
                        HStack(alignment: .top) {
                            Rectangle().fill(Color.accentColor.opacity(0.4)).frame(width: 3)
                            Text(sense.definition).font(.subheadline)
                        }
                        
                        if let ex = sense.example {
                            HStack(alignment: .top) {
                                Rectangle().fill(Color.orange.opacity(0.4)).frame(width: 3)
                                Text(ex).font(.footnote).foregroundColor(.orange)
                                Spacer()
                                Button {
                                     SpeechService.speak(text: ex)
                                } label: {
                                    Image(systemName: "speaker.wave.2").font(.caption)
                                        .frame(width: 28, height: 28)
                                        .background(Color.gray.opacity(0.1)).clipShape(Circle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .transition(.opacity) // Smooth fade when clicking arrows
                }
                
                // NAVIGATION PILL
                if senses.count > 1 {
                    HStack {
                        Spacer()
                        HStack(spacing: 16) {
                            Button(action: { if currentPage > 0 { withAnimation { currentPage -= 1 } } }) {
                                Image(systemName: "chevron.left").foregroundColor(currentPage > 0 ? .primary : .secondary.opacity(0.5))
                            }
                            
                            Text("\(currentPage + 1) / \(senses.count)")
                                .font(.caption).fontWeight(.medium).monospacedDigit()
                            
                            Button(action: { if currentPage < senses.count - 1 { withAnimation { currentPage += 1 } } }) {
                                Image(systemName: "chevron.right").foregroundColor(currentPage < senses.count - 1 ? .primary : .secondary.opacity(0.5))
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                        Spacer()
                    }
                }
            }
        } else {
            // Fallback for older cards or if senses are missing
            VStack(alignment: .leading, spacing: 4) {
                if let def = card.definition {
                    Text(def).font(.subheadline)
                }
                if let ex = card.dictionaryExample {
                    Text(ex).font(.footnote).italic().foregroundColor(.secondary)
                }
            }
        }
    }
}


struct PendingVocabItem: Identifiable {
    let id = UUID()
    let word: String
    let originalSentence: String
    var pronunciation: String = ""
    var definition: String = ""
    var dictionaryExample: String? = nil
    var pronunciationAudioURL: String? = nil
    var wordType: String? = nil
    var registerLabel: String? = nil
    var origin: String? = nil
    var translatedSentence: String = ""
    var senses: [DictionarySense] = []
}

// --------------------------------------------------
// MARK: - Word Selection View Controller
// --------------------------------------------------
class WordSelectionViewController: UIViewController, UIScrollViewDelegate {
    var image: UIImage!
    var onDismiss: (() -> Void)?
    var onProcess: (([DetectedWord]) -> Void)?
    
    private var scrollView: UIScrollView!
    private var imageView: UIImageView!
    private var overlayView: UIView!
    private var bottomBar: UIView!
    private var wordScrollView: UIScrollView!
    private var wordStackView: UIStackView!
    private var selectedWords: [DetectedWord] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupScrollView()
        setupImageView()
        setupBottomBar()
        runOCR()
    }
    
    private func updateSelectedLabel() {
        wordStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if selectedWords.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "0 words selected"
            emptyLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            emptyLabel.textColor = .placeholderText
            wordStackView.addArrangedSubview(emptyLabel)
        } else {
            for word in selectedWords {
                let tagView = UIView()
                tagView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.15)
                tagView.layer.cornerRadius = 12
                tagView.clipsToBounds = true
                
                let label = UILabel()
                label.text = word.text
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
        
        overlayView = UIView()
        overlayView.isUserInteractionEnabled = true
        imageView.addSubview(overlayView)
    }
    
    private func setupBottomBar() {
        bottomBar = UIView()
        bottomBar.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.95)
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)
        
        wordScrollView = UIScrollView()
        wordScrollView.showsHorizontalScrollIndicator = false
        wordScrollView.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(wordScrollView)
        
        wordStackView = UIStackView()
        wordStackView.axis = .horizontal
        wordStackView.spacing = 8
        wordStackView.alignment = .center
        wordStackView.translatesAutoresizingMaskIntoConstraints = false
        wordScrollView.addSubview(wordStackView)
        
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
        
        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 95),
            
            wordScrollView.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 8),
            wordScrollView.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            wordScrollView.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16),
            wordScrollView.heightAnchor.constraint(equalToConstant: 32),
            
            wordStackView.leadingAnchor.constraint(equalTo: wordScrollView.contentLayoutGuide.leadingAnchor),
            wordStackView.trailingAnchor.constraint(equalTo: wordScrollView.contentLayoutGuide.trailingAnchor),
            wordStackView.topAnchor.constraint(equalTo: wordScrollView.contentLayoutGuide.topAnchor),
            wordStackView.bottomAnchor.constraint(equalTo: wordScrollView.contentLayoutGuide.bottomAnchor),
            wordStackView.heightAnchor.constraint(equalTo: wordScrollView.heightAnchor),
            
            clearButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 20),
            clearButton.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -12),
            
            cancelButton.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -12),
            
            processButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -20),
            processButton.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -12)
        ])
        
        updateSelectedLabel()
    }
    
    private func runOCR() {
        WordDetector.recognizeWords(in: image) { [weak self] words in
            guard let self = self else { return }
            let enrichedWords = self.detectPhrases(from: words)
            DispatchQueue.main.async {
                self.drawWordBoxes(enrichedWords)
            }
        }
    }
    
    private func drawWordBoxes(_ words: [DetectedWord]) {
        overlayView.subviews.forEach { $0.removeFromSuperview() }
        let displayedRect = AVMakeRect(aspectRatio: image.size, insideRect: imageView.bounds)
        overlayView.frame = displayedRect
        
        for word in words {
            let box = word.boundingBox
            let x = box.origin.x * displayedRect.width
            let y = (1 - box.origin.y - box.height) * displayedRect.height
            let width = box.width * displayedRect.width
            let height = box.height * displayedRect.height
            
            let rect = CGRect(x: x, y: y, width: width, height: height)
            let boxView = WordBoxView(detectedWord: word, frame: rect)
            
            boxView.isPhrase = word.isPhrase
            let tap = UITapGestureRecognizer(target: self, action: #selector(wordTapped(_:)))
            boxView.addGestureRecognizer(tap)
            overlayView.addSubview(boxView)
        }
    }
    private func detectPhrases(from words: [DetectedWord]) -> [DetectedWord] {
        // Group words by their contextSentence
        var grouped: [String: [DetectedWord]] = [:]
        for word in words {
            grouped[word.contextSentence, default: []].append(word)
        }

        // Order sentences by the earliest word (top‑to‑bottom, left‑to‑right)
        var sentenceOrder: [(sentence: String, minY: CGFloat, minX: CGFloat)] = []
        for (sentence, wordList) in grouped {
            let sorted = wordList.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            let first = sorted.first!
            sentenceOrder.append((sentence, first.boundingBox.minY, first.boundingBox.minX))
        }
        sentenceOrder.sort {
            if abs($0.minY - $1.minY) > 0.005 { return $0.minY > $1.minY }
            else { return $0.minX < $1.minX }
        }

        // Common particles used in phrasal verbs (e.g. "fly out", "give up", "look after")
        let phrasalParticles: Set<String> = [
            "out", "up", "off", "in", "away", "down", "on", "over",
            "through", "back", "around", "along", "about", "into",
            "onto", "after", "across", "by", "forward", "apart"
        ]

        var finalWords: [DetectedWord] = []

        for (sentence, _, _) in sentenceOrder {
            var wordList = grouped[sentence]!
            wordList.sort { $0.boundingBox.minX < $1.boundingBox.minX }

            let tagger = NSLinguisticTagger(tagSchemes: [.lexicalClass, .nameType], options: 0)
            tagger.string = sentence

            // Ranges of phrases in terms of UTF‑16 offsets (NSRange)
            var phraseRanges: [NSRange] = []

            // 1. Named entities
            tagger.enumerateTags(in: NSRange(location: 0, length: sentence.utf16.count),
                                 scheme: .nameType,
                                 options: [.joinNames]) { tag, tokenRange, _, _ in
                if tag != nil {
                    phraseRanges.append(tokenRange)
                }
            }

            // Tokenize into words, keeping both the string and the NSRange
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = sentence
            var tokens: [(string: String, range: NSRange)] = []
            tokenizer.enumerateTokens(in: sentence.startIndex..<sentence.endIndex) { range, _ in
                let str = String(sentence[range])
                let nsRange = NSRange(range, in: sentence)
                tokens.append((str, nsRange))
                return true
            }

            func tag(forTokenAt index: Int) -> NSLinguisticTag? {
                let location = tokens[index].range.location
                return tagger.tag(at: location, scheme: .lexicalClass, tokenRange: nil, sentenceRange: nil)
            }

            // 2. Noun phrases (consecutive Nouns / Adjectives)
            var i = 0
            while i < tokens.count {
                let currentTag = tag(forTokenAt: i)
                if currentTag == .noun || currentTag == .adjective {
                    let start = i
                    i += 1
                    while i < tokens.count {
                        let nextTag = tag(forTokenAt: i)
                        if nextTag == .noun || nextTag == .adjective {
                            i += 1
                        } else {
                            break
                        }
                    }
                    if i - start > 1 {
                        let startLocation = tokens[start].range.location
                        let endLocation = tokens[i - 1].range.location + tokens[i - 1].range.length
                        let phraseRange = NSRange(location: startLocation, length: endLocation - startLocation)
                        phraseRanges.append(phraseRange)
                    }
                } else {
                    i += 1
                }
            }

            // 3. Phrasal verbs (Verb immediately followed by a known particle)
            var j = 0
            while j < tokens.count {
                let currentTag = tag(forTokenAt: j)
                if currentTag == .verb, j + 1 < tokens.count {
                    let nextWordLower = tokens[j + 1].string.lowercased()
                    if phrasalParticles.contains(nextWordLower) {
                        let startLocation = tokens[j].range.location
                        let endLocation = tokens[j + 1].range.location + tokens[j + 1].range.length
                        let phraseRange = NSRange(location: startLocation, length: endLocation - startLocation)
                        phraseRanges.append(phraseRange)
                        j += 2
                        continue
                    }
                }
                j += 1
            }

            // 4. Merge words that are covered by phrase ranges
            var mergedWords: [DetectedWord] = []
            var coveredIndices = Set<Int>()

            for phraseRange in phraseRanges {
                guard let phraseTextRange = Range(phraseRange, in: sentence) else { continue }
                let phraseText = String(sentence[phraseTextRange])
                let phraseWords = phraseText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

                guard phraseWords.count <= wordList.count, phraseWords.count > 0 else { continue }
                for startIdx in 0...(wordList.count - phraseWords.count) {
                    let slice = wordList[startIdx..<startIdx + phraseWords.count].map { $0.text }
                    if slice == phraseWords {
                        for idx in startIdx..<startIdx + phraseWords.count {
                            coveredIndices.insert(idx)
                        }
                        let mergedBox = wordList[startIdx].boundingBox.union(
                            wordList[startIdx + phraseWords.count - 1].boundingBox)

                        let phraseWord = DetectedWord(
                            text: phraseText,
                            boundingBox: mergedBox,
                            contextSentence: sentence,
                            isPhrase: true,
                            phraseComponents: phraseWords
                        )
                        mergedWords.append(phraseWord)
                        break
                    }
                }
            }

            // Add words not covered by any phrase
            for (idx, word) in wordList.enumerated() {
                if !coveredIndices.contains(idx) {
                    mergedWords.append(word)
                }
            }

            // Keep left‑to‑right order within the sentence
            mergedWords.sort { $0.boundingBox.minX < $1.boundingBox.minX }
            finalWords.append(contentsOf: mergedWords)
        }

        return finalWords
    }

    
    @objc private func wordTapped(_ gesture: UITapGestureRecognizer) {
        guard let boxView = gesture.view as? WordBoxView else { return }
        let word = boxView.detectedWord

        boxView.isSelectedWord.toggle()
        if boxView.isSelectedWord {
            selectedWords.append(word)
        } else {
            selectedWords.removeAll { $0.id == word.id }
        }
        updateSelectedLabel()
    }
    
    @objc private func clearSelection() {
        selectedWords.removeAll()
        updateSelectedLabel()
        for case let boxView as WordBoxView in overlayView.subviews {
            boxView.isSelectedWord = false
        }
    }
    
    @objc private func processWords() { onProcess?(selectedWords) }
    @objc private func cancelTapped() { onDismiss?() }
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { return imageView }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
        imageView.frame.origin = CGPoint(x: offsetX, y: offsetY)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if scrollView.zoomScale == 1.0 {
            scrollView.frame = view.bounds
            imageView.frame = scrollView.bounds
            scrollView.contentSize = imageView.bounds.size
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
    let contextSentence: String
    var isPhrase: Bool = false
    var phraseComponents: [String]? = nil
}

final class WordDetector {
    static func recognizeWords(in image: UIImage, completion: @escaping ([DetectedWord]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                completion([])
                return
            }

            // 1. Build lines with text and bounding boxes
            var lines: [(text: String, box: CGRect)] = []
            for obs in observations {
                guard let candidate = obs.topCandidates(1).first else { continue }
                let line = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty {
                    lines.append((text: line, box: obs.boundingBox))
                }
            }

            // 2. Sort lines top-to-bottom, left-to-right
            lines.sort {
                if abs($0.box.minY - $1.box.minY) > 0.005 { return $0.box.minY > $1.box.minY }
                else { return $0.box.minX < $1.box.minX }
            }

            // 3. Build full text and tokenize into sentences
            // Insert paragraph breaks between lines with a large vertical gap,
            // so unrelated text blocks (e.g. toolbar UI vs. body paragraph)
            // don't get merged into a single "sentence" by the tokenizer.
            var fullTextBuilder = ""
            for (i, line) in lines.enumerated() {
                if i > 0 {
                    let prevY = lines[i - 1].box.minY
                    let gap = abs(prevY - line.box.minY)
                    fullTextBuilder += gap > 0.03 ? "\n\n" : " "
                }
                fullTextBuilder += line.text
            }
            let fullText = fullTextBuilder
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = fullText
            var sentenceRanges: [Range<String.Index>] = []
            tokenizer.enumerateTokens(in: fullText.startIndex..<fullText.endIndex) { range, _ in
                sentenceRanges.append(range)
                return true
            }
            let sentences = sentenceRanges.map { String(fullText[$0]) }

            // 4. Map each line to a sentence by character-position overlap
            // First, recompute the character range each line occupies in fullText
            var lineRanges: [Range<String.Index>] = []
            var cursor = fullText.startIndex
            for line in lines {
                guard let lineRange = fullText.range(of: line.text, range: cursor..<fullText.endIndex) else {
                    lineRanges.append(cursor..<cursor)
                    continue
                }
                lineRanges.append(lineRange)
                cursor = lineRange.upperBound
            }

            var lineSentenceMap = [Int](repeating: 0, count: lines.count)
            for (i, lineRange) in lineRanges.enumerated() {
                var bestIdx = 0
                var bestOverlap = 0
                for (idx, sentRange) in sentenceRanges.enumerated() {
                    let overlapStart = max(lineRange.lowerBound, sentRange.lowerBound)
                    let overlapEnd = min(lineRange.upperBound, sentRange.upperBound)
                    if overlapStart < overlapEnd {
                        let overlapLength = fullText.distance(from: overlapStart, to: overlapEnd)
                        if overlapLength > bestOverlap {
                            bestOverlap = overlapLength
                            bestIdx = idx
                        }
                    }
                }
                lineSentenceMap[i] = bestIdx
            }

            // 5. Split lines into words, assign correct sentence
            var results: [DetectedWord] = []
            for (lineIdx, line) in lines.enumerated() {
                let wordsInLine = line.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                let totalChars = wordsInLine.reduce(0) { $0 + $1.count }
                var currentX: CGFloat = 0
                for word in wordsInLine {
                    let proportion = CGFloat(word.count) / CGFloat(totalChars)
                    let wordWidth = line.box.width * proportion
                    let wordHeight = line.box.height
                    let wordX = line.box.origin.x + currentX
                    let wordY = line.box.origin.y
                    let wordBox = CGRect(x: wordX, y: wordY, width: wordWidth, height: wordHeight)

                    let sentenceIndex = lineSentenceMap[lineIdx]
                    let contextSentence = sentences.indices.contains(sentenceIndex) ? sentences[sentenceIndex] : line.text

                    results.append(DetectedWord(text: word, boundingBox: wordBox, contextSentence: contextSentence,
                                                isPhrase: false, phraseComponents: nil))
                    currentX += wordWidth
                }
            }

            // Sort final results top-to-bottom, left-to-right
            results.sort { w1, w2 in
                let y1 = w1.boundingBox.origin.y + w1.boundingBox.height
                let y2 = w2.boundingBox.origin.y + w2.boundingBox.height
                if abs(y1 - y2) > 0.01 { return y1 > y2 }
                return w1.boundingBox.origin.x < w2.boundingBox.origin.x
            }

            completion(results)
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
