import AppKit
import ServiceManagement
import UniformTypeIdentifiers
import Darwin

final class PanelBackground: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            dirtyRect.fill()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, NSTableViewDataSource, NSTableViewDelegate, NSPopoverDelegate {
    var store: Store!
    var monitor: Monitor!
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var datePicker: NSDatePicker?
    private var currentLabel: NSTextField?
    private var detailLabel: NSTextField?
    private var sessionLabel: NSTextField?
    private var speedLabel: NSTextField?
    private var cards: [NSTextField] = []
    private var table: NSTableView?
    private var section: NSSegmentedControl?
    private var historyNote: NSTextField?
    private var tableRows: [[String]] = []
    private var testButton: NSButton?
    private var autoButton: NSButton?
    private var availabilityLabel: NSTextField?
    private var timelineView: DayTimelineView?
    private var timelineCaption: NSTextField?
    private var stateIcon: NSImageView?
    private var detailsButton: NSButton?
    private var rootStack: NSStackView?
    private var popover: NSPopover?
    private var compactController: CompactController?
    private let clock: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "pt_BR"); f.dateFormat = "HH:mm:ss"; return f }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "br.local.ConexaoMac").filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty { NSApp.terminate(nil); return }
        do {
            let override = ProcessInfo.processInfo.environment["CONEXAO_DATA_DIR"]
            let folder = override.map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ConexaoMac")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            store = try Store(path: folder.appendingPathComponent("historico.sqlite").path)
        } catch { showError(error.localizedDescription); NSApp.terminate(nil); return }
        monitor = Monitor(store: store)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Conexão")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusPressed)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        monitor.changed = { [weak self] in self?.updateStatus() }
        monitor.start()
        if CommandLine.arguments.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if CommandLine.arguments.contains("--light") { NSApp.appearance = NSAppearance(named: .aqua) }
        if CommandLine.arguments.contains("--panel") { showPanel() }
        if CommandLine.arguments.contains("--small") { window?.setContentSize(NSSize(width: 860, height: 762)) }
        if CommandLine.arguments.contains("--details") { detailsButton?.state = .on; toggleDetails() }
        if CommandLine.arguments.contains("--compact") { showCompact() }
        if CommandLine.arguments.contains("--about") {
            DispatchQueue.main.async { self.showAbout() }
        }
        if let seconds = ProcessInfo.processInfo.environment["CONEXAO_DIAGNOSTIC_SECONDS"].flatMap(Double.init) {
            if let closeAfter = ProcessInfo.processInfo.environment["CONEXAO_DIAGNOSTIC_CLOSE_PANEL_AFTER"].flatMap(Double.init) {
                DispatchQueue.main.asyncAfter(deadline: .now() + closeAfter) { self.window?.performClose(nil) }
            }
            if ProcessInfo.processInfo.environment["CONEXAO_DIAGNOSTIC_SPEED"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self.monitor.runSpeedTest() }
            }
            if let imagePath = ProcessInfo.processInfo.environment["CONEXAO_DIAGNOSTIC_RENDER"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    if let view = self.popover?.contentViewController?.view ?? self.window?.contentView,
                       let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.effectiveAppearance.performAsCurrentDrawingAppearance {
                            view.cacheDisplay(in: view.bounds, to: bitmap)
                        }
                        let image = NSImage(size: view.bounds.size)
                        image.lockFocus()
                        NSColor.windowBackgroundColor.setFill()
                        view.bounds.fill()
                        bitmap.draw(in: view.bounds)
                        image.unlockFocus()
                        if let data = image.tiffRepresentation, let flattened = NSBitmapImageRep(data: data) {
                            try? flattened.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: imagePath))
                        }
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                print("estado=\(self.monitor.state?.rawValue ?? "unknown") interface=\(self.monitor.interface) latencia_ms=\(self.monitor.latency ?? -1) teste=\(self.monitor.speedMessage) erro_db=\(self.store.lastError ?? "nenhum") painel=\(self.window != nil) linha_do_tempo=\(self.timelineView != nil) linhas=\(self.tableRows.count)")
                fflush(stdout)
                NSApp.terminate(nil)
            }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { monitor?.stop() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return true }

    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    private func button(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        return b
    }
    private func stack(_ views: [NSView], horizontal: Bool = false, spacing: CGFloat = 10) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = horizontal ? .horizontal : .vertical
        s.alignment = horizontal ? .centerY : .leading
        s.spacing = spacing
        return s
    }
    private var statusText: String {
        if monitor.paused { return "Monitoramento pausado" }
        switch monitor.state {
        case .online: return "Internet disponível · \(monitor.interface)"
        case .offline: return "Rede conectada, sem acesso à internet"
        case .noNetwork: return "Sem conexão de rede"
        case nil: return "Aguardando verificação"
        }
    }

    private func updateStatus() {
        statusItem.button?.image = NSImage(systemSymbolName: monitor.paused ? "pause.circle" : monitor.state == .online ? "network" : "network.slash", accessibilityDescription: statusText)
        statusItem.button?.toolTip = statusText
        if window?.isVisible == true { refreshPanel() }
        if popover?.isShown == true { refreshCompact() }
    }
    private var stateColor: NSColor {
        if monitor.paused || monitor.state == nil { return .secondaryLabelColor }
        return monitor.state == .online ? .systemGreen : .systemRed
    }
    private var stateSymbol: String {
        if monitor.paused { return "pause.circle" }
        if monitor.state == nil { return "clock" }
        return monitor.state == .online ? "checkmark.circle" : "exclamationmark.circle"
    }
    @objc private func statusPressed() {
        if NSApp.currentEvent?.type == .rightMouseUp { showOptions(); return }
        if popover?.isShown == true { popover?.performClose(nil) } else { showCompact() }
    }
    private func showCompact() {
        guard let button = statusItem.button else { return }
        let controller = CompactController()
        controller.loadView()
        controller.onOpen = { [weak self] in self?.showPanel() }
        controller.onTest = { [weak self] in self?.testSpeed() }
        controller.onPause = { [weak self] in self?.togglePause() }
        controller.onOptions = { [weak self] in self?.showOptions() }
        controller.onAbout = { [weak self] in self?.showAbout() }
        let popover = NSPopover()
        popover.appearance = NSApp.appearance
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 360, height: 350)
        popover.contentViewController = controller
        popover.delegate = self
        compactController = controller
        self.popover = popover
        refreshCompact()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    func popoverDidClose(_ notification: Notification) {
        popover = nil
        compactController = nil
    }
    private func refreshCompact() {
        store.withErrorScope { refreshCompactContents() }
    }
    private func refreshCompactContents() {
        guard let controller = compactController else { return }
        let now = Date().timeIntervalSince1970
        let start = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let summary = store.summary(from: start, to: now)
        let outages = store.outageStats(from: start, to: now, now: now)
        let availability = summary.availability.map { number($0, digits: 2) + "%" } ?? "Sem dados"
        controller.stateLabel.stringValue = monitor.paused ? "Monitoramento pausado" : monitor.state == .online ? "Internet disponível" : monitor.state == .offline ? "Sem acesso à internet" : monitor.state == .noNetwork ? "Sem conexão de rede" : "Aguardando verificação"
        controller.interfaceLabel.stringValue = monitor.paused ? "Retome para verificar a conexão" : monitor.state == .noNetwork ? "Nenhuma rede conectada" : monitor.interface
        controller.icon.image = NSImage(systemSymbolName: stateSymbol, accessibilityDescription: statusText)
        controller.icon.contentTintColor = stateColor
        controller.availabilityLabel.stringValue = availability
        controller.availabilityLabel.setAccessibilityLabel("Disponibilidade hoje: \(availability)")
        controller.onlineLabel.stringValue = "\(duration(summary.online)) com internet"
        controller.outageLabel.stringValue = "\(outages.0) \(outages.0 == 1 ? "queda" : "quedas")"
        controller.offlineLabel.stringValue = "\(duration(summary.offline)) sem internet"
        controller.errorLabel.stringValue = store.lastError.map { "Erro no histórico: \($0)" } ?? ""
        controller.errorLabel.isHidden = store.lastError == nil
        popover?.contentSize = NSSize(width: 360, height: store.lastError == nil ? 350 : 420)
        controller.testButton.isEnabled = monitor.state == .online && !monitor.speedRunning
        controller.pauseButton.title = monitor.paused ? "Retomar" : "Pausar"
    }
    @objc private func showOptions() {
        popover?.performClose(nil)
        let menu = NSMenu()
        menu.delegate = self
        menuNeedsUpdate(menu)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: statusItem.button)
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        store.withErrorScope { populateMenu(menu) }
    }
    private func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let info = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        menu.addItem(info)
        let now = Date()
        let start = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        let summary = store.summary(from: start, to: now.timeIntervalSince1970)
        let outages = store.outageStats(from: start, to: now.timeIntervalSince1970, now: now.timeIntervalSince1970)
        menu.addItem(NSMenuItem(title: "Hoje: \(outages.0) queda(s) · \(duration(summary.offline)) sem internet", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        for (title, action) in [("Abrir histórico…", #selector(showPanel)), ("Testar velocidade agora", #selector(testSpeed)), (monitor.paused ? "Retomar monitoramento" : "Pausar monitoramento", #selector(togglePause))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if action == #selector(testSpeed) { item.isEnabled = monitor.state == .online && !monitor.speedRunning }
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        let automatic = NSMenuItem(title: "Teste automático a cada hora", action: #selector(toggleAuto), keyEquivalent: "")
        automatic.target = self; automatic.state = monitor.automaticSpeed ? .on : .off
        menu.addItem(automatic)
        let login = NSMenuItem(title: "Iniciar ao entrar no Mac", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self; login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "Sobre o Conexão…", action: #selector(showAbout), keyEquivalent: "")
        about.target = self; menu.addItem(about)
        let quit = NSMenuItem(title: "Encerrar Conexão", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
    }

    @objc private func showAbout() {
        popover?.performClose(nil)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Não informada"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let versionText = build.map { "Versão \(version) (build \($0))" } ?? "Versão \(version)"
        let alert = NSAlert()
        alert.messageText = "Conexão"
        alert.informativeText = "\(versionText)\n\nMonitoramento da conexão e histórico de disponibilidade no Mac.\nOs registros ficam neste computador."
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Fechar")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc func showPanel() {
        popover?.performClose(nil)
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 810), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "Conexão"
        w.minSize = NSSize(width: 860, height: 790)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = PanelBackground(frame: w.contentView!.frame)
        let content = w.contentView!
        let title = label("Conexão", size: 22, weight: .semibold)
        datePicker = NSDatePicker()
        datePicker!.datePickerStyle = .textFieldAndStepper
        datePicker!.datePickerElements = .yearMonthDay
        datePicker!.dateValue = Date()
        datePicker!.target = self; datePicker!.action = #selector(dateChanged)
        let previous = button("", action: #selector(previousDay))
        previous.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Dia anterior")
        previous.toolTip = "Dia anterior"
        let next = button("", action: #selector(nextDay))
        next.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Dia seguinte")
        next.toolTip = "Dia seguinte"
        let export = button("Exportar", action: #selector(exportDay))
        export.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Exportar dia")
        export.imagePosition = .imageLeading
        let spacer = NSView()
        let heading = stack([title, spacer, previous, datePicker!, next, button("Hoje", action: #selector(today)), export], horizontal: true, spacing: 8)

        stateIcon = PanelUI.symbol("checkmark.circle", description: "Estado atual", size: 32)
        currentLabel = label(statusText, size: 21, weight: .semibold)
        sessionLabel = label("", size: 12)
        sessionLabel!.textColor = .secondaryLabelColor
        let connection = stack([currentLabel!, sessionLabel!], spacing: 6)
        let live = stack([stateIcon!, connection], horizontal: true, spacing: 14)
        availabilityLabel = label("Sem dados", size: 34, weight: .medium)
        availabilityLabel!.font = .monospacedDigitSystemFont(ofSize: 34, weight: .medium)
        availabilityLabel!.alignment = .right
        let caption = label("Disponibilidade no dia", size: 12)
        caption.textColor = .secondaryLabelColor
        let availability = stack([availabilityLabel!, caption], spacing: 4)
        availability.alignment = .trailing
        let hero = stack([live, NSView(), availability], horizontal: true, spacing: 20)
        let heroSurface = PanelUI.surface(hero, padding: 20)

        cards = []
        let metrics = stack([], horizontal: true, spacing: 20)
        metrics.distribution = .fillEqually
        for name in ["Com internet", "Sem internet", "Quedas no dia", "Maior interrupção"] {
            let value = label("…", size: 24, weight: .medium)
            value.font = .monospacedDigitSystemFont(ofSize: 24, weight: .medium)
            cards.append(value)
            let nameLabel = label(name, size: 12)
            nameLabel.textColor = .secondaryLabelColor
            metrics.addArrangedSubview(stack([nameLabel, value], spacing: 5))
        }

        timelineView = DayTimelineView()
        let timelineTitle = label("Conexão ao longo do dia", size: 14, weight: .semibold)
        func legend(_ text: String, symbol: String, color: NSColor) -> NSView {
            let icon = PanelUI.symbol(symbol, description: text, size: 11)
            icon.contentTintColor = color
            let caption = label(text, size: 11)
            caption.textColor = .secondaryLabelColor
            return stack([icon, caption], horizontal: true, spacing: 4)
        }
        let legendRow = stack([
            legend("Com internet", symbol: "checkmark.circle.fill", color: .systemGreen),
            legend("Sem internet", symbol: "xmark.circle.fill", color: .systemRed),
            legend("Sem observação", symbol: "circle.dashed", color: .secondaryLabelColor)
        ], horizontal: true, spacing: 16)
        let timelineHeading = stack([timelineTitle, NSView(), legendRow], horizontal: true)
        timelineCaption = label("", size: 11)
        timelineCaption!.textColor = .secondaryLabelColor
        let timelineContent = stack([timelineHeading, timelineView!, timelineCaption!], spacing: 3)
        NSLayoutConstraint.activate([
            timelineHeading.widthAnchor.constraint(equalTo: timelineContent.widthAnchor),
            timelineView!.widthAnchor.constraint(equalTo: timelineContent.widthAnchor),
            timelineView!.heightAnchor.constraint(equalToConstant: 64),
            timelineCaption!.widthAnchor.constraint(equalTo: timelineContent.widthAnchor)
        ])
        let timelineSurface = PanelUI.surface(timelineContent, padding: 16)

        let speedMetrics = stack([], horizontal: true, spacing: 30)
        for name in ["Download médio", "Upload médio"] {
            let value = label("Sem testes", size: 20, weight: .medium)
            value.font = .monospacedDigitSystemFont(ofSize: 20, weight: .medium)
            cards.append(value)
            let caption = label(name + " dos testes", size: 11)
            caption.textColor = .secondaryLabelColor
            speedMetrics.addArrangedSubview(stack([caption, value], spacing: 4))
        }
        testButton = button("Testar velocidade", action: #selector(testSpeed))
        testButton!.image = NSImage(systemSymbolName: "speedometer", accessibilityDescription: "Testar velocidade")
        testButton!.imagePosition = .imageLeading
        autoButton = NSButton(checkboxWithTitle: "Teste automático a cada hora", target: self, action: #selector(toggleAuto))
        autoButton!.font = .systemFont(ofSize: 11)
        let speedControls = stack([testButton!, autoButton!], spacing: 6)
        let speedRow = stack([speedMetrics, NSView(), speedControls], horizontal: true)
        speedLabel = label("", size: 11)
        speedLabel!.textColor = .secondaryLabelColor
        let speedBlock = stack([speedRow, speedLabel!], spacing: 6)
        speedRow.widthAnchor.constraint(equalTo: speedBlock.widthAnchor).isActive = true

        detailsButton = button("Detalhes de tráfego e observação", action: #selector(toggleDetails))
        detailsButton!.bezelStyle = .inline
        detailsButton!.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Expandir detalhes")
        detailsButton!.imagePosition = .imageLeading
        detailsButton!.setButtonType(.pushOnPushOff)
        detailLabel = label("", size: 12)
        detailLabel!.textColor = .secondaryLabelColor
        detailLabel!.isHidden = true

        section = NSSegmentedControl(labels: ["Quedas", "Sessões", "Testes", "Eventos"], trackingMode: .selectOne, target: self, action: #selector(sectionChanged))
        section!.selectedSegment = 0
        let historyHeading = stack([label("Histórico do dia", size: 14, weight: .semibold), NSView(), section!], horizontal: true)
        table = NSTableView()
        table!.usesAlternatingRowBackgroundColors = true
        table!.rowHeight = 30
        table!.dataSource = self; table!.delegate = self
        for (i, width) in [170.0, 470.0, 230.0].enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c\(i)"))
            column.width = width; column.minWidth = 100
            table!.addTableColumn(column)
        }
        table!.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.documentView = table
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 116).isActive = true
        let note = label("Histórico local de 90 dias. Repouso e períodos sem observação ficam fora da disponibilidade.", size: 11)
        note.textColor = .secondaryLabelColor
        historyNote = note
        let separator = PanelUI.divider()
        let root = stack([heading, heroSurface, metrics, timelineSurface, speedBlock, detailsButton!, detailLabel!, separator, historyHeading, scroll, note], spacing: 14)
        root.detachesHiddenViews = true
        rootStack = root
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        var constraints = [
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18)
        ]
        for view in [heading, heroSurface, metrics, timelineSurface, speedBlock, detailLabel!, separator, historyHeading, scroll, note] {
            constraints.append(view.widthAnchor.constraint(equalTo: root.widthAnchor))
        }
        NSLayoutConstraint.activate(constraints)
        window = w
        refreshPanel()
        w.center(); w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleDetails() {
        guard let detailLabel, let detailsButton else { return }
        detailLabel.isHidden = detailsButton.state != .on
        rootStack?.spacing = detailLabel.isHidden ? 14 : 10
        let symbol = detailLabel.isHidden ? "chevron.right" : "chevron.down"
        detailsButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: detailLabel.isHidden ? "Expandir detalhes" : "Recolher detalhes")
        detailsButton.setAccessibilityValue(detailLabel.isHidden ? "Recolhido" : "Expandido")
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil; table = nil; datePicker = nil; currentLabel = nil; historyNote = nil
        detailLabel = nil; sessionLabel = nil; speedLabel = nil; section = nil
        availabilityLabel = nil; timelineView = nil; timelineCaption = nil; stateIcon = nil
        detailsButton = nil; rootStack = nil
        cards.removeAll(); tableRows.removeAll(); testButton = nil; autoButton = nil
        // Após o fechamento, devolve páginas livres sem afetar objetos em uso.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window == nil else { return }
            malloc_zone_pressure_relief(nil, 0)
        }
    }
    private func dayBounds() -> (Double, Double) {
        let start = Calendar.current.startOfDay(for: datePicker?.dateValue ?? Date())
        return (start.timeIntervalSince1970, Calendar.current.date(byAdding: .day, value: 1, to: start)!.timeIntervalSince1970)
    }
    private func time(_ value: String) -> String { Double(value).map { clock.string(from: Date(timeIntervalSince1970: $0)) } ?? "Em andamento" }
    private func speedText(_ down: Double?, _ up: Double?, _ count: Int) -> String {
        guard let down, let up else { return "Sem testes" }
        return "↓ \(number(down)) · ↑ \(number(up)) Mbps (\(count) teste(s))"
    }

    private func refreshPanel() {
        store.withErrorScope { refreshPanelContents() }
    }
    private func refreshPanelContents() {
        guard window != nil else { return }
        let (start, end) = dayBounds()
        let now = Date().timeIntervalSince1970
        let summary = store.summary(from: start, to: end)
        let speeds = store.speeds(from: start, to: end)
        let outages = store.outageStats(from: start, to: end, now: now)
        let elapsed = max(0, min(end, now) - start)
        let unknown = max(0, elapsed - summary.online - summary.offline)
        let downloadText: String = speeds.0.map { number($0) + " Mbps" } ?? "Sem testes"
        let uploadText: String = speeds.1.map { number($0) + " Mbps" } ?? "Sem testes"
        let availabilityText: String = summary.availability.map { number($0, digits: 2) + "%" } ?? "Sem dados"
        let values: [String] = [duration(summary.online), duration(summary.offline), "\(outages.0)", duration(outages.1), downloadText, uploadText]
        availabilityLabel?.stringValue = availabilityText
        stateIcon?.image = NSImage(systemSymbolName: stateSymbol, accessibilityDescription: statusText)
        stateIcon?.contentTintColor = stateColor
        timelineView?.update(store.dayTimeline(from: start, to: end), from: start, to: end)
        timelineCaption?.stringValue = "Horário local. Intervalos de aproximadamente 5 min. Sem observação: \(duration(unknown))."
        for (label, value) in zip(cards, values) { label.stringValue = value }
        currentLabel?.stringValue = statusText
        let received = ByteCountFormatter.string(fromByteCount: Int64(summary.received), countStyle: .decimal)
        let sent = ByteCountFormatter.string(fromByteCount: Int64(summary.sent), countStyle: .decimal)
        let traffic = summary.trafficSeconds > 0 ? "↓ \(received) / ↑ \(sent)" : "Indisponível"
        let usage: String
        if let down = summary.averageDownloadUsage, let up = summary.averageUploadUsage {
            usage = "↓ \(number(down)) / ↑ \(number(up)) Mbps"
        } else { usage = "Indisponível" }
        let coverage = summary.trafficCoverage.map { number($0, digits: 1) + "% do tempo com internet" } ?? "Sem observação conectada"
        detailLabel?.stringValue = "Wi-Fi: \(duration(summary.wifi)) · Cabo: \(duration(summary.ethernet)) · Tráfego medido: \(traffic)\nUso médio medido: \(usage) · Cobertura: \(coverage)\nResposta HTTP média: \(summary.latency.map { number($0, digits: 0) + " ms" } ?? "Sem dados")"
        if !monitor.timeline.session.isEmpty {
            let id = monitor.timeline.session
            let current = store.summary(from: 0, to: now + 1, session: id)
            let sessionSpeeds = store.speeds(from: 0, to: now + 1, session: id)
            sessionLabel?.stringValue = "Sessão atual: \(duration(current.online)) com internet · \(speedText(sessionSpeeds.0, sessionSpeeds.1, sessionSpeeds.2))"
        } else { sessionLabel?.stringValue = "Sem sessão conectada em andamento" }
        testButton?.isEnabled = monitor.state == .online && !monitor.speedRunning
        autoButton?.state = monitor.automaticSpeed ? .on : .off
        loadRows(start: start, end: end, now: now)
        speedLabel?.stringValue = store.lastError.map { "Erro no histórico: \($0)" } ?? monitor.speedMessage
    }

    private func loadRows(start: Double, end: Double, now: Double) {
        let selected = section?.selectedSegment ?? 0
        let headings: [[String]] = [["Início / fim", "Conexão", "Duração observada"], ["Início / fim", "Conexão e velocidade média", "Tempo com internet"], ["Horário", "Conexão", "Download / upload"], ["Horário", "Registro", ""]]
        for (column, title) in zip(table!.tableColumns, headings[selected]) { column.title = title }
        do {
            let page = try store.history(from: start, to: end, now: now, section: HistorySection(rawValue: selected) ?? .events)
            switch selected {
            case 0:
                tableRows = page.rows.map { row in
                    let seconds = max(0, (Double(row[1]) ?? now) - max(start, Double(row[0]) ?? start))
                    return ["\(time(row[0])) / \(time(row[1]))", row[2].replacingOccurrences(of: "|", with: " · ") + (row[3] == "1" ? " (observação interrompida)" : ""), duration(seconds)]
                }
            case 1:
                tableRows = try page.rows.map { row in
                    let result = try store.checkedRows("SELECT AVG(download),AVG(upload),COUNT(*) FROM speeds WHERE time>=? AND time<? AND session=?", [start, end, row[4]]).first ?? ["", "", "0"]
                    return ["\(time(row[0])) / \(time(row[1]))", row[2].replacingOccurrences(of: "|", with: " · ") + " · " + speedText(Double(result[0]), Double(result[1]), Int(result[2]) ?? 0), duration(Double(row[3]) ?? 0)]
                }
            case 2:
                tableRows = page.rows.map { [time($0[0]), $0[1], "↓ \(number(Double($0[2]) ?? 0)) / ↑ \(number(Double($0[3]) ?? 0)) Mbps"] }
            default:
                tableRows = page.rows.map { [time($0[0]), $0[1], ""] }
            }
            historyNote?.stringValue = page.notice + " Histórico local de 90 dias. Repouso e períodos sem observação ficam fora da disponibilidade."
            historyNote?.textColor = .secondaryLabelColor
            if tableRows.isEmpty { tableRows = [["", "Nenhum registro neste dia", ""]] }
        } catch {
            tableRows = [["", "Não foi possível consultar o histórico", ""]]
            historyNote?.stringValue = "Erro na consulta: \(error.localizedDescription). A próxima atualização tentará novamente."
            historyNote?.textColor = .systemRed
        }
        table?.reloadData()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { tableRows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn, let index = tableView.tableColumns.firstIndex(of: column), row < tableRows.count else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let field = tableView.makeView(withIdentifier: id, owner: self) as? NSTextField ?? label("")
        field.identifier = id
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.stringValue = tableRows[row][index]
        field.toolTip = field.stringValue
        return field
    }

    @objc private func dateChanged() { refreshPanel() }
    @objc private func sectionChanged() { refreshPanel() }
    @objc private func previousDay() { datePicker?.dateValue = Calendar.current.date(byAdding: .day, value: -1, to: datePicker!.dateValue)!; refreshPanel() }
    @objc private func nextDay() { datePicker?.dateValue = Calendar.current.date(byAdding: .day, value: 1, to: datePicker!.dateValue)!; refreshPanel() }
    @objc private func today() { datePicker?.dateValue = Date(); refreshPanel() }
    @objc private func testSpeed() { monitor.runSpeedTest() }
    @objc private func togglePause() { monitor.togglePause() }
    @objc private func toggleAuto() { monitor.automaticSpeed.toggle() }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { showError("Não foi possível alterar a inicialização automática. \(error.localizedDescription)") }
    }
    @objc private func exportDay() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = exportDayName(datePicker?.dateValue ?? Date())
        panel.message = "Exporta três arquivos CSV. Escolha um nome novo: arquivos existentes serão preservados."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let (start, end) = dayBounds()
        do { try store.export(from: start, to: end, to: url) } catch { showError(error.localizedDescription) }
    }
    private func showError(_ message: String) {
        let alert = NSAlert(); alert.messageText = "Conexão"; alert.informativeText = message
        alert.alertStyle = .warning; alert.runModal()
    }
}
