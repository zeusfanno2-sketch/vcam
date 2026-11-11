import SwiftUI
import AVKit

// MARK: - device

enum Device {
    static var name: String { UIDevice.current.name }
    static var id: String { UIDevice.current.identifierForVendor?.uuidString ?? "unknown" }
    static var model: String { UIDevice.current.model }
}

// MARK: - store

final class AppState: ObservableObject {
    @Published var server: String
    @Published var key: String
    @Published var expiresAt: Double
    @Published var deviceName: String
    @Published var unlocked: Bool
    @Published var message: String = ""

    init() {
        let d = UserDefaults.standard
        server = d.string(forKey: "server") ?? "https://ranch-complicated-commander-pink.trycloudflare.com"
        key = d.string(forKey: "key") ?? ""
        expiresAt = d.double(forKey: "expiresAt")
        deviceName = d.string(forKey: "deviceName") ?? Device.name
        unlocked = false
    }

    var daysLeft: Int {
        guard expiresAt > 0 else { return 0 }
        return max(0, Int(ceil((expiresAt / 1000 - Date().timeIntervalSince1970) / 86400)))
    }
    var expiryText: String {
        guard expiresAt > 0 else { return "—" }
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"
        return f.string(from: Date(timeIntervalSince1970: expiresAt / 1000))
    }

    func persist() {
        let d = UserDefaults.standard
        d.set(server, forKey: "server"); d.set(key, forKey: "key")
        d.set(expiresAt, forKey: "expiresAt"); d.set(deviceName, forKey: "deviceName")
    }

    func activate() async {
        await MainActor.run { message = "Đang kiểm tra…" }
        guard let url = URL(string: server.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/v1/public/redeem") else {
            await MainActor.run { message = "URL server không hợp lệ" }; return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 15
        let body: [String: String] = ["key": key.uppercased().trimmingCharacters(in: .whitespaces), "udid": Device.id, "name": Device.name]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let ok = obj["ok"] as? Bool ?? false
            let msg = obj["message"] as? String ?? "Lỗi"
            await MainActor.run {
                message = msg
                if ok {
                    expiresAt = (obj["expiresAt"] as? Double) ?? 0
                    deviceName = (obj["deviceName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? Device.name
                    persist()
                    unlocked = true
                }
            }
        } catch {
            await MainActor.run { message = "Không kết nối được server" }
        }
    }

    func verifyOnLaunch() async {
        guard !key.isEmpty, expiresAt > Date().timeIntervalSince1970 * 1000 else { return }
        await MainActor.run { unlocked = true }
        guard let url = URL(string: server.trimmingCharacters(in: .whitespaces) + "/api/v1/public/check") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 10
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["key": key, "udid": Device.id])
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            let valid = obj["valid"] as? Bool ?? false
            await MainActor.run { if !valid { unlocked = false; message = "Key không hợp lệ" } }
        }
    }
}

// MARK: - player

final class StreamModel: ObservableObject {
    @Published var urlText: String
    @Published var state: String = "—"
    @Published var live: Bool = false

    let player = AVPlayer()
    private var item: AVPlayerItem?
    private var observer: NSKeyValueObservation?

    init() {
        urlText = UserDefaults.standard.string(forKey: "streamURL") ?? "http://192.168.1.10:8888/live/test/index.m3u8"
    }

    func connect() {
        let raw = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw) else { state = "URL không hợp lệ"; return }
        UserDefaults.standard.set(raw, forKey: "streamURL")

        observer?.invalidate()
        let it = AVPlayerItem(asset: AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "ObsCam/1.0"]
        ]))
        it.preferredForwardBufferDuration = 0.2
        it.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        item = it
        player.replaceCurrentItem(with: it)
        player.automaticallyWaitsToMinimizeStalling = false
        player.play()
        state = "Đang kết nối"

        observer = it.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    self?.state = "Đã kết nối"; self?.live = item.isPlaybackLikelyToKeepUp
                case .failed:
                    self?.state = "Lỗi kết nối"
                default:
                    self?.state = "Đang tải"
                }
            }
        }
    }

    func stop() {
        observer?.invalidate(); observer = nil
        player.pause(); player.replaceCurrentItem(with: nil); live = false
    }
}

