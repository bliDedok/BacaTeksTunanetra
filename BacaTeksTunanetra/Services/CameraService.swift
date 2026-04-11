import Foundation
import Combine
import AVFoundation
import UIKit
import CoreMedia
import ImageIO

final class CameraService: NSObject, ObservableObject {
    @Published var isSessionRunning = false
    @Published var authorizationDenied = false

    @Published var previewOrientation: AVCaptureVideoOrientation = .portrait
    @Published var visionOrientation: CGImagePropertyOrientation = .right

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "CameraService.SessionQueue")
    private let videoOutput = AVCaptureVideoDataOutput()

    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    private var frameCounter = 0
    private let frameInterval = 6

    func requestPermissionAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.authorizationDenied = !granted
                }
                if granted {
                    self?.configureSession()
                }
            }
        default:
            DispatchQueue.main.async {
                self.authorizationDenied = true
            }
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                self.session.commitConfiguration()
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: camera)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                }

                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.setSampleBufferDelegate(
                    self,
                    queue: DispatchQueue(label: "CameraService.VideoOutputQueue")
                )

                if self.session.canAddOutput(self.videoOutput) {
                    self.session.addOutput(self.videoOutput)
                }

                self.applyOrientation()

                self.session.commitConfiguration()
            } catch {
                self.session.commitConfiguration()
                print("Camera configure error: \(error.localizedDescription)")
            }
        }
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.session.isRunning else { return }

            self.session.startRunning()

            DispatchQueue.main.async {
                self.isSessionRunning = true
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.session.isRunning else { return }

            self.session.stopRunning()

            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    func updateOrientation(for deviceOrientation: UIDeviceOrientation) {
        let newPreviewOrientation: AVCaptureVideoOrientation
        let newVisionOrientation: CGImagePropertyOrientation

        switch deviceOrientation {
        case .portrait:
            newPreviewOrientation = .portrait
            newVisionOrientation = .right

        case .portraitUpsideDown:
            newPreviewOrientation = .portraitUpsideDown
            newVisionOrientation = .left

        case .landscapeLeft:
            // UIDevice landscapeLeft dibalik untuk AVCapture
            newPreviewOrientation = .landscapeRight
            newVisionOrientation = .up

        case .landscapeRight:
            newPreviewOrientation = .landscapeLeft
            newVisionOrientation = .down

        default:
            return
        }

        DispatchQueue.main.async {
            self.previewOrientation = newPreviewOrientation
            self.visionOrientation = newVisionOrientation
        }

        sessionQueue.async { [weak self] in
            self?.applyOrientation()
        }
    }

    private func applyOrientation() {
        if let connection = videoOutput.connection(with: .video),
           connection.isVideoOrientationSupported {
            connection.videoOrientation = previewOrientation
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frameCounter += 1
        if frameCounter % frameInterval != 0 { return }
        onSampleBuffer?(sampleBuffer)
    }
}
