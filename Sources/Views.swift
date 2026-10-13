import AppKit

enum PanelUI {
    static func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = .labelColor
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    static func stack(_ views: [NSView], horizontal: Bool = false, spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = horizontal ? .horizontal : .vertical
        stack.alignment = horizontal ? .centerY : .leading
        stack.spacing = spacing
        return stack
    }
    static func symbol(_ name: String, description: String, size: CGFloat = 24) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        view.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        return view
    }
    static func surface(_ content: NSView, padding: CGFloat = 18) -> NSView {
        let view = SurfaceView()
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: padding),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -padding)
        ])
        return view
    }
    static func divider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}

final class SurfaceView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.controlBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        }
    }
}

final class DayTimelineView: NSView {
    private var buckets: [TimelineBucket] = []
    private var start = 0.0
    private var end = 0.0
    private var tracking: NSTrackingArea?
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 64) }

    func update(_ buckets: [TimelineBucket], from: Double, to: Double) {
        self.buckets = buckets
        start = from; end = to
        let online = buckets.reduce(0) { $0 + $1.online }
        let offline = buckets.reduce(0) { $0 + $1.offline }
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Linha do tempo do dia. \(duration(online)) com internet e \(duration(offline)) sem internet. Os demais períodos não foram observados.")
        toolTip = "Passe o cursor para consultar cada intervalo. Os dados são agregados em aproximadamente cinco minutos. Interrupções curtas têm marcador ampliado para ficarem visíveis."
        needsDisplay = true
    }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .mouseMoved], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }
    override func mouseMoved(with event: NSEvent) {
        guard !buckets.isEmpty, end > start, bounds.width > 0 else { return }
        let x = convert(event.locationInWindow, from: nil).x
        let index = min(buckets.count - 1, max(0, Int(x / bounds.width * CGFloat(buckets.count))))
        let width = (end - start) / Double(buckets.count)
        let bucket = buckets[index]
        let unknown = max(0, width - bucket.online - bucket.offline)
        let time = formatter.string(from: Date(timeIntervalSince1970: start + Double(index) * width))
        toolTip = "\(time): \(duration(bucket.online)) com internet, \(duration(bucket.offline)) sem internet, \(duration(unknown)) sem observação."
    }
    override func draw(_ dirtyRect: NSRect) {
        guard end > start, bounds.width > 0 else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let bar = NSRect(x: 0, y: 30, width: bounds.width, height: 28)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: bar, xRadius: 6, yRadius: 6).addClip()
            // Preenchimentos contíguos não devem criar linhas entre intervalos.
            NSGraphicsContext.current?.cgContext.setShouldAntialias(false)
            NSColor.quaternaryLabelColor.setFill()
            bar.fill()
            if !buckets.isEmpty {
                let width = bar.width / CGFloat(buckets.count)
                let seconds = (end - start) / Double(buckets.count)
                for (index, bucket) in buckets.enumerated() {
                    let x = CGFloat(index) * width
                    let onlineWidth = width * CGFloat(min(1, bucket.online / seconds))
                    if onlineWidth > 0 {
                        NSColor.systemGreen.setFill()
                        NSRect(x: x, y: bar.minY, width: onlineWidth, height: bar.height).fill()
                    }
                }
                // Desenhar por último impede que o intervalo seguinte cubra um marcador ampliado.
                for (index, bucket) in buckets.enumerated() where bucket.offline > 0 {
                    let x = CGFloat(index) * width
                    let onlineWidth = width * CGFloat(min(1, bucket.online / seconds))
                    let offlineWidth = width * CGFloat(max(0, min(1 - Double(onlineWidth / width), bucket.offline / seconds)))
                    let markerWidth = min(bar.width, max(3, offlineWidth))
                    let center = x + onlineWidth + offlineWidth / 2
                    let markerX = min(bar.maxX - markerWidth, max(bar.minX, center - markerWidth / 2))
                    NSColor.systemRed.setFill()
                    NSRect(x: markerX, y: bar.minY, width: markerWidth, height: bar.height).fill()
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            let date = Date(timeIntervalSince1970: start)
            let calendar = Calendar.current
            var ticks = [start]
            for hour in [6, 12, 18] {
                if let tick = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)?.timeIntervalSince1970, tick > start, tick < end {
                    ticks.append(tick)
                }
            }
            ticks.append(end)
            for tick in ticks {
                let text = formatter.string(from: Date(timeIntervalSince1970: tick)) as NSString
                let size = text.size(withAttributes: attributes)
                let x = bounds.width * CGFloat((tick - start) / (end - start))
                text.draw(at: NSPoint(x: min(bounds.width - size.width, max(0, x - size.width / 2)), y: 8), withAttributes: attributes)
            }
        }
    }
}

