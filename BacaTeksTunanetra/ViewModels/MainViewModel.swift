import Foundation
import SwiftUI
import AVFoundation
import Combine

@MainActor
final class MainViewModel: ObservableObject {
    @Published var activeMode: VisionMode = .textReading
    @Published var latestHeldObjectText: String = "Belum ada objek"
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
    let stableFrameThreshold: Int = 3
    let duplicateCooldown: TimeInterval = 8
    let heldObjectRecognitionService = HeldObjectRecognitionService()
    
    private var lastTextFrameProcessedAt: Date = .distantPast
    private var lastObjectFrameProcessedAt: Date = .distantPast

    private let textFrameProcessingInterval: TimeInterval = 0.30
    private let objectFrameProcessingInterval: TimeInterval = 0.35
    
    private var lastSpokenObjectLabel: String = ""
    private var lastObjectSpokenAt: Date = .distantPast
    private var candidateObjectLabel: String = ""
    private var candidateObjectStableCount: Int = 0
    private let objectStableThreshold: Int = 3
    private let objectDuplicateCooldown: TimeInterval = 5
    private var isProcessingHeldObjectFrame = false

    private var lastSpokenNormalizedText: String = ""
    private var lastSpokenAt: Date = .distantPast

    private var candidateNormalizedText: String = ""
    private var candidateRawText: String = ""
    private var candidateStableCount: Int = 0

    private var lastRecognizedForManualRead: String = ""
    private let maxHistoryCount = 10

    // MARK: - Reading Lock
    private var lockedReadingText: String = ""
    private var mustWaitForNewText: Bool = false
    
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

