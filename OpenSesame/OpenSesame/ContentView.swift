import SwiftUI
import CoreBluetooth
import AVFoundation

// MARK: - Video Player View

struct DoorVideoView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        PlayerContainerView(player: player)
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {}
}

class PlayerContainerView: UIView {
    // Using layerClass ensures AVPlayerLayer auto-fills the view bounds.
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
}

// MARK: - Door Video Controller

class DoorVideoController: ObservableObject {
    // Two players: one visible (front), one preloading (back).
    // We swap them the instant the back player has its first frame ready,
    // so there is never a black gap.
    let playerA = AVPlayer()
    let playerB = AVPlayer()
    @Published var showA: Bool = true

    private var frontPlayer: AVPlayer { showA ? playerA : playerB }
    private var backPlayer:  AVPlayer { showA ? playerB : playerA }

    private let urlOpening: URL
    private let urlOpen:    URL
    private let urlClosing: URL

    private var endObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var pendingStatus = "Closed"

    init() {
        func bundleURL(_ name: String) -> URL {
            if let url = Bundle.main.url(forResource: name, withExtension: "mov") { return url }
            print("[DoorVideoController] ⚠️ Not found in bundle: \(name).mov")
            return URL(fileURLWithPath: "")
        }

        urlOpening = bundleURL("Door Opening")
        urlOpen    = bundleURL("Door Open")
        urlClosing = bundleURL("Door Closing")

        playerA.isMuted = true
        playerB.isMuted = true

        // Pre-load the opening clip into playerA so there is a frame on first appearance
        let item = AVPlayerItem(url: urlOpening)
        playerA.replaceCurrentItem(with: item)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self, item.status == .readyToPlay else { return }
            self.statusObservation = nil
            DispatchQueue.main.async { self.update(for: self.pendingStatus) }
        }
    }

    func update(for status: String) {
        pendingStatus = status
        removeEndObserver()

        switch status {
        case "Closed":
            load(url: urlOpening) { player in
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                player.pause()
            }

        case "Opening":
            load(url: urlOpening) { [weak self] player in
                guard let self else { return }
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    player.play()
                    self.endObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: player.currentItem,
                        queue: .main
                    ) { [weak self] _ in
                        self?.removeEndObserver()
                        player.pause()
                    }
                }
            }

        case "Open":
            load(url: urlOpen) { [weak self] player in
                guard let self else { return }
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    player.play()
                    self.endObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: player.currentItem,
                        queue: .main
                    ) { [weak self] _ in
                        self?.removeEndObserver()
                        player.pause()
                    }
                }
            }

        case "Closing":
            load(url: urlClosing) { [weak self] player in
                guard let self else { return }
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    player.play()
                    self.endObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: player.currentItem,
                        queue: .main
                    ) { [weak self] _ in
                        self?.removeEndObserver()
                        player.pause()
                    }
                }
            }

        default:
            load(url: urlOpening) { player in
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                player.pause()
            }
        }
    }

    /// Loads `url` into the background player. Once its first frame is ready,
    /// instantly swaps it to the foreground (no black gap) and calls `completion`.
    private func load(url: URL, completion: @escaping (AVPlayer) -> Void) {
        let incoming = backPlayer
        let item = AVPlayerItem(url: url)
        incoming.replaceCurrentItem(with: item)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self, item.status == .readyToPlay else { return }
            self.statusObservation = nil
            DispatchQueue.main.async {
                self.showA.toggle()          // back becomes front instantly
                self.backPlayer.pause()      // silence the now-background player
                completion(self.frontPlayer)
            }
        }
    }

    private func removeEndObserver() {
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var bleManager = BLEManager()
    @StateObject private var videoController = DoorVideoController()
    @State private var glowAmount: CGFloat = 0

    var body: some View {
        VStack(spacing: 40) {
            ZStack {
                DoorVideoView(player: videoController.playerB)
                    .opacity(videoController.showA ? 0 : 1)
                DoorVideoView(player: videoController.playerA)
                    .opacity(videoController.showA ? 1 : 0)
            }
            .frame(width: 280, height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                // Thick blurred stroke fades from solid at the edge to transparent inward.
                // A thin sharp stroke on top anchors the hard outer edge.
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(borderColor, lineWidth: 10 + glowAmount * 12)
                        .blur(radius: 1.5 + glowAmount * 2.5)
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(borderColor, lineWidth: 5)
                }
            }
            .onTapGesture {
                bleManager.sendOpenCommand()
            }
            .onChange(of: bleManager.status) { newStatus in
                updateGlow(for: newStatus)
            }
            .onAppear {
                updateGlow(for: bleManager.status)
            }

            Text("OpenSesame")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Fixed-height area so status changes never shift the video
            VStack(spacing: 12) {
                Text(bleManager.status)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(statusColor)
                    .padding(.horizontal)

                if bleManager.isBusy {
                    ProgressView("Operating door...")
                        .scaleEffect(1.5)
                } else {
                    ProgressView("Operating door...")
                        .scaleEffect(1.5)
                        .hidden()
                }
            }
            .frame(height: 90)
        }
        .padding()
        .onAppear {
            bleManager.startAutoConnect()
            videoController.update(for: bleManager.status)
        }
        .onChange(of: bleManager.status) { newStatus in
            videoController.update(for: newStatus)
        }
    }

    private var borderColor: Color {
        switch bleManager.status {
        case "Closed":  return .red
        case "Opening": return .blue
        case "Open":    return .green
        case "Closing": return .yellow
        default:        return .red
        }
    }

    // Only Opening and Closing pulse; Closed and Open are static.
    private func updateGlow(for status: String) {
        if status == "Opening" || status == "Closing" {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                glowAmount = 1
            }
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                glowAmount = 0
            }
        }
    }

    private var statusColor: Color {
        switch bleManager.status {
        case "Closed":  return .red
        case "Opening": return .blue
        case "Open":    return .green
        case "Closing": return .yellow
        default:        return .orange
        }
    }
}

// MARK: - BLE Manager (keep your existing one)
class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    @Published var status = "Not Found"
    @Published var isBusy = false
    
    private var centralManager: CBCentralManager!
    private var targetPeripheral: CBPeripheral?
    private var targetCharacteristic: CBCharacteristic?
    
    private let serviceUUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
    private let characteristicUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startAutoConnect() {
        status = "Scanning for DoorOpener..."
        if centralManager.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        }
    }
    
    func sendOpenCommand() {
        status = "Scanning for DoorOpener..."
        isBusy = true
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startAutoConnect()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if peripheral.name == "DoorOpener" {
            status = "Connecting..."
            centralManager.stopScan()
            
            targetPeripheral = peripheral
            targetPeripheral?.delegate = self
            centralManager.connect(peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "Connected"
        peripheral.discoverServices([serviceUUID])
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == serviceUUID {
                peripheral.discoverCharacteristics([characteristicUUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.uuid == characteristicUUID {
                targetCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                
                let data = "OPEN".data(using: .utf8)!
                peripheral.writeValue(data, for: characteristic, type: .withResponse)
                
                status = "Opening..."
                isBusy = true
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let value = characteristic.value, let received = String(data: value, encoding: .utf8) {
            DispatchQueue.main.async {
                self.status = received
                self.isBusy = (received == "Opening" || received == "Closing")
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if self.status == "Opening" || self.status == "Closing" {
                self.status = "Closed"
            }
            self.isBusy = false
        }
    }
}

#Preview {
    ContentView()
}
