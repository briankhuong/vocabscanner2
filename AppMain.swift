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
import UIKit
import UniformTypeIdentifiers

// Required for camera rotation — UIViewController-level overrides are
// ignored when presented via SwiftUI fullScreenCover because the hosting
// controller controls orientation at the app delegate level.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return .all
    }
}
// Cancels the inner task and throws if it doesn't complete within `seconds`.
func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw CancellationError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
// --------------------------------------------------
// MARK: - App Entry
// --------------------------------------------------
@main
struct VocabScannerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate  // ← add this
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Book.self, VocabCard.self, ActivityLog.self])
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

    // Same mapping PreviewView uses for its preview layer connection, so the
    // photo output connection can be kept in sync with the actual interface
    // orientation at the moment of capture.
    private static func videoRotationAngle(for orientation: UIInterfaceOrientation) -> CGFloat {
        switch orientation {
        case .landscapeLeft:           return 180
        case .landscapeRight:          return 0
        case .portraitUpsideDown:      return 270
        default:                       return 90  // portrait
        }
    }
    
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
            // The photo output has its own AVCaptureConnection, separate from the
            // preview layer's. Only the preview layer's connection was being kept
            // in sync with device rotation (in PreviewView.layoutSubviews), so the
            // captured photo's orientation metadata was always based on whatever
            // angle the output connection happened to default to — not the actual
            // orientation at the moment of capture. Sync it here, on the main
            // thread, right before firing the capture.
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let connection = self.output.connection(with: .video) {
                    let orientation = UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .first?.effectiveGeometry.interfaceOrientation ?? .portrait
                    let angle = Self.videoRotationAngle(for: orientation)
                    if connection.isVideoRotationAngleSupported(angle) {
                        connection.videoRotationAngle = angle
                    }
                }
                let settings = AVCapturePhotoSettings()
                self.output.capturePhoto(with: settings, delegate: self)
            }
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
        // Trigger layoutSubviews so orientation updates on every SwiftUI pass
        uiView.setNeedsLayout()
    }
}