        switch activeMode {

        case .textReading:

            guard shouldProcessTextFrame() else { return }

            processTextFrame(sampleBuffer)

        case .heldObject:

            guard shouldProcessObjectFrame() else { return }

            processHeldObjectFrame(sampleBuffer)

        }

    }
    
    private func shouldProcessTextFrame() -> Bool {

        let now = Date()

        guard now.timeIntervalSince(lastTextFrameProcessedAt) >= textFrameProcessingInterval else {

            return false

        }

        lastTextFrameProcessedAt = now

        return true

    }

    private func shouldProcessObjectFrame() -> Bool {

        let now = Date()

        guard now.timeIntervalSince(lastObjectFrameProcessedAt) >= objectFrameProcessingInterval else {

            return false

        }

        lastObjectFrameProcessedAt = now

        return true

    }
    
    private func processTextFrame(_ sampleBuffer: CMSampleBuffer) {
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
        // Jika aplikasi sedang membacakan teks, jangan proses bacaan baru dulu.
        guard !speechService.isSpeaking else {
            statusText = "Sedang membacakan teks"
            return
        }

        // Jika teks yang sama sudah pernah dibacakan, jangan baca ulang.
        // Pengguna harus reset dulu jika ingin membaca ulang teks yang sama.
        if mustWaitForNewText && isTextSimilar(normalizedText, lockedReadingText) {
            statusText = "Teks sudah dibacakan"
            return
        }

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
    
    private func processHeldObjectFrame(_ sampleBuffer: CMSampleBuffer) {
        guard !speechService.isSpeaking else {
            statusText = "Sedang membacakan"
            return
        }

        guard !isProcessingHeldObjectFrame else {
            return
        }

        isProcessingHeldObjectFrame = true

        heldObjectRecognitionService.recognizeHeldObject(
            from: sampleBuffer,
            orientation: cameraService.visionOrientation
        ) { [weak self] (result: Result<DetectedHeldObject?, Error>) in
            guard let self else { return }

            self.isProcessingHeldObjectFrame = false

            switch result {
            case .success(let maybeObject):
                guard let object = maybeObject else {
                    self.statusText = "Arahkan kamera ke benda yang dipegang"
                    return
                }

                self.latestHeldObjectText = object.spokenLabel
                self.statusText = "Objek: \(object.spokenLabel) \(Int(object.confidence * 100))%"

                print("ML DETECTED:", object.rawLabel, object.spokenLabel, object.confidence)

                self.handleStableHeldObject(object)

            case .failure(let error):
                let message = error.localizedDescription.lowercased()

                if message.contains("cancel") || message.contains("cancelled") {
                    return
                }

                self.errorMessage = error.localizedDescription
                self.statusText = "Deteksi objek gagal"
            }
        }
    }
    
    private func handleStableHeldObject(_ object: DetectedHeldObject) {
        let normalizedLabel = object.spokenLabel.lowercased()

        if normalizedLabel == candidateObjectLabel {
            candidateObjectStableCount += 1
        } else {
            candidateObjectLabel = normalizedLabel
            candidateObjectStableCount = 1
        }

        guard candidateObjectStableCount >= objectStableThreshold else {
            return
        }

        let now = Date()
        let isSameAsLastObject = normalizedLabel == lastSpokenObjectLabel
        let isWithinCooldown = now.timeIntervalSince(lastObjectSpokenAt) < objectDuplicateCooldown

        if isSameAsLastObject && isWithinCooldown {
            return
        }

        speakHeldObject(object.spokenLabel)
    }
    
    private func speakHeldObject(_ objectName: String) {
        guard !objectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let sentence = "Objek yang Anda pegang adalah \(objectName)"

        speechService.speak(sentence)

        lastSpokenObjectLabel = objectName.lowercased()
        lastObjectSpokenAt = Date()
        statusText = "Membacakan objek"
        AccessibilityHelper.hapticSuccess()
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
    
    func toggleVisionMode() {
        stopSpeechAndReset()

        switch activeMode {
        case .textReading:
            activeMode = .heldObject
        case .heldObject:
            activeMode = .textReading
        }
        print("ACTIVE MODE:", activeMode)
        statusText = activeMode.title
        speechService.speakFeedback(activeMode.voiceMessage)
        AccessibilityHelper.announce(activeMode.voiceMessage)
        AccessibilityHelper.hapticSuccess()
    }
    
    func handlePrimaryTap() {
        switch activeMode {
        case .textReading:
            readCurrentTextNow()

        case .heldObject:
            let objectName = latestHeldObjectText.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !objectName.isEmpty, objectName != "Belum ada objek" else {
                speechService.speakFeedback("Belum ada objek yang dipegang terdeteksi")
                return
            }

            speakHeldObject(objectName)
        }
    }
    
    private func isTextSimilar(_ firstText: String, _ secondText: String) -> Bool {
        let first = firstText.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = secondText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !first.isEmpty, !second.isEmpty else { return false }

        if first == second {
            return true
        }

        if first.contains(second) || second.contains(first) {
            return true
        }

        let firstWords = Set(first.split(separator: " ").map { String($0) })
        let secondWords = Set(second.split(separator: " ").map { String($0) })

        guard !firstWords.isEmpty, !secondWords.isEmpty else { return false }

        let sameWords = firstWords.intersection(secondWords).count
        let totalWords = max(firstWords.count, secondWords.count)

        let similarity = Double(sameWords) / Double(totalWords)

        return similarity >= 0.75
    }

    func readCurrentTextNow() {
        guard !speechService.isSpeaking else {
            statusText = "Tunggu sampai bacaan selesai"
            AccessibilityHelper.hapticWarning()
            return
        }

        let text = lastRecognizedForManualRead.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty, text != "Belum ada teks" else {
            speechService.speakFeedback("Belum ada teks untuk dibacakan")
            return
        }

        let normalized = StringNormalizer.normalize(text)

        if mustWaitForNewText && isTextSimilar(normalized, lockedReadingText) {
            speechService.speakFeedback("Teks ini sudah dibacakan. Tekan lama untuk reset jika ingin membaca ulang.")
            statusText = "Teks sudah dibacakan"
            AccessibilityHelper.hapticWarning()
            return
        }

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
        // Kunci teks yang sedang dibaca.
        // Setelah ini, teks yang sama tidak akan dibaca ulang otomatis.
        lockedReadingText = normalized
        mustWaitForNewText = true

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
    
    func stopSpeechAndReset() {
        speechService.stopSpeaking()
        candidateNormalizedText = ""
        candidateRawText = ""
        candidateStableCount = 0
        lastTextFrameProcessedAt = .distantPast
        lastObjectFrameProcessedAt = .distantPast
        latestRecognizedText = "Belum ada teks"
        lastRecognizedForManualRead = ""
        lockedReadingText = ""
        mustWaitForNewText = false
        statusText = "Scan diulang"
        speechService.speakFeedback("Bacaan dihentikan. Arahkan kamera ke teks.")
        AccessibilityHelper.hapticWarning()

    }

    func handleKeyInput(_ input: String) {
        inputManager.handleKeyInput(input)
    }

    private func handleExternalAction(_ action: InputManager.ExternalAction) {
        switch action {
        case .triggerScan:
            speechService.speakFeedback("Perintah scan diterima")
            handlePrimaryTap()

        case .repeatLastSpeech:
            repeatLastSpeech()

        case .toggleAutoRead:
            toggleAutoRead()

        case .pauseOrResumeSpeech:
            pauseOrResumeSpeech()
        }
    }
}
