import AppKit
import Network
import Darwin

final class Monitor {
    let store: Store
    let timeline = Timeline()
    var changed: () -> Void = {}
    private let pathMonitor = NWPathMonitor()
    private var path: NWPath?
    private var timer: Timer?
    private var tasks: [URLSessionDataTask] = []
    private var generation = 0
    private var routeRevision = 0
    private var checking = false
    private var sleeping = false
    private var lastPrune = 0.0
    private var speedProcess: Process?
    private var lastSpeedAttempt = 0.0
    private var observers: [NSObjectProtocol] = []
    private let http: URLSession
    private(set) var state: Connectivity?
    private(set) var interface = "Identificando"
    private(set) var interfaceName = ""
    private(set) var latency: Double?
    private(set) var speedMessage = "Nenhum teste nesta execução"
    private(set) var speedRunning = false
    var paused = false
    var automaticSpeed: Bool {
        get { UserDefaults.standard.object(forKey: "automaticSpeed") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "automaticSpeed"); changed() }
    }

    init(store: Store) {
        self.store = store
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 1
        http = URLSession(configuration: config)
        timeline.saveSpan = { [weak store] in store?.save($0) }
        timeline.startOutage = { [weak store] in store?.beginOutage($0, $1) }
        timeline.finishOutage = { [weak store] in store?.endOutage($0, $1) }
        timeline.event = { [weak store] in store?.event($0, $1) }
    }

    func start() {
        store.prune(now: Date().timeIntervalSince1970)
        lastPrune = Date().timeIntervalSince1970
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            if let old = self.path, old.status != path.status || self.connection(old) != self.connection(path) { self.routeRevision += 1 }
            self.path = path
            self.check()
        }
        pathMonitor.start(queue: .main)
        timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.check() }
        timer?.tolerance = 1
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = true
            self?.suspend(reason: "Mac em repouso")
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = false
            self?.check()
        })
    }

    func suspend(reason: String) {
        generation += 1
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        checking = false
        if let process = speedProcess, process.isRunning { process.terminate() }
        timeline.suspend(at: Date().timeIntervalSince1970, reason: reason)
        state = nil
        latency = nil
        changed()
    }
    func togglePause() {
        paused.toggle()
        if paused { suspend(reason: "Monitoramento pausado") } else { check() }
        changed()
    }
    func stop() {
        suspend(reason: "Aplicativo encerrado")
        timer?.invalidate()
        pathMonitor.cancel()
        http.invalidateAndCancel()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    private func connection(_ path: NWPath) -> (String, String) {
        let wired = path.usesInterfaceType(.wiredEthernet)
        let wifi = path.usesInterfaceType(.wifi)
        if wired && wifi { return ("Múltipla", "") }
        let type: NWInterface.InterfaceType = wired ? .wiredEthernet : wifi ? .wifi : .other
        let name = path.availableInterfaces.first(where: { $0.type == type })?.name ?? ""
        return (wired ? "Cabo" : wifi ? "Wi-Fi" : "Outra / VPN", name)
    }

    private func counters(name: String) -> (UInt64, UInt64)? {
        guard !name.isEmpty else { return nil }
        // Contadores de 64 bits preservam transferências acima de 4 GB.
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(if_nametoindex(name))]
        guard mib[5] != 0 else { return nil }
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = Data(count: size)
        return buffer.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress, sysctl(&mib, UInt32(mib.count), base, &size, nil, 0) == 0 else { return nil }
            var offset = 0
            while offset + MemoryLayout<if_msghdr2>.size <= size {
                let message = base.advanced(by: offset).loadUnaligned(as: if_msghdr2.self)
                guard message.ifm_msglen > 0 else { break }
                if message.ifm_type == RTM_IFINFO2 && message.ifm_index == UInt16(mib[5]) {
                    return (message.ifm_data.ifi_ibytes, message.ifm_data.ifi_obytes)
                }
                offset += Int(message.ifm_msglen)
            }
            return nil
        }
    }

    func check() {
        guard !sleeping, !paused, !checking, let path else { return }
        let (kind, name) = connection(path)
        if path.status != .satisfied {
            accept(state: .noNetwork, kind: kind, name: name, latency: nil)
            return
        }
        checking = true
        let token = generation
        let started = ProcessInfo.processInfo.systemUptime
        var completed = 0
        var successful: [Double] = []
        let targets = ["https://www.apple.com/library/test/success.html", "https://www.gstatic.com/generate_204"]
        tasks = targets.enumerated().map { index, address in
            var request = URLRequest(url: URL(string: address)!)
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            return http.dataTask(with: request) { [weak self] data, response, error in
                let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
                let response = response as? HTTPURLResponse
                let valid = error == nil && (index == 1
                    ? response?.statusCode == 204 && response?.url?.host == "www.gstatic.com"
                    : response?.statusCode == 200 && response?.url?.host == "www.apple.com" && String(data: data ?? Data(), encoding: .utf8)?.contains("<BODY>Success</BODY>") == true)
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    completed += 1
                    if valid { successful.append(elapsed) }
                    guard completed == 2 else { return }
                    self.tasks.removeAll()
                    self.checking = false
                    // Uma mudança de rota durante a requisição invalida a atribuição de interface.
                    if let current = self.path, self.connection(current).1 != name || current.status != .satisfied { self.check(); return }
                    self.accept(state: successful.isEmpty ? .offline : .online, kind: kind, name: name, latency: successful.min())
                }
            }
        }
        tasks.forEach { $0.resume() }
    }

    private func accept(state: Connectivity, kind: String, name: String, latency: Double?) {
        let time = Date().timeIntervalSince1970
        let bytes = counters(name: name)
        self.state = state
        self.interface = kind
        self.interfaceName = name
        self.latency = latency
        timeline.observe(Reading(time: time, state: state, interface: kind + (name.isEmpty ? "" : "|" + name), received: bytes?.0, sent: bytes?.1, latency: latency))
        if time - lastPrune > 86400 { store.prune(now: time); lastPrune = time }
        changed()
        if ProcessInfo.processInfo.environment["CONEXAO_DIAGNOSTIC_SECONDS"] == nil && automaticSpeed && state == .online && time - lastSpeedAttempt >= 3600 && !(path?.isExpensive ?? true) && !(path?.isConstrained ?? true) {
            runSpeedTest()
        }
    }

    func runSpeedTest() {
        guard state == .online, !paused, !sleeping, !speedRunning else { return }
        let session = timeline.session
        let kind = interface
        let name = interfaceName
        let token = generation
        let revision = routeRevision
        lastSpeedAttempt = Date().timeIntervalSince1970
        speedRunning = true
        speedMessage = "Medindo download e upload (até 20 s)"
        changed()
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
        process.arguments = ["-c", "-M", "15"] + (name.isEmpty ? [] : ["-I", name])
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        speedProcess = process
        do { try process.run() } catch {
            speedProcess = nil; speedRunning = false; speedMessage = "Não foi possível iniciar o teste: \(error.localizedDescription)"; changed(); return
        }
        // Leitura fora da thread de interface, sem manter o processo após o teste.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let down = (json?["dl_throughput"] as? NSNumber)?.doubleValue
            let up = (json?["ul_throughput"] as? NSNumber)?.doubleValue
            DispatchQueue.main.async {
                guard let self else { return }
                self.speedProcess = nil
                self.speedRunning = false
                if token != self.generation || revision != self.routeRevision || self.timeline.session != session || self.interfaceName != name {
                    self.speedMessage = "Teste descartado: conexão ou monitoramento mudou"
                } else if process.terminationStatus == 0, let down, let up, down > 0, up > 0 {
                    self.store.saveSpeed(Date().timeIntervalSince1970, session, kind, down / 1_000_000, up / 1_000_000)
                    self.speedMessage = "Último teste: ↓ \(number(down / 1_000_000)) · ↑ \(number(up / 1_000_000)) Mbps"
                } else { self.speedMessage = "Teste sem resultado válido. Tente novamente." }
                self.changed()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak process] in
            if let process, process.isRunning { process.terminate() }
        }
    }
}
