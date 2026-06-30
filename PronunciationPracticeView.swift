import SwiftUI
import AVFoundation

struct PronunciationPracticeView: View {
    let word: String
    let audioURL: String?   // for listening to correct pronunciation

    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordedFileURL: URL?
    @State private var assessmentResult: PronunciationService.AssessmentResult?
    @State private var errorMessage: String?
    @State private var isLoading = false
    private func scoreColor(for score: Double) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Target word always visible
                HStack {
                    Text(word)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)

                    Button {
                        SpeechService.pronounce(word: word, audioURL: audioURL)
                    } label: {
                        Image(systemName: "speaker.wave.2")
                            .font(.title2)
                            .frame(width: 32, height: 32)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                Text("Pronounce the word clearly")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Record / Stop button
                Button {
                    if isRecording {
                        stopRecordingAndAssess()
                    } else {
                        startRecording()
                    }
                } label: {
                    Label(isRecording ? "Stop & Assess" : "Start Recording", systemImage: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: 220, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)

                if isLoading {
                    ProgressView("Analyzing pronunciation…")
                }

                // Results
                // Results
                // In PronunciationPracticeView.swift

                // Results section of the body
                // Results
                // Results
                if let result = assessmentResult {
                    VStack(alignment: .leading, spacing: 12) {
                        // Overall Header
                        HStack {
                            Text("Overall Accuracy:")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(result.overallScore, specifier: "%.0f")%")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(scoreColor(for: result.overallScore))
                        }
                        
                        Divider()
                        
                        ForEach(result.wordResults, id: \.word) { wordResult in
                            VStack(alignment: .leading, spacing: 12) {
                                // Individual Word Score
                                HStack {
                                    Text(wordResult.word)
                                        .font(.headline)
                                        .fontWeight(.bold)
                                    Spacer()
                                    Text("\(wordResult.accuracyScore, specifier: "%.0f")%")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(scoreColor(for: wordResult.accuracyScore))
                                }
                                
                                // 👈 IPA Phoneme Breakdown
                                VStack(spacing: 8) {
                                    ForEach(wordResult.phonemes) { phoneme in
                                        HStack(spacing: 12) {
                                            Text(phoneme.text) // 👈 Reads the IPA text (e.g. ɔː)
                                                .font(.system(.body, design: .default))
                                                .fontWeight(.semibold)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                                .background(scoreColor(for: phoneme.accuracyScore).opacity(0.15))
                                                .foregroundColor(scoreColor(for: phoneme.accuracyScore))
                                                .cornerRadius(8)
                                                .frame(width: 60, alignment: .leading)
                                            
                                            ProgressView(value: phoneme.accuracyScore, total: 100)
                                                .tint(scoreColor(for: phoneme.accuracyScore))
                                            
                                            Text("\(phoneme.accuracyScore, specifier: "%.0f")%")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(scoreColor(for: phoneme.accuracyScore))
                                                .frame(width: 35, alignment: .trailing)
                                        }
                                    }
                                }
                                .padding(.leading, 4)
                            }
                            .padding(.bottom, 4)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(12)
                }



                if let error = errorMessage {
                    Text("Error: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                // Temporary share button to export the recorded file
                if let fileURL = recordedFileURL {
                    ShareLink(item: fileURL) {
                        Label("Share Recording", systemImage: "square.and.arrow.up")
                    }
                    .padding(.top, 8)
                }
                Spacer()
            }
            .padding()
            .navigationBarTitle("Practice", displayMode: .inline)
        }
        .onDisappear {
            stopRecordingWithoutAssess()
        }
    }
    func createWAVData(from rawData: Data) -> Data? {
        let sampleRate: UInt32 = 16000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(rawData.count)
        let headerSize: UInt32 = 44

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: (dataSize + headerSize - 8).littleEndian, Array.init))
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))   // PCM
        header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian, Array.init))
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))

        var wavData = header
        wavData.append(rawData)
        return wavData
    }
    private func startRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default)
        try? session.setActive(true)

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString + ".wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.record()
            isRecording = true
            recordedFileURL = fileURL
            assessmentResult = nil
            errorMessage = nil
        } catch {
            errorMessage = "Recording failed: \(error.localizedDescription)"
        }
    }
    private func stopRecordingAndAssess() {
        audioRecorder?.stop()
        isRecording = false

        print("[Practice] Word to assess: '\(word)'")

        guard !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "No word to assess. Please select a word first."
            return
        }

        guard let fileURL = recordedFileURL, let rawData = try? Data(contentsOf: fileURL) else {
            errorMessage = "No recording found"
            return
        }

        let audioData: Data
        if rawData.count > 44, String(data: rawData.subdata(in: 0..<4), encoding: .ascii) == "RIFF" {
            audioData = rawData.subdata(in: 44..<rawData.count)
            print("[Practice] Stripped WAV header, sending raw PCM (\(audioData.count) bytes)")
        } else {
            audioData = rawData
        }

        isLoading = true
        Task {
            do {
                let result = try await PronunciationService.assessPronunciation(audioData: audioData, expectedText: word)
                await MainActor.run {
                    assessmentResult = result
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
    private func stopRecordingWithoutAssess() {
        audioRecorder?.stop()
        isRecording = false

        print("[Practice] Recorded file path: \(recordedFileURL?.path ?? "none")")
    }
}
