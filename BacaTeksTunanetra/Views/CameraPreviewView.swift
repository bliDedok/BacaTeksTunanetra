import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let videoOrientation: AVCaptureVideoOrientation

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspect
        if let connection = view.videoPreviewLayer.connection,
           connection.isVideoOrientationSupported {
            connection.videoOrientation = videoOrientation
        }
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.videoPreviewLayer.session = session
        if let connection = uiView.videoPreviewLayer.connection,
           connection.isVideoOrientationSupported {
            connection.videoOrientation = videoOrientation
        }
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Layer is not AVCaptureVideoPreviewLayer")
        }
        return layer
    }
}
