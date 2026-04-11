import SwiftUI

struct MainView: View {
    @EnvironmentObject var viewModel: MainViewModel

    private var previewHeight: CGFloat {
        UIDevice.current.orientation.isLandscape ? 180 : 250
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        headerSection
                        cameraSection
                        statusSection
                        actionButtonsSection
                        externalInputSection
                        settingsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
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
        .alert("Terjadi Masalah", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BacaTeks Tunanetra")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.black)

            Text("Bantu membaca teks dari buku, lembar tugas, dan papan informasi secara otomatis.")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("BacaTeks Tunanetra. Aplikasi pembaca teks real time.")
    }

    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kamera")
                .font(.title3.bold())
                .foregroundColor(.black)

            ZStack(alignment: .topLeading) {
                CameraPreviewView(
                    session: viewModel.cameraService.session,
                    videoOrientation: viewModel.cameraService.previewOrientation
                )
                .frame(height: previewHeight)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 24))

                Text(viewModel.isScanning ? "Scan Aktif" : "Scan Dijeda")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(viewModel.isScanning ? Color.green.opacity(0.85) : Color.gray.opacity(0.85))
                    .clipShape(Capsule())
                    .padding(12)
                    .accessibilityHidden(true)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .accessibilityLabel("Preview kamera")
            .accessibilityHint("Arahkan kamera ke teks. Preview mengikuti orientasi perangkat.")

            Text("Arahkan kamera ke teks lalu tahan 1 sampai 2 detik agar pembacaan stabil.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Status")
                .font(.title3.bold())
                .foregroundColor(.black)

            Text(viewModel.statusText)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.black)
                .accessibilityLabel("Status \(viewModel.statusText)")

            Divider()

            Text("Teks Terakhir")
                .font(.title3.bold())
                .foregroundColor(.black)

            ScrollView {
                Text(viewModel.latestRecognizedText)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .frame(minHeight: 130, maxHeight: 190)
            .accessibilityLabel("Teks terakhir terdeteksi")
            .accessibilityValue(viewModel.latestRecognizedText)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var actionButtonsSection: some View {
        VStack(spacing: 14) {
            BigAccessibleButton(
                title: viewModel.isScanning ? "Pause Scan" : "Mulai Scan",
                subtitle: viewModel.isScanning
                    ? "Menghentikan scan kamera sementara"
                    : "Mengaktifkan scan teks real-time",
                superLarge: viewModel.superLargeButtons
            ) {
                viewModel.toggleScanning()
            }

            BigAccessibleButton(
                title: "Bacakan Sekarang",
                subtitle: "Membacakan hasil teks terbaru",
                superLarge: viewModel.superLargeButtons
            ) {
                viewModel.readCurrentTextNow()
            }

            BigAccessibleButton(
                title: "Ulangi",
                subtitle: "Mengulang bacaan terakhir",
                superLarge: viewModel.superLargeButtons
            ) {
                viewModel.repeatLastSpeech()
            }

            BigAccessibleButton(
                title: viewModel.autoReadEnabled ? "Auto Read: ON" : "Auto Read: OFF",
                subtitle: "Mengaktifkan atau menonaktifkan pembacaan otomatis",
                superLarge: viewModel.superLargeButtons
            ) {
                viewModel.toggleAutoRead()
            }
        }
    }

    private var externalInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Input Eksternal")
                .font(.title3.bold())
                .foregroundColor(.black)

            VStack(spacing: 10) {
                inputRow(title: "Keyboard Remote", isOn: viewModel.keyboardRemoteDetected)
                inputRow(title: "BLE Remote", isOn: viewModel.bleRemoteDetected)
                inputRow(title: "MFi Accessory", isOn: viewModel.mfiAccessoryDetected)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pengaturan Tampilan")
                .font(.title3.bold())
                .foregroundColor(.black)

            Toggle(isOn: $viewModel.superLargeButtons) {
                Text("Mode tombol super besar")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.black)
            }
            .tint(.black)
            .accessibilityLabel("Mode tombol super besar")
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func inputRow(title: String, isOn: Bool) -> some View {
        HStack {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundColor(.black)

            Spacer()

            Text(isOn ? "Terdeteksi" : "Belum")
                .font(.footnote.bold())
                .foregroundColor(isOn ? .green : .gray)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background((isOn ? Color.green : Color.gray).opacity(0.12))
                .clipShape(Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(isOn ? "terdeteksi" : "belum terdeteksi")")
    }
}