final class CompactController: NSViewController {
    let stateLabel = PanelUI.label("Aguardando verificação", size: 19, weight: .semibold)
    let interfaceLabel = PanelUI.label("Identificando a rede", size: 13)
    let availabilityLabel = PanelUI.label("Sem dados", size: 20, weight: .semibold)
    let onlineLabel = PanelUI.label("0s com internet", size: 13)
    let outageLabel = PanelUI.label("0 quedas", size: 13)
    let offlineLabel = PanelUI.label("0s sem internet", size: 13)
    let errorLabel = PanelUI.label("", size: 12)
    let icon = PanelUI.symbol("network", description: "Estado da conexão", size: 30)
    let testButton = NSButton(title: "Testar velocidade", target: nil, action: nil)
    let pauseButton = NSButton(title: "Pausar", target: nil, action: nil)
    var onOpen: () -> Void = {}
    var onTest: () -> Void = {}
    var onPause: () -> Void = {}
    var onOptions: () -> Void = {}
    var onAbout: () -> Void = {}

    override func loadView() {
        view = PanelBackground(frame: NSRect(x: 0, y: 0, width: 360, height: 350))
        let title = PanelUI.label("Conexão", size: 14, weight: .semibold)
        let options = NSButton(image: NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Opções")!, target: self, action: #selector(optionsPressed))
        options.bezelStyle = .inline
        options.toolTip = "Opções do aplicativo"
        let spacer = NSView()
        let about = NSButton(title: "Sobre", target: self, action: #selector(aboutPressed))
        about.bezelStyle = .inline
        about.toolTip = "Sobre o Conexão e versão instalada"
        let heading = PanelUI.stack([title, spacer, about, options], horizontal: true)
        interfaceLabel.textColor = .secondaryLabelColor
        let stateText = PanelUI.stack([stateLabel, interfaceLabel], spacing: 4)
        let status = PanelUI.stack([icon, stateText], horizontal: true, spacing: 12)
        let today = PanelUI.label("Disponibilidade hoje", size: 13, weight: .semibold)
        let availability = PanelUI.stack([today, availabilityLabel], horizontal: true)
        availability.distribution = .fill
        today.setContentCompressionResistancePriority(.required, for: .horizontal)
        today.setContentHuggingPriority(.defaultLow, for: .horizontal)
        today.widthAnchor.constraint(equalToConstant: 170).isActive = true
        today.maximumNumberOfLines = 1
        availabilityLabel.alignment = .right
        availabilityLabel.setContentHuggingPriority(.required, for: .horizontal)
        availabilityLabel.toolTip = "Disponibilidade no tempo observado hoje"
        availabilityLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        onlineLabel.textColor = .secondaryLabelColor
        offlineLabel.textColor = .secondaryLabelColor
        let interruptions = PanelUI.stack([outageLabel, offlineLabel], horizontal: true)
        interruptions.distribution = .fill
        outageLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        outageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        outageLabel.widthAnchor.constraint(equalToConstant: 112).isActive = true
        outageLabel.maximumNumberOfLines = 1
        offlineLabel.alignment = .right
        offlineLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        offlineLabel.setContentHuggingPriority(.required, for: .horizontal)
        for row in [availability, interruptions] {
            for field in row.arrangedSubviews { row.setVisibilityPriority(.mustHold, for: field) }
        }
        let stats = PanelUI.stack([availability, onlineLabel, PanelUI.divider(), interruptions], spacing: 8)
        let summary = PanelUI.surface(stats, padding: 14)
        for row in stats.arrangedSubviews { row.widthAnchor.constraint(equalTo: stats.widthAnchor).isActive = true }
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        let open = NSButton(title: "Abrir histórico", target: self, action: #selector(openPressed))
        open.bezelStyle = .rounded
        open.controlSize = .large
        open.bezelColor = .controlAccentColor
        open.keyEquivalent = "\r"
        testButton.target = self; testButton.action = #selector(testPressed); testButton.bezelStyle = .rounded
        pauseButton.target = self; pauseButton.action = #selector(pausePressed); pauseButton.bezelStyle = .rounded
        testButton.controlSize = .large; pauseButton.controlSize = .large
        let secondaryActions = PanelUI.stack([testButton, pauseButton], horizontal: true, spacing: 8)
        secondaryActions.distribution = .fillEqually
        let actions = PanelUI.stack([open, secondaryActions], spacing: 8)
        let root = PanelUI.stack([heading, status, summary, errorLabel, actions], spacing: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            root.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20),
            heading.widthAnchor.constraint(equalTo: root.widthAnchor),
            status.widthAnchor.constraint(equalTo: root.widthAnchor),
            summary.widthAnchor.constraint(equalTo: root.widthAnchor),
            errorLabel.widthAnchor.constraint(equalTo: root.widthAnchor),
            actions.widthAnchor.constraint(equalTo: root.widthAnchor),
            open.widthAnchor.constraint(equalTo: actions.widthAnchor),
            secondaryActions.widthAnchor.constraint(equalTo: actions.widthAnchor),
            testButton.widthAnchor.constraint(equalTo: pauseButton.widthAnchor),
            open.heightAnchor.constraint(equalToConstant: 32),
            testButton.heightAnchor.constraint(equalToConstant: 32),
            pauseButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }
    @objc private func openPressed() { onOpen() }
    @objc private func testPressed() { onTest() }
    @objc private func pausePressed() { onPause() }
    @objc private func optionsPressed() { onOptions() }
    @objc private func aboutPressed() { onAbout() }
}