struct PlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerUIView { let v = PlayerUIView(); v.attach(player); return v }
    func updateUIView(_ uiView: PlayerUIView, context: Context) { uiView.attach(player) }
}

final class PlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    init() { super.init(frame: .zero); backgroundColor = .black; playerLayer.videoGravity = .resizeAspect }
    required init?(coder: NSCoder) { fatalError() }
    func attach(_ player: AVPlayer) { if playerLayer.player !== player { playerLayer.player = player } }
}

// MARK: - views

struct RootView: View {
    @StateObject var app = AppState()
    var body: some View {
        Group {
            if app.unlocked { PlayerView(app: app) } else { GateView(app: app) }
        }
        .preferredColorScheme(.dark)
        .task { await app.verifyOnLaunch() }
    }
}

struct GateView: View {
    @ObservedObject var app: AppState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("OBS Cam").font(.title2.bold()).foregroundStyle(.white)
                Text("Nhập key để sử dụng").font(.footnote).foregroundStyle(.secondary)

                field("Key", text: $app.key, caps: .characters, keyboard: .asciiCapable)

                kv("Tên thiết bị", Device.name)
                kv("ID thiết bị", Device.id)
                kv("Model", Device.model)

                Button {
                    Task { await app.activate() }
                } label: {
                    Text("Kích hoạt").bold().frame(maxWidth: .infinity).padding(14)
                        .background(Color.blue).clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                }

                Text(app.message).font(.footnote).foregroundStyle(.orange)
                Spacer()
            }
            .padding(22)
        }
    }

    private func field(_ label: String, text: Binding<String>, caps: TextInputAutocapitalization, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text)
                .textInputAutocapitalization(caps)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .padding(12)
                .background(Color(white: 0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.caption.monospaced()).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
        }
    }
}

struct PlayerView: View {
    @ObservedObject var app: AppState
    @StateObject private var stream = StreamModel()
    @State private var sheet = false
    @State private var editURL = false

    var body: some View {
        ZStack {
            PlayerLayer(player: stream.player).ignoresSafeArea()

            VStack {
                HStack(spacing: 8) {
                    Circle().fill(stream.live ? .green : .orange).frame(width: 8, height: 8)
                    Text(stream.state).font(.footnote).foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Text("\(app.daysLeft)d").font(.caption.monospaced()).foregroundStyle(.white.opacity(0.8))
                    Button { editURL.toggle() } label: { Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(.white) }
                    Button { sheet = true } label: { Image(systemName: "info.circle.fill").foregroundStyle(.white) }
                }
                .padding(12)
                .background(.black.opacity(0.45))

                Spacer()
            }

            if editURL {
                VStack(spacing: 10) {
                    TextField("HLS URL", text: $stream.urlText)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .padding(12).background(Color(white: 0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10)).foregroundStyle(.white)
                    Button {
                        stream.connect(); editURL = false
                    } label: {
                        Text("Kết nối").bold().frame(maxWidth: .infinity).padding(12)
                            .background(Color.blue).clipShape(RoundedRectangle(cornerRadius: 10)).foregroundStyle(.white)
                    }
                }
                .padding(16).background(.black.opacity(0.75))
            }
        }
        .onAppear { stream.connect() }
        .onDisappear { stream.stop() }
        .sheet(isPresented: $sheet) {
            InfoView(app: app, streamURL: stream.urlText)
                .presentationDetents([.medium])
        }
    }
}

struct InfoView: View {
    @ObservedObject var app: AppState
    let streamURL: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Thiết bị") {
                    row("Tên", Device.name)
                    row("ID", Device.id)
                    row("Model", Device.model)
                }
                Section("Bản quyền") {
                    row("Key", app.key)
                    row("Hạn dùng", app.expiryText)
                    row("Còn lại", app.daysLeft.description + " ngày")
                }
                Section("Kết nối") {
                    row("Stream", streamURL)
                    row("Phiên bản", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                }
            }
            .navigationTitle("Thông tin")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Xong") { dismiss() } } }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).foregroundStyle(.secondary).font(.caption)
            Spacer()
            Text(v).font(.caption.monospaced()).multilineTextAlignment(.trailing)
        }
    }
}