final class PreviewView: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(previewLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        // Update video orientation to match current interface orientation
        // so the preview fills the screen correctly in landscape.
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(0) {
            let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
            let angle: CGFloat
            switch orientation {
            case .landscapeLeft:           angle = 180
            case .landscapeRight:          angle = 0
            case .portraitUpsideDown:      angle = 270
            default:                       angle = 90  // portrait
            }
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
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

    var isSelectedWord: Bool = false { didSet { updateAppearance() } }
    var isPhrase: Bool = false      { didSet { updateAppearance() } }
    var mergeOrder: Int?            { didSet { updateAppearance() } }

    // All sublayers created once — never added or removed after init.
    // This prevents the EXC_BAD_ACCESS from add/remove racing with didSet.
    private let tintLayer      = CALayer()
    private let badgeLayer     = CALayer()
    private let badgeTextLayer = CATextLayer()

    init(detectedWord: DetectedWord, frame: CGRect) {
        self.detectedWord = detectedWord
        super.init(frame: frame)
        layer.cornerRadius = 3
        layer.masksToBounds = true

        layer.addSublayer(tintLayer)

        badgeLayer.cornerRadius = 7
        badgeLayer.isHidden = true
        layer.addSublayer(badgeLayer)

        badgeTextLayer.fontSize = 8
        badgeTextLayer.alignmentMode = .center
        badgeTextLayer.foregroundColor = UIColor.white.cgColor
        badgeTextLayer.isHidden = true
        layer.addSublayer(badgeTextLayer)

        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Update layer frames whenever the view resizes (rotation, zoom, etc.)
        tintLayer.frame = bounds

        let badgeSize: CGFloat = 14
        badgeLayer.frame = CGRect(x: -4, y: -4, width: badgeSize, height: badgeSize)
        badgeLayer.cornerRadius = badgeSize / 2

        let textHeight: CGFloat = 9
        badgeTextLayer.frame = CGRect(
            x: badgeLayer.frame.minX,
            y: badgeLayer.frame.minY + (badgeSize - textHeight) / 2,
            width: badgeSize,
            height: textHeight
        )
        badgeTextLayer.contentsScale = window?.screen.scale ?? 2.0
    }

    private func updateAppearance() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)

            // Always sync frame here — guarantees visibility even when called
            // before layoutSubviews runs (e.g. from mergeOrder's didSet firing
            // right after init, before the view has been laid out).
            tintLayer.frame = bounds

            if mergeOrder != nil {
                // Merge mode: same fill-only style as single selection — no
                // badge, since the order is already visible in the merge
                // preview strip next to the Merge Words button.
                tintLayer.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.4).cgColor
                badgeLayer.isHidden = true
                badgeTextLayer.isHidden = true
            } else if isSelectedWord {
                // Selected: teal for phrases, yellow for single words
                let color = isPhrase ? UIColor.systemTeal : UIColor.systemYellow
                tintLayer.backgroundColor = color.withAlphaComponent(0.55).cgColor
                badgeLayer.isHidden = true
                badgeTextLayer.isHidden = true
            } else {
                // Unselected: bright white pill — locally reverses the image dim
                // under this word, making it look like it has its original white
                // paper background while everything around it stays slightly dark.
                // This is exactly what iOS Live Text does.
                tintLayer.backgroundColor = UIColor.white.withAlphaComponent(0.4).cgColor
                badgeLayer.isHidden = true
                badgeTextLayer.isHidden = true
            }

            CATransaction.commit()
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
        // Fire all word lookups concurrently — each word updates its own row
        // as soon as its result arrives, rather than waiting for all to finish.
        await withTaskGroup(of: Void.self) { group in
            for i in itemsToSave.indices {
                group.addTask {
                    await self.lookupSingleWord(at: i)
                }
            }
        }
    }

    private func lookupSingleWord(at i: Int) async {
        let word = itemsToSave[i].word.trimmingCharacters(in: .punctuationCharacters)

        // Multi-word phrases → Llama directly
        if word.contains(" ") {
            await lookupPhraseWithLlama(for: i)
            return
        }

        // ── Merriam-Webster (8s timeout) ──────────────────────────────────────
        do {
            let mwResult = try await withTimeout(seconds: 8) {
                try await MerriamWebster.lookup(word: word)
            }

            if let mwResult, !mwResult.senses.isEmpty {
                var senses = mwResult.senses
                for j in senses.indices { senses[j].isBestMatch = false }

                // Take an immutable snapshot before crossing the async boundary —
                // Swift 6 forbids capturing a var across concurrent closures.
                let sensesSnapshot = senses

                // ── Llama WSD (6s timeout) ────────────────────────────────────
                let wsdResult = await (try? withTimeout(seconds: 6) {
                    await LLMWSD.selectBestSense(
                        word: word,
                        sentence: self.itemsToSave[i].originalSentence,
                        senses: sensesSnapshot
                    )
                }) ?? nil

                if let wsdResult {
                    var best = senses.remove(at: wsdResult.bestIndex)
                    best.isBestMatch = wsdResult.confidence >= 0.75
                    senses.insert(best, at: 0)
                } else {
                    print("[LLMWSD] Timed out or unavailable, using local ranking")
                    senses = rankSenses(
                        senses,
                        contextSentence: itemsToSave[i].originalSentence,
                        word: word,
                        mode: dictionaryMode
                    )
                }

                await MainActor.run {
                    itemsToSave[i].senses = senses
                    if let best = senses.first {
                        itemsToSave[i].definition            = best.definition
                        itemsToSave[i].dictionaryExample     = best.example
                        itemsToSave[i].wordType              = best.wordType
                        itemsToSave[i].registerLabel         = best.registerLabel
                        itemsToSave[i].pronunciationAudioURL = best.pronunciationAudioURL
                    }
                    itemsToSave[i].pronunciation = mwResult.pronunciation ?? "N/A"
                    itemsToSave[i].origin        = mwResult.origin
                }
                return
            }
        } catch {
            print("[MW] Error or timeout for '\(word)': \(error)")
        }

        // ── Free dictionary fallback (6s timeout) ─────────────────────────────
                do {
                    try await withTimeout(seconds: 6) {
                        await self.lookupFreeDictionary(for: i)
                    }
                } catch {
                    print("[FreeDictionary] Timeout for '\(word)', falling back to Llama")
                    await lookupWordWithLlama(for: i)
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

        let rawScores: [RawScore] = senses.map { sense in
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
    /// Last-resort fallback when both Merriam-Webster and the free dictionary
        /// API fail to return a definition. Mirrors lookupPhraseWithLlama's
        /// request shape, but asks for a plain word definition instead of an
        /// idiom/proper-noun explanation.
        private func lookupWordWithLlama(for index: Int) async {
            let word     = itemsToSave[index].word.trimmingCharacters(in: .punctuationCharacters)
            let sentence = itemsToSave[index].originalSentence

            guard
                let url     = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
                let dict    = NSDictionary(contentsOf: url) as? [String: Any],
                let apiKey  = dict["LLM_API_KEY"]  as? String,
                let baseURL = dict["LLM_BASE_URL"] as? String,
                let model   = dict["LLM_MODEL"]    as? String,
                let endpoint = URL(string: baseURL)
            else {
                await setFallbackDefinition(for: index)
                return
            }

            let prompt = """
                    The dictionary lookup for the English word "\(word)" failed (not
                    found, misspelled, informal, or too rare for a standard
                    dictionary). It appears in this sentence: "\(sentence)"

                    Provide a learner-friendly definition based on how it's used in
                    that sentence.

                    Reply ONLY with this JSON, no explanation:
                    {
                      "valid": true,
                      "definition": "<clear definition in 1 sentence, matching this context>",
                      "example": "<a natural example sentence using it>",
                      "wordType": "<noun | verb | adjective | adverb | etc.>",
                      "pronunciation": "<IPA or approximate pronunciation, or empty string if unknown>"
                    }
                    If "\(word)" is not a real word at all (e.g. OCR garbage), reply:
                    {"valid": false}
                    """

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json",  forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 12

            let body: [String: Any] = [
                "model": model,
                "max_tokens": 220,
                "temperature": 0,
                "messages": [["role": "user", "content": prompt]]
            ]

            guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
                await setFallbackDefinition(for: index)
                return
            }
            request.httpBody = httpBody

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    await setFallbackDefinition(for: index)
                    return
                }

                guard
                    let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let choices = json["choices"] as? [[String: Any]],
                    let message = choices.first?["message"] as? [String: Any],
                    let text    = message["content"] as? String
                else {
                    await setFallbackDefinition(for: index)
                    return
                }

                let cleaned = text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard
                    let resultData = cleaned.data(using: .utf8),
                    let result     = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any],
                    result["valid"] as? Bool == true
                else {
                    await setFallbackDefinition(for: index)
                    return
                }

                let definition    = result["definition"]    as? String ?? ""
                let example       = result["example"]       as? String ?? ""
                let wordType      = result["wordType"]      as? String
                let pronunciation = result["pronunciation"]  as? String

                guard !definition.isEmpty else {
                    await setFallbackDefinition(for: index)
                    return
                }

                let sense = DictionarySense(
                    definition: definition,
                    example: example.isEmpty ? nil : example,
                    wordType: wordType,
                    registerLabel: nil,
                    pronunciationAudioURL: nil,
                    isBestMatch: true
                )

                await MainActor.run {
                    itemsToSave[index].senses            = [sense]
                    itemsToSave[index].definition         = definition
                    itemsToSave[index].dictionaryExample  = example.isEmpty ? nil : example
                    itemsToSave[index].wordType           = wordType
                    itemsToSave[index].pronunciation      = (pronunciation?.isEmpty == false) ? pronunciation! : "N/A"
                    print("[LlamaWordFallback] '\(word)': \(definition.prefix(60))")
                }
            } catch {
                print("[LlamaWordFallback] error: \(error)")
                await setFallbackDefinition(for: index)
            }
        }
    private func lookupPhraseWithLlama(for index: Int) async {
        let phrase   = itemsToSave[index].word
        let sentence = itemsToSave[index].originalSentence

        guard
            let url     = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let dict    = NSDictionary(contentsOf: url) as? [String: Any],
            let apiKey  = dict["LLM_API_KEY"]  as? String,
            let baseURL = dict["LLM_BASE_URL"] as? String,
            let model   = dict["LLM_MODEL"]    as? String,
            let endpoint = URL(string: baseURL)
        else { return }

        let prompt = """
                The user is reading an English book and found this phrase: "\(phrase)"
                It appears in this sentence: "\(sentence)"

                Figure out what kind of expression this is and explain it for a
                vocabulary learner:
                - If it's an idiom, phrasal verb, or other fixed expression, explain
                  what it means.
                - If it's a proper noun referring to something well-known — a person,
                  place, event, organization, brand, title, etc. (e.g. "Boston
                  Marathon", "Wall Street") — explain what it refers to.
                - Otherwise, if it's neither a recognizable expression nor a
                  well-known proper noun, reply: {"valid": false}

                If valid, reply with this JSON:
                {
                  "valid": true,
                  "definition": "<clear explanation in 1-2 sentences>",
                  "example": "<a natural example sentence using it>",
                  "wordType": "<idiom | phrasal verb | expression | proper noun>"
                }
                Reply ONLY with the JSON. No explanation.
                """

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12

        let body: [String: Any] = [
                    "model": model,
                    "max_tokens": 260,
                    "temperature": 0,
                    "messages": [["role": "user", "content": prompt]]
                ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }

            guard
                let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = json["choices"] as? [[String: Any]],
                let message = choices.first?["message"] as? [String: Any],
                let text    = message["content"] as? String
            else { return }

            let cleaned = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard
                let resultData = cleaned.data(using: .utf8),
                let result     = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any]
            else { return }

            guard result["valid"] as? Bool == true else {
                await MainActor.run {
                    itemsToSave[index].definition = "⚠️ Not a recognized phrase. Try selecting individual words."
                    itemsToSave[index].pronunciation = ""
                }
                return
            }

            let definition = result["definition"] as? String ?? ""
            let example    = result["example"]    as? String ?? ""
            let wordType   = result["wordType"]   as? String

            let sense = DictionarySense(
                definition: definition,
                example: example.isEmpty ? nil : example,
                wordType: wordType,
                registerLabel: nil,
                pronunciationAudioURL: nil,
                isBestMatch: true
            )

            await MainActor.run {
                itemsToSave[index].senses             = [sense]
                itemsToSave[index].definition         = definition
                itemsToSave[index].dictionaryExample  = example.isEmpty ? nil : example
                itemsToSave[index].wordType           = wordType
                itemsToSave[index].pronunciation      = ""
                print("[Phrase] '\(phrase)': \(definition.prefix(60))")
            }
        } catch {
            print("[Phrase] Llama error: \(error)")
        }
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
                
                if extractedDefinition.isEmpty {
                                    // Free dictionary returned an entry but no usable definition —
                                    // fall through to Llama instead of showing "Definition not found."
                                    await lookupWordWithLlama(for: index)
                                } else {
                                    await MainActor.run {
                                        itemsToSave[index].pronunciation = extractedPhonetic.isEmpty ? "N/A" : extractedPhonetic
                                        itemsToSave[index].definition = extractedDefinition
                                        itemsToSave[index].dictionaryExample = extractedExample
                                    }
                                }
                            } else {
                                await lookupWordWithLlama(for: index)
                            }
                        } catch {
                            await lookupWordWithLlama(for: index)
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
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Looking up definition…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
    private var imageDimOverlay: UIView!
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
        private var allDetectedWords: [DetectedWord] = []

        // Merge Mode (Option A): tapping words while active adds them to a
        // pending phrase (with an order badge) instead of selecting them for
        // saving. Confirming combines exactly those words, in tap order.
    private var isMergeModeActive = false
            private var pendingMergeSelections: [(word: DetectedWord, box: WordBoxView)] = []
            private var mergeModeButton: UIButton!
            private var combineButton: UIButton!
            private var mergePreviewLabel: UILabel!
            // Tracks the last displayed image rect so viewDidLayoutSubviews only
            // rebuilds word boxes on genuine geometry changes (rotation/resize),
            // not on every layout pass triggered by unrelated UI (e.g. the
            // Combine button's title changing size).
            private var lastDisplayedRect: CGRect = .zero
    
    override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            setupScrollView()
            setupImageView()
            setupBottomBar()
            runOCR()
            setupHintLabel()
            setupMergeControls()
        }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all   // allow portrait + both landscapes
    }

    override var shouldAutorotate: Bool {
        return true
    }
    private func setupHintLabel() {
            let hint = UILabel()
            hint.text = "Tap to select · Use Merge Words to combine · Long-press phrase to split"
        hint.font = .systemFont(ofSize: 11, weight: .medium)
        hint.textColor = .white
        hint.textAlignment = .center
        hint.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        hint.layer.cornerRadius = 8
        hint.clipsToBounds = true
        hint.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(hint)

                NSLayoutConstraint.activate([
                    hint.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
                    hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                    hint.heightAnchor.constraint(equalToConstant: 28),
                    hint.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32)
                ])
            }

            /// Rebuilds the live "word + word + word" preview strip shown while
            /// picking words in Merge Mode, so the user can visually confirm the
            /// phrase being built without losing track of small on-image badges.
            private func updateMergePreview() {
                guard !pendingMergeSelections.isEmpty else {
                    mergePreviewLabel.isHidden = true
                    return
                }
                let text = pendingMergeSelections.map { $0.word.text }.joined(separator: "  +  ")
                mergePreviewLabel.text = "  \(text)  "
                mergePreviewLabel.isHidden = false
            }

            private func setupMergeControls() {
                mergeModeButton = UIButton(type: .system)
                        var mergeModeConfig = UIButton.Configuration.plain()
                        mergeModeConfig.title = "Merge Words"
                        mergeModeConfig.baseForegroundColor = .white
                        mergeModeConfig.background.backgroundColor = UIColor.black.withAlphaComponent(0.45)
                        mergeModeConfig.background.cornerRadius = 8
                        mergeModeConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
                        mergeModeButton.configuration = mergeModeConfig
                        mergeModeButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
                        mergeModeButton.translatesAutoresizingMaskIntoConstraints = false
                        mergeModeButton.addTarget(self, action: #selector(toggleMergeMode), for: .touchUpInside)
                        view.addSubview(mergeModeButton)

                        combineButton = UIButton(type: .system)
                        var combineConfig = UIButton.Configuration.plain()
                        combineConfig.title = "Combine (0)"
                        combineConfig.baseForegroundColor = .white
                        combineConfig.background.backgroundColor = UIColor.systemBlue
                        combineConfig.background.cornerRadius = 8
                        combineConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
                        combineButton.configuration = combineConfig
                        combineButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
                        combineButton.translatesAutoresizingMaskIntoConstraints = false
                        combineButton.addTarget(self, action: #selector(confirmMerge), for: .touchUpInside)
                        combineButton.isHidden = true
                        view.addSubview(combineButton)

                mergePreviewLabel = UILabel()
                                mergePreviewLabel.font = .systemFont(ofSize: 14, weight: .semibold)
                                mergePreviewLabel.textColor = .white
                                mergePreviewLabel.textAlignment = .center
                                mergePreviewLabel.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.85)
                                mergePreviewLabel.layer.cornerRadius = 10
                                mergePreviewLabel.clipsToBounds = true
                                mergePreviewLabel.numberOfLines = 1
                                mergePreviewLabel.adjustsFontSizeToFitWidth = true
                                mergePreviewLabel.minimumScaleFactor = 0.6
                                mergePreviewLabel.isHidden = true
                                mergePreviewLabel.translatesAutoresizingMaskIntoConstraints = false
                                view.addSubview(mergePreviewLabel)

                                NSLayoutConstraint.activate([
                                    mergeModeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 48),
                                    mergeModeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                                    mergeModeButton.heightAnchor.constraint(equalToConstant: 32),

                                    combineButton.centerYAnchor.constraint(equalTo: mergeModeButton.centerYAnchor),
                                    combineButton.trailingAnchor.constraint(equalTo: mergeModeButton.leadingAnchor, constant: -8),
                                    combineButton.heightAnchor.constraint(equalToConstant: 32),

                                    mergePreviewLabel.topAnchor.constraint(equalTo: mergeModeButton.bottomAnchor, constant: 8),
                                    mergePreviewLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                                    mergePreviewLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
                                    mergePreviewLabel.heightAnchor.constraint(equalToConstant: 30)
                                ])
                            }
    @objc private func toggleMergeMode() {
            if isMergeModeActive {
                // Button doubles as Cancel while merge mode is active.
                resetMergeMode()
            } else {
                isMergeModeActive = true
                mergeModeButton.configuration?.title = "Cancel Merge"
                mergeModeButton.configuration?.background.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
                combineButton.isHidden = false
                updateMergePreview()
            }
        }
    private func resetMergeMode() {
            isMergeModeActive = false
            mergeModeButton.configuration?.title = "Merge Words"
            mergeModeButton.configuration?.background.backgroundColor = UIColor.black.withAlphaComponent(0.45)
            combineButton.isHidden = true
            combineButton.configuration?.title = "Combine (0)"
            for entry in pendingMergeSelections {
                entry.box.mergeOrder = nil
            }
            pendingMergeSelections.removeAll()
            mergePreviewLabel.isHidden = true
        }

            private func handleMergeModeTap(on boxView: WordBoxView) {
                // Tapping an already-picked word removes it and renumbers the rest,
                // so the badges always read as a clean, contiguous sequence.
                if let idx = pendingMergeSelections.firstIndex(where: { $0.box === boxView }) {
                            pendingMergeSelections.remove(at: idx)
                            boxView.mergeOrder = nil
                            for (i, entry) in pendingMergeSelections.enumerated() {
                                entry.box.mergeOrder = i + 1
                            }
                            combineButton.configuration?.title = "Combine (\(pendingMergeSelections.count))"
                            updateMergePreview()
                            return
                        }

                // Keep merges within a single sentence — avoids accidentally
                // stitching together words that were never actually adjacent.
                if let firstSentence = pendingMergeSelections.first?.word.contextSentence,
                   boxView.detectedWord.contextSentence != firstSentence {
                    let alert = UIAlertController(
                        title: "Different sentence",
                        message: "You can only combine words from the same sentence.",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    present(alert, animated: true)
                    return
                }

                pendingMergeSelections.append((boxView.detectedWord, boxView))
                        boxView.mergeOrder = pendingMergeSelections.count
                        combineButton.configuration?.title = "Combine (\(pendingMergeSelections.count))"
                        updateMergePreview()
                    }

            @objc private func confirmMerge() {
                guard pendingMergeSelections.count >= 2 else {
                    let alert = UIAlertController(
                        title: "Pick at least 2 words",
                        message: "Tap 2 or more words to combine into a phrase.",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    present(alert, animated: true)
                    return
                }

                // Combine in the order the user tapped them — this is the phrase
                // order they intended, which may not always match left-to-right.
                let orderedBoxes = pendingMergeSelections.map { $0.box }
                mergeBoxes(orderedBoxes)
                resetMergeMode()
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

            // Z-order (back to front): photo → dim overlay → word tap targets.
            // The dim MUST be added before overlayView, not after — addSubview
            // stacks later calls on top, so adding it after word boxes would
            // wash out every highlight (this was muting merge-mode's blue tint
            // almost to invisibility, since white selection is bright enough to
            // fight through the dim but the blue tint isn't).
            imageDimOverlay = UIView()
            imageDimOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.15)
            imageDimOverlay.isUserInteractionEnabled = false
            imageView.addSubview(imageDimOverlay)

            overlayView = UIView()
            overlayView.isUserInteractionEnabled = true
            imageView.addSubview(overlayView)
            // Swipe-to-merge has been replaced by tap-based Merge Mode (see
            // toggleMergeMode/handleMergeModeTap) — it was unreliable because
            // OCR box edges don't always line up precisely with the visible
            // text, especially on tilted photos.
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
                let orderedWords = self.orderWords(from: words)
                DispatchQueue.main.async {
                    self.allDetectedWords = orderedWords  // ← store for merge/split
                    self.drawWordBoxes(orderedWords)
                }
            }
        }
    
    private func drawWordBoxes(_ words: [DetectedWord]) {
        overlayView.subviews.forEach { $0.removeFromSuperview() }
        let displayedRect = AVMakeRect(aspectRatio: image.size, insideRect: imageView.bounds)
        overlayView.frame = displayedRect
        imageDimOverlay.frame = displayedRect
        
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

            // Long-press on any phrase box to split it
            if word.isPhrase {
                let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleSplit(_:)))
                boxView.addGestureRecognizer(longPress)
            }

            overlayView.addSubview(boxView)
        }
    }
    
    /// Auto phrase-detection has been removed — phrases are now created
        /// exclusively by the user via swipe-to-merge. This just orders the
        /// raw OCR words in natural reading order (top-to-bottom by sentence
        /// group, then left-to-right within each group) with no merging.
        private func orderWords(from words: [DetectedWord]) -> [DetectedWord] {
            var grouped: [String: [DetectedWord]] = [:]
            for word in words {
                grouped[word.contextSentence, default: []].append(word)
            }

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

            var finalWords: [DetectedWord] = []
            for (sentence, _, _) in sentenceOrder {
                let wordList = grouped[sentence]!.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                finalWords.append(contentsOf: wordList)
            }
            return finalWords
        }

    // MARK: - Merge (swipe) and Split (long-press)

    private func boundingBoxFrame(for box: CGRect) -> CGRect {
        let displayedRect = AVMakeRect(aspectRatio: image.size, insideRect: imageView.bounds)
        return CGRect(
            x: box.origin.x * displayedRect.width,
            y: (1 - box.origin.y - box.height) * displayedRect.height,
            width: box.width  * displayedRect.width,
            height: box.height * displayedRect.height
        )
    }


    private func mergeBoxes(_ boxes: [WordBoxView]) {
            let words = boxes.map { $0.detectedWord }
            let mergedText = words.map { $0.text }.joined(separator: " ")
            let mergedBBox = words.map { $0.boundingBox }.reduce(words[0].boundingBox) { $0.union($1) }
            let sentence   = words[0].contextSentence

            // If any of the words being merged were already individually
            // selected, drop them from selectedWords — they're being replaced
            // by the merged phrase below, so we don't want stale duplicates.
            let mergedIds = Set(words.map { $0.id })
            selectedWords.removeAll { mergedIds.contains($0.id) }

            let mergedWord = DetectedWord(
                text: mergedText,
                boundingBox: mergedBBox,
                contextSentence: sentence,
                isPhrase: true,
                phraseComponents: words.map { $0.text }
            )

            boxes.forEach { $0.removeFromSuperview() }

            let frame = boundingBoxFrame(for: mergedBBox)
            let newBox = WordBoxView(detectedWord: mergedWord, frame: frame)
            newBox.isPhrase = true

            let tap = UITapGestureRecognizer(target: self, action: #selector(wordTapped(_:)))
            newBox.addGestureRecognizer(tap)
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleSplit(_:)))
            newBox.addGestureRecognizer(longPress)

            overlayView.addSubview(newBox)

            // Combining is itself a selection gesture — mark the new phrase
            // as selected immediately (shows the underline) and add it to the
            // save list, rather than leaving it unselected.
            newBox.isSelectedWord = true
            selectedWords.append(mergedWord)
            updateSelectedLabel()
        }

    @objc private func handleSplit(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let box = gesture.view as? WordBoxView,
              box.detectedWord.isPhrase,
              let components = box.detectedWord.phraseComponents else { return }

        let alert = UIAlertController(
            title: "Split phrase?",
            message: "\"\(box.detectedWord.text)\" → \(components.joined(separator: " + "))",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Split", style: .destructive) { _ in
            self.splitBox(box)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func splitBox(_ phraseBox: WordBoxView) {
        guard let components = phraseBox.detectedWord.phraseComponents else { return }
        let sentence   = phraseBox.detectedWord.contextSentence
        let totalWidth = phraseBox.frame.width
        let charCount  = components.map { $0.count }.reduce(0, +)
        let displayedRect = AVMakeRect(aspectRatio: image.size, insideRect: imageView.bounds)

        phraseBox.removeFromSuperview()
        var currentX = phraseBox.frame.minX

        for component in components {
            let proportion = CGFloat(component.count) / CGFloat(max(charCount, 1))
            let wordWidth  = totalWidth * proportion
            let wordFrame  = CGRect(
                x: currentX, y: phraseBox.frame.minY,
                width: wordWidth, height: phraseBox.frame.height
            )
            let normBox = CGRect(
                x: wordFrame.minX / displayedRect.width,
                y: 1 - (wordFrame.minY / displayedRect.height) - (wordFrame.height / displayedRect.height),
                width: wordFrame.width  / displayedRect.width,
                height: wordFrame.height / displayedRect.height
            )
            let word = DetectedWord(
                text: component, boundingBox: normBox,
                contextSentence: sentence, isPhrase: false
            )
            let newBox = WordBoxView(detectedWord: word, frame: wordFrame)
            let tap = UITapGestureRecognizer(target: self, action: #selector(wordTapped(_:)))
            newBox.addGestureRecognizer(tap)
            overlayView.addSubview(newBox)
            currentX += wordWidth
        }
    }

    @objc private func wordTapped(_ gesture: UITapGestureRecognizer) {
            guard let boxView = gesture.view as? WordBoxView else { return }

            if isMergeModeActive {
                handleMergeModeTap(on: boxView)
                return
            }

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
            // Runs after every rotation — recompute scroll/image/overlay frames
            // so the word boxes remap correctly to the new screen dimensions.
            scrollView.frame = view.bounds

            if scrollView.zoomScale == 1.0 {
                imageView.frame = scrollView.bounds
                scrollView.contentSize = imageView.bounds.size
            }

            let displayedRect = AVMakeRect(aspectRatio: image.size, insideRect: imageView.bounds)
            overlayView.frame = displayedRect

            // viewDidLayoutSubviews fires on ANY layout pass, including ones
            // caused by unrelated UI changes (e.g. the Combine button's title
            // changing after a merge-mode tap). Only rebuild the word boxes when
            // the actual displayed image geometry changed — otherwise we tear
            // down and recreate every WordBoxView an instant after tapping it,
            // which is what caused merge-mode highlights to flicker and vanish.
            guard displayedRect != lastDisplayedRect, !allDetectedWords.isEmpty else { return }
            lastDisplayedRect = displayedRect

            imageDimOverlay.frame = displayedRect

            // Redraw all word boxes at the new scale — the normalized boundingBox
            // coordinates are orientation-independent so no OCR re-run is needed.
            drawWordBoxes(allDetectedWords)

            // Restore selection AND merge state after redraw. pendingMergeSelections
            // holds references to the old (now-detached) WordBoxView instances, so
            // those must be repointed at the freshly created boxes or future taps
            // (deselect, resetMergeMode) will silently miss them.
            for case let box as WordBoxView in overlayView.subviews {
                if selectedWords.contains(where: { $0.id == box.detectedWord.id }) {
                    box.isSelectedWord = true
                }
                if let idx = pendingMergeSelections.firstIndex(where: { $0.word.id == box.detectedWord.id }) {
                    box.mergeOrder = idx + 1
                    pendingMergeSelections[idx].box = box
                }
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
        guard let cgImage = image.cgImage else { completion([]); return }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation],
                  error == nil else { completion([]); return }

            // ── Step 1: pair each observation with its top candidate, sort top→bottom ──
            var obsLines: [(candidate: VNRecognizedText, text: String, box: CGRect)] = []
            for obs in observations {
                guard let candidate = obs.topCandidates(1).first else { continue }
                let line = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty { obsLines.append((candidate, line, obs.boundingBox)) }
            }
            obsLines.sort {
                if abs($0.box.minY - $1.box.minY) > 0.005 { return $0.box.minY > $1.box.minY }
                return $0.box.minX < $1.box.minX
            }
            // ── Step 1b: merge words hyphenated across lines ──────────────────────────
            // Vision gives each line as a separate observation. When a word is broken
            // with a hyphen at a line end ("self-" / "aware"), stitch the two fragments
            // into one DetectedWord so MW lookup gets the real word.
            var mergedObsLines: [(candidate: VNRecognizedText, text: String, box: CGRect)] = []
            var skipNext = false
            for i in 0..<obsLines.count {
                if skipNext { skipNext = false; continue }
                let current = obsLines[i]
                // Check if this line ends with a hyphen AND there is a next line
                if current.text.hasSuffix("-"), i + 1 < obsLines.count {
                    let next = obsLines[i + 1]
                    // Strip the trailing hyphen and join
                    let joined = String(current.text.dropLast()) + next.text
                    // Union the two bounding boxes
                    let unionBox = current.box.union(next.box)
                    // We lose per-word Vision boxes for the joined word, but that's
                    // acceptable — it will be treated as a single token below.
                    mergedObsLines.append((current.candidate, joined, unionBox))
                    skipNext = true
                } else {
                    mergedObsLines.append(current)
                }
            }
            obsLines = mergedObsLines   // reassign in place — var was declared above

            // ── Step 2: build full text & sentence map (unchanged logic) ──────────────
            var fullTextBuilder = ""
            for (i, item) in obsLines.enumerated() {
                if i > 0 {
                    let gap = abs(obsLines[i-1].box.minY - item.box.minY)
                    fullTextBuilder += gap > 0.03 ? "\n\n" : " "
                }
                fullTextBuilder += item.text
            }
            let fullText = fullTextBuilder

            let sentenceTokenizer = NLTokenizer(unit: .sentence)
            sentenceTokenizer.string = fullText
            var sentenceRanges: [Range<String.Index>] = []
            sentenceTokenizer.enumerateTokens(in: fullText.startIndex..<fullText.endIndex) { r, _ in
                sentenceRanges.append(r); return true
            }
            let sentences = sentenceRanges.map { String(fullText[$0]) }

            // Map each line to the sentence it overlaps most
            var cursor = fullText.startIndex
            var lineRanges: [Range<String.Index>] = []
            for item in obsLines {
                if let r = fullText.range(of: item.text, range: cursor..<fullText.endIndex) {
                    lineRanges.append(r); cursor = r.upperBound
                } else {
                    lineRanges.append(cursor..<cursor)
                }
            }
            var lineSentenceMap = [Int](repeating: 0, count: obsLines.count)
            for (i, lineRange) in lineRanges.enumerated() {
                var bestIdx = 0; var bestOverlap = 0
                for (idx, sentRange) in sentenceRanges.enumerated() {
                    let oStart = max(lineRange.lowerBound, sentRange.lowerBound)
                    let oEnd   = min(lineRange.upperBound, sentRange.upperBound)
                    if oStart < oEnd {
                        let len = fullText.distance(from: oStart, to: oEnd)
                        if len > bestOverlap { bestOverlap = len; bestIdx = idx }
                    }
                }
                lineSentenceMap[i] = bestIdx
            }

            // ── Step 3: use Vision's tight per-word boxes ──────────────────────────────
            // This is what Photos app does — instead of guessing word positions by
            // character proportion, we ask Vision for the exact bounding box it
            // already computed for each word token during recognition.
            var results: [DetectedWord] = []

            for (lineIdx, item) in obsLines.enumerated() {
                let sentenceIndex = lineSentenceMap[lineIdx]
                let contextSentence = sentences.indices.contains(sentenceIndex)
                    ? sentences[sentenceIndex] : item.text

                // Split on whitespace only — NOT NLTokenizer which splits on hyphens,
                // causing "well-known" → ["well", "known"] and making both unsearchable.
                let rawTokens = item.candidate.string
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.trimmingCharacters(in: .punctuationCharacters).isEmpty }

                // Track character position so we can call boundingBox(for:) with the
                // correct range of each token inside the candidate string.
                var searchStart = item.candidate.string.startIndex

                for token in rawTokens {
                    // Find this token's range in the candidate string
                    guard let tokenRange = item.candidate.string.range(
                        of: token,
                        range: searchStart..<item.candidate.string.endIndex
                    ) else { continue }
                    searchStart = tokenRange.upperBound

                    let wordText = token.trimmingCharacters(in: .punctuationCharacters)
                    guard !wordText.isEmpty else { continue }

                    if let wordRect = try? item.candidate.boundingBox(for: tokenRange) {
                        results.append(DetectedWord(
                            text: wordText,
                            boundingBox: wordRect.boundingBox,
                            contextSentence: contextSentence,
                            isPhrase: false,
                            phraseComponents: nil
                        ))
                    }
                }
            }

            // Sort top-to-bottom, left-to-right
            results.sort { w1, w2 in
                let y1 = w1.boundingBox.origin.y + w1.boundingBox.height
                let y2 = w2.boundingBox.origin.y + w2.boundingBox.height
                if abs(y1 - y2) > 0.01 { return y1 > y2 }
                return w1.boundingBox.origin.x < w2.boundingBox.origin.x
            }
            completion(results)
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true   // better handling of curly quotes
                                                 // and stylized/decorated text
        request.minimumTextHeight = 0.01        // don't skip small or decorated lines
        // Explicitly set language so Vision doesn't waste time on other scripts
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        DispatchQueue.global(qos: .userInitiated).async { try? handler.perform([request]) }
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
