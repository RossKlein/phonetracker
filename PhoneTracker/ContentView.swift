import ARKit
import RealityKit
import SwiftUI

struct ContentView: View {
    @StateObject private var tracker = Tracker()

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraView(session: tracker.session)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text(tracker.status)
                    .font(.headline)
                Text(tracker.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("Server", text: $tracker.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Room", text: $tracker.room)
                    TextField("Token", text: $tracker.token)
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                Button(tracker.running ? "Stop" : "Start tracking") {
                    tracker.toggle()
                }
                .buttonStyle(.borderedProminent)
                .disabled(tracker.running && !tracker.canStop)
                Button("Reset room origin") {
                    tracker.resetOrigin()
                }
                .disabled(!tracker.running)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding()
        }
    }
}

private struct CameraView: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.session = session
        view.automaticallyConfigureSession = false
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
