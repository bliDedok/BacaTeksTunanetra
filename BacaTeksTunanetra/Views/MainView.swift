import SwiftUI

struct MainView: View {
    @EnvironmentObject var viewModel: MainViewModel

    private var singleTapGesture: some Gesture {
        TapGesture(count: 1)
            .onEnded {
                viewModel.readCurrentTextNow()
            }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                viewModel.pauseOrResumeSpeech()
            }
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.8)
            .onEnded { _ in
                viewModel.stopSpeechAndReset()
            }
    }

    var body: some View {
        ZStack {
            CameraPreviewView(
                session: viewModel.cameraService.session,
                videoOrientation: viewModel.cameraService.previewOrientation
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)

            VStack {
                Spacer()

                Text(viewModel.statusText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(.bottom, 28)
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .gesture(
            ExclusiveGesture(doubleTapGesture, singleTapGesture)
        )
        .simultaneousGesture(longPressGesture)
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            viewModel.updateDeviceOrientation()
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            viewModel.updateDeviceOrientation()
        }
        .overlay(
            HardwareKeyCaptureView { input in
                viewModel.handleKeyInput(input)
            }
            .frame(width: 1, height: 1)
            .opacity(0.01)
        )
        .alert(
            "Terjadi Masalah",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kamera pemindai teks aktif")
        .accessibilityHint(
            "Arahkan kamera ke teks. Ketuk satu kali untuk langsung membaca teks yang terdeteksi. Ketuk dua kali untuk pause atau lanjutkan suara. Tekan lama untuk menghentikan bacaan."
        )
    }
}
