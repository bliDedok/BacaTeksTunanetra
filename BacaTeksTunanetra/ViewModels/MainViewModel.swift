import Foundation
import SwiftUI
import AVFoundation
import Combine

@MainActor
final class MainViewModel: ObservableObject {
    @Published var statusText: String = "Menunggu inisialisasi"
    @Published var latestRecognizedText: String = "Belum ada teks"
    @Published var isScanning = false
    @Published var autoReadEnabled = true
    @Published var superLargeButtons = true
    @Published var cameraPermissionDenied = false
    @Published var errorMessage: String?
    @Published var readingHistory: [RecognizedTextItem] = []

    @Published var keyboardRemoteDetected = false
    @Published var bleRemoteDetected = false
    @Published var mfiAccessoryDetected = false

    let cameraService = CameraService()
    let speechService = SpeechService()
    let textRecognitionService = TextRecognitionService()
    let inputManager = InputManager()

    let minimumOCRConfidence: Float = 0.45
    let minimumTextLength: Int = 4
    let stableFrameThreshold: Int = 2
    let duplicateCooldown: TimeInterval = 8

    private var lastSpokenNormalizedText: String = ""
    private var lastSpokenAt: Date = .distantPast

    private var candidateNormalizedText: String = ""
    private var candidateRawText: String = ""
    private var candidateStableCount: Int = 0

    private var lastRecognizedForManualRead: String = ""
    private let maxHistoryCount = 10
    
    func updateDeviceOrientation() {
        cameraService.updateOrientation(for: UIDevice.current.orientation)
    }

    func onAppLaunch() {
        bindServices()
        requestPermissionsAndStart()
    }

    private func bindServices() {
        cameraService.onSampleBuffer = { [weak self] sampleBuffer in
            Task { @MainActor in
                guard let self, self.isScanning else { return }
                self.processFrame(sampleBuffer)
            }
        }

        inputManager.onAction = { [weak self] action in
            Task { @MainActor in
                self?.handleExternalAction(action)
            }
        }

        inputManager.$keyboardRemoteDetected
            .receive(on: DispatchQueue.main)
            .assign(to: &$keyboardRemoteDetected)

        inputManager.$bleRemoteDetected
            .receive(on: DispatchQueue.main)
            .assign(to: &$bleRemoteDetected)

        inputManager.$mfiAccessoryDetected
            .receive(on: DispatchQueue.main)
            .assign(to: &$mfiAccessoryDetected)
    }

    func requestPermissionsAndStart() {
        inputManager.start()
        cameraService.requestPermissionAndConfigure()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startScanning()
        }
    }

    func startScanning() {
        cameraPermissionDenied = cameraService.authorizationDenied
        guard !cameraPermissionDenied else {
            statusText = "Izin kamera ditolak"
            speechService.speakFeedback("Izin kamera ditolak")
            return
        }

        isScanning = true
        cameraService.startSession()
        statusText = "Mode scan aktif"
        speechService.speakFeedback("Mode scan aktif")
        AccessibilityHelper.hapticSuccess()
    }

    func pauseScanning() {
        isScanning = false
        cameraService.stopSession()
        statusText = "Scan dijeda"
        speechService.speakFeedback("Scan dijeda")
        AccessibilityHelper.hapticLight()
    }

    func toggleScanning() {
        isScanning ? pauseScanning() : startScanning()
    }

    private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        textRecognitionService.recognizeText(
            from: sampleBuffer,
            minimumConfidence: minimumOCRConfidence,
            orientation: cameraService.visionOrientation
        ) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let maybeOCR):
                guard let ocr = maybeOCR else {
                    self.statusText = "Tidak ada teks terdeteksi"
                    return
                }

                let text = ocr.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = StringNormalizer.normalize(text)

                guard StringNormalizer.isMeaningful(text, minimumLength: self.minimumTextLength) else {
                    return
                }

                self.latestRecognizedText = text
                self.lastRecognizedForManualRead = text
                self.statusText = "Teks terdeteksi"

                self.handleStableDetection(
                    rawText: text,
                    normalizedText: normalized,
                    confidence: ocr.averageConfidence
                )

            case .failure(let error):
                self.errorMessage = error.localizedDescription
                self.statusText = "OCR gagal"
            }
        }
    }

    private func handleStableDetection(rawText: String, normalizedText: String, confidence: Float) {
        if normalizedText == candidateNormalizedText {
            candidateStableCount += 1
        } else {
            candidateNormalizedText = normalizedText
            candidateRawText = rawText
            candidateStableCount = 1
        }

        guard candidateStableCount >= stableFrameThreshold else { return }

        let now = Date()
        let isSameAsLastSpoken = normalizedText == lastSpokenNormalizedText
        let isWithinCooldown = now.timeIntervalSince(lastSpokenAt) < duplicateCooldown

        if isSameAsLastSpoken && isWithinCooldown {
            return
        }

        let item = RecognizedTextItem(
            text: rawText,
            normalizedText: normalizedText,
            confidence: confidence
        )
        addToHistory(item)

        if autoReadEnabled {
            readText(rawText, normalized: normalizedText)
        }
    }

    private func addToHistory(_ item: RecognizedTextItem) {
        if readingHistory.first?.normalizedText == item.normalizedText {
            return
        }

        readingHistory.insert(item, at: 0)
        if readingHistory.count > maxHistoryCount {
            readingHistory = Array(readingHistory.prefix(maxHistoryCount))
        }
    }

    func readCurrentTextNow() {
        let text = lastRecognizedForManualRead.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "Belum ada teks" else {
            speechService.speakFeedback("Belum ada teks untuk dibacakan")
            return
        }

        let normalized = StringNormalizer.normalize(text)
        readText(text, normalized: normalized)
    }

    func repeatLastSpeech() {
        guard let latest = readingHistory.first else {
            speechService.speakFeedback("Belum ada riwayat bacaan")
            return
        }

        speechService.speakFeedback("Mengulang bacaan terakhir")
        speechService.speak(latest.text)
        lastSpokenNormalizedText = latest.normalizedText
        lastSpokenAt = Date()
        statusText = "Bacaan diulang"
        AccessibilityHelper.hapticSuccess()
    }

    private func readText(_ text: String, normalized: String) {
        speechService.speak(text)
        lastSpokenNormalizedText = normalized
        lastSpokenAt = Date()
        statusText = "Membacakan teks"
        AccessibilityHelper.hapticSuccess()
    }

    func toggleAutoRead() {
        autoReadEnabled.toggle()
        let message = autoReadEnabled ? "Auto Read aktif" : "Auto Read nonaktif"
        statusText = message
        speechService.speakFeedback(message)
        AccessibilityHelper.announce(message)
    }

    func pauseOrResumeSpeech() {
        speechService.pauseOrResume()
        speechService.speakFeedback("Kontrol suara dijalankan")
    }

    func handleKeyInput(_ input: String) {
        inputManager.handleKeyInput(input)
    }

    private func handleExternalAction(_ action: InputManager.ExternalAction) {
        switch action {
        case .triggerScan:
            speechService.speakFeedback("Perintah scan diterima")
            readCurrentTextNow()

        case .repeatLastSpeech:
            repeatLastSpeech()

        case .toggleAutoRead:
            toggleAutoRead()

        case .pauseOrResumeSpeech:
            pauseOrResumeSpeech()
        }
    }
}
