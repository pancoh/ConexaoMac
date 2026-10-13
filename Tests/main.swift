import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fatalError("FALHOU: \(name)") }
    checks += 1
    print("PASSOU: \(name)")
}
func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }
func reading(_ time: Double, _ state: Connectivity = .online, _ iface: String = "Wi-Fi|en0", _ received: UInt64 = 0, _ sent: UInt64 = 0) -> Reading {
    Reading(time: time, state: state, interface: iface, received: received, sent: sent, latency: 20)
}
let root = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let store = try Store(path: root.appendingPathComponent("test.sqlite").path)
let timeline = Timeline()
timeline.saveSpan = { store.save($0) }
timeline.startOutage = { store.beginOutage($0, $1) }
timeline.finishOutage = { store.endOutage($0, $1) }
timeline.event = { store.event($0, $1) }
timeline.observe(reading(100, .online, "Wi-Fi|en0", 4_500_000_000, 10))
let session1 = timeline.session
timeline.observe(reading(110, .online, "Wi-Fi|en0", 4_510_000_000, 1000010))
check(near(store.summary(from: 0, to: 200).received, 10_000_000), "tráfego acima de 4 GB")
check(near(store.summary(from: 105, to: 110).received, 5_000_000), "rateio do tráfego no limite do dia")
check(near(store.summary(from: 0, to: 200).averageDownloadUsage ?? -1, 8), "média de uso por tempo com tráfego medido")
timeline.observe(reading(120, .online, "Cabo|en5"))
check(timeline.session == session1, "troca de interface preserva sessão")
timeline.observe(reading(130, .offline, "Cabo|en5"))
timeline.observe(reading(140, .offline, "Cabo|en5"))
timeline.observe(reading(150, .online, "Cabo|en5"))
check(timeline.session != session1 && !timeline.session.isEmpty, "retorno da internet inicia nova sessão")
let summary = store.summary(from: 100, to: 150)
check(near(summary.online, 30) && near(summary.offline, 20), "tempos conectado e desconectado")
check(near(summary.availability ?? -1, 60), "disponibilidade exclui tempo não observado")
check(near(summary.wifi, 20) && near(summary.ethernet, 30), "tempo por interface")
check(store.outageStats(from: 100, to: 150, now: 150).0 == 1, "uma queda apesar de várias verificações")
check(near(store.outageStats(from: 135, to: 145, now: 150).1, 10), "queda atravessa limite do dia")
check(store.outageStats(from: 135, to: 145, now: 150).0 == 0, "queda anterior não conta como nova queda no dia")
timeline.observe(reading(160, .online, "Cabo|en5"))
timeline.suspend(at: 165, reason: "Repouso")
timeline.observe(reading(1000, .online, "Wi-Fi|en0"))
timeline.observe(reading(1010, .online, "Wi-Fi|en0", 100))
check(near(store.summary(from: 150, to: 1010).online, 25), "repouso excluído do tempo observado")
check(store.outageStats(from: 0, to: 2000, now: 1010).0 == 1, "repouso não gera queda")
timeline.observe(reading(1100, .offline))
check(near(store.summary(from: 1010, to: 1100).offline, 0), "lacuna não vira queda")
check(timeline.outageStart == nil, "início sem internet não inventa queda anterior")
timeline.observe(reading(1110, .online))
timeline.observe(reading(1120, .noNetwork))
timeline.observe(reading(1130, .noNetwork))
timeline.suspend(at: 1135, reason: "Encerramento")
let outages = store.outages(from: 1120, to: 1200, now: 1200)
check(outages.count == 1 && outages[0][3] == "1", "queda interrompida ao encerrar")
check(near(Double(outages[0][1]) ?? -1, 1135), "queda não extrapola encerramento")
store.saveSpeed(110, session1, "Wi-Fi", 100, 20)
store.saveSpeed(120, session1, "Cabo", 200, 40)
store.saveSpeed(1005, "outra", "Wi-Fi", 500, 50)
let speeds = store.speeds(from: 100, to: 150)
check(speeds.2 == 2 && near(speeds.0 ?? -1, 150) && near(speeds.1 ?? -1, 30), "média diária dos testes")
check(store.speeds(from: 0, to: 2000, session: session1).2 == 2, "testes filtrados por sessão")
try store.export(from: 100, to: 150, to: root.appendingPathComponent("dia.csv"))
let exported = try String(contentsOf: root.appendingPathComponent("dia.csv"), encoding: .utf8)
check(!exported.contains("4500000000"), "exportação contém deltas e não contadores acumulados")
check(FileManager.default.fileExists(atPath: root.appendingPathComponent("dia.testes.csv").path), "exportação inclui testes")
check(FileManager.default.fileExists(atPath: root.appendingPathComponent("dia.quedas.csv").path), "exportação inclui quedas")
store.beginOutage(2000, "Wi-Fi")
let reopened = try Store(path: store.path)
check(reopened.rows("SELECT COUNT(*) FROM outages WHERE end IS NULL")[0][0] == "0", "recuperação após encerramento inesperado")
store.prune(now: 2000)
check(store.lastError == nil && reopened.lastError == nil, "SQLite sem erros")

// Contadores ausentes não podem produzir tráfego zero nem saltos ao voltar.
let trafficStore = try Store(path: root.appendingPathComponent("traffic.sqlite").path)
let trafficTimeline = Timeline()
trafficTimeline.saveSpan = { trafficStore.save($0) }
trafficTimeline.observe(Reading(time: 0, state: .online, interface: "Múltipla", received: nil, sent: nil, latency: nil))
trafficTimeline.observe(Reading(time: 10, state: .online, interface: "Múltipla", received: nil, sent: nil, latency: nil))
let unavailable = trafficStore.summary(from: 0, to: 10)
check(unavailable.averageDownloadUsage == nil && unavailable.trafficSeconds == 0, "tráfego indisponível não é zero medido")
check(near(unavailable.online, 10), "ausência de tráfego preserva disponibilidade")
trafficTimeline.observe(reading(20, .online, "Wi-Fi|en0", 1_000_000_000, 2_000_000))
trafficTimeline.observe(reading(30, .online, "Wi-Fi|en0", 1_010_000_000, 3_000_000))
let partial = trafficStore.summary(from: 0, to: 30)
check(near(partial.received, 10_000_000) && near(partial.averageDownloadUsage ?? -1, 8), "média exclui tempo sem contadores")
check(near(partial.trafficCoverage ?? -1, 100.0 / 3), "cobertura informa medição parcial")
check(near(trafficStore.summary(from: 25, to: 30).trafficSeconds, 5), "cobertura respeita recorte de dia")
trafficTimeline.observe(reading(40, .online, "Wi-Fi|en0", 0, 0))
check(trafficStore.summary(from: 30, to: 40).averageDownloadUsage == nil, "reset de contador invalida intervalo")
trafficTimeline.observe(reading(50, .online, "Wi-Fi|en0", 0, 0))
check(trafficStore.summary(from: 40, to: 50).averageDownloadUsage == 0, "zero real permanece medição válida")
trafficTimeline.observe(Reading(time: 60, state: .online, interface: "Wi-Fi|en0", received: nil, sent: nil, latency: nil))
trafficTimeline.observe(reading(70, .online, "Wi-Fi|en0", 5_000_000_000, 5_000_000))
check(trafficStore.summary(from: 50, to: 70).averageDownloadUsage == nil, "retorno dos contadores não inventa delta")
trafficTimeline.suspend(at: 75, reason: "Pausa")
check(trafficStore.summary(from: 70, to: 75).averageDownloadUsage == nil, "pausa sem contador final não inventa tráfego")
try trafficStore.export(from: 0, to: 10, to: root.appendingPathComponent("indisponivel.csv"))
let unavailableCSV = try String(contentsOf: root.appendingPathComponent("indisponivel.csv"), encoding: .utf8)
check(unavailableCSV.contains("\"\",\"\",\"\""), "CSV preserva contadores indisponíveis como campos vazios")

let brazil = TimeZone(identifier: "America/Sao_Paulo")!
let utcDate = ISO8601DateFormatter().date(from: "2026-10-13T01:30:00Z")!
check(exportDayName(utcDate, timeZone: brazil) == "conexao-2026-10-12.csv", "nome do CSV usa dia local à noite")
check(exportDayName(utcDate, timeZone: TimeZone(secondsFromGMT: 0)!) == "conexao-2026-10-13.csv", "nome do CSV respeita fuso escolhido")

let errorStore = try Store(path: root.appendingPathComponent("errors.sqlite").path)
let partialRows = errorStore.rows("SELECT 1 UNION ALL SELECT abs(-9223372036854775808)")
check(partialRows.isEmpty && errorStore.lastError != nil, "erro ao percorrer SQLite descarta resultado parcial")
check(StoreError(description: "Falha de leitura").localizedDescription == "Falha de leitura", "erro preserva mensagem para a interface")
errorStore.write("DROP TABLE speeds")
var exportFailed = false
do { try errorStore.export(from: 0, to: 100, to: root.appendingPathComponent("erro.csv")) }
catch { exportFailed = true }
check(exportFailed, "exportação informa falha nas consultas dos arquivos adicionais")

let buckets = store.dayTimeline(from: 100, to: 150, count: 5)
check(buckets.count == 5 && near(buckets.reduce(0) { $0 + $1.online }, 30) && near(buckets.reduce(0) { $0 + $1.offline }, 20), "linha do tempo preserva duração por estado")
let clipped = store.dayTimeline(from: 105, to: 145, count: 3)
check(near(clipped.reduce(0) { $0 + $1.online }, 25) && near(clipped.reduce(0) { $0 + $1.offline }, 15), "linha do tempo recorta os limites do dia")
let gap = store.dayTimeline(from: 200, to: 900)
check(gap.count == 288 && gap.allSatisfy { $0.online == 0 && $0.offline == 0 }, "linha do tempo mantém lacunas sem inventar quedas")
check(store.dayTimeline(from: 100, to: 150, count: 10_000).count == 288, "linha do tempo limita memória a 288 intervalos")
check(store.dayTimeline(from: 100, to: 100).isEmpty && store.dayTimeline(from: 0, to: 10, count: 0).isEmpty, "linha do tempo rejeita intervalo inválido")
check(near(store.dayTimeline(from: 100, to: 150, count: 1)[0].offline, 20), "intervalo misto conserva queda curta")
check(store.dayTimeline(from: 0, to: 25 * 3600).count == 288, "dia de 25 horas mantém limite de memória")
// Regressões da auditoria: recuperação, histórico limitado e exportação protegida.
let recovery = try Store(path: root.appendingPathComponent("recovery.sqlite").path)
_ = recovery.rows("SELECT * FROM inexistente")
check(recovery.lastError != nil, "falha de consulta registra erro")
check(recovery.rows("SELECT 1") == [["1"]] && recovery.lastError == nil, "consulta bem-sucedida limpa erro anterior")
recovery.write("INSERT INTO inexistente VALUES(1)")
check(recovery.lastError != nil, "falha de gravação registra erro")
recovery.event(1, "Recuperado")
check(recovery.lastError == nil, "gravação bem-sucedida limpa erro anterior")
recovery.withErrorScope {
    _ = recovery.rows("SELECT * FROM inexistente")
    _ = recovery.rows("SELECT 1")
}
check(recovery.lastError != nil, "consulta posterior não esconde falha na mesma atualização")
recovery.withErrorScope { _ = recovery.rows("SELECT 1") }
check(recovery.lastError == nil, "nova atualização saudável limpa erro antigo")
var queryThrew = false
do { _ = try recovery.checkedRows("SELECT 1 UNION ALL SELECT abs(-9223372036854775808)") }
catch { queryThrew = true }
check(queryThrew, "consulta explícita propaga falha sem devolver resultados parciais")
let historyStore = try Store(path: root.appendingPathComponent("history.sqlite").path)
let emptyHistory = try historyStore.history(from: 0, to: 300, now: 300, section: .events)
check(emptyHistory.rows.isEmpty && !emptyHistory.hasMore, "histórico vazio é resultado válido")
for index in 0..<205 {
    let time = Double(index)
    historyStore.event(time, "Evento \(index)")
    historyStore.saveSpeed(time, "sessao-\(index)", "Cabo", 100, 20)
    historyStore.beginOutage(time, "Cabo")
    historyStore.endOutage(time + 0.1, false)
    historyStore.save(Span(start: time, end: time + 0.1, state: .online, interface: "Cabo", session: "sessao-\(index)", received: nil, sent: nil, latency: nil))
}
for section in [HistorySection.events, .outages, .speeds, .sessions] {
    let page = try historyStore.history(from: 0, to: 300, now: 300, section: section)
    check(page.rows.count == section.limit && page.hasMore && page.notice.contains("Há outros registros"), "limite informado na seção \(section)")
}
let exactPage = try historyStore.history(from: 5, to: 205, now: 300, section: .events)
check(exactPage.rows.count == 200 && !exactPage.hasMore, "limite exato não informa registros adicionais inexistentes")
historyStore.write("DROP TABLE events")
var historyThrew = false
do { _ = try historyStore.history(from: 0, to: 300, now: 300, section: .events) }
catch { historyThrew = true }
check(historyThrew, "falha no histórico não vira lista vazia")
for collision in 0..<3 {
    let target = root.appendingPathComponent("colisao-\(collision).csv")
    let targets = Store.exportTargets(for: target)
    try "CONTEUDO ORIGINAL".write(to: targets[collision], atomically: true, encoding: .utf8)
    var refused = false
    do { try recovery.export(from: 0, to: 300, to: target) }
    catch { refused = true }
    let untouched = try String(contentsOf: targets[collision], encoding: .utf8) == "CONTEUDO ORIGINAL"
    check(refused && untouched && targets.enumerated().allSatisfy { $0.offset == collision || !FileManager.default.fileExists(atPath: $0.element.path) }, "exportação preserva colisão no arquivo \(collision + 1)")
}
check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("erro.csv").path), "falha de consulta na exportação não deixa CSV parcial")
let auditFiles = try FileManager.default.contentsOfDirectory(atPath: root.path)
check(auditFiles.allSatisfy { !$0.hasPrefix(".conexao-export-") }, "exportação limpa os arquivos temporários")
let protectedMain = root.appendingPathComponent("criacao-exclusiva.csv")
let protectedSidecar = Store.exportTargets(for: protectedMain)[1]
let missingDestination = root.appendingPathComponent("destino-inexistente.csv").path
try FileManager.default.createSymbolicLink(atPath: protectedSidecar.path, withDestinationPath: missingDestination)
var exclusiveFailed = false
do { try recovery.export(from: 0, to: 300, to: protectedMain) }
catch { exclusiveFailed = true }
let symlinkDestination = try FileManager.default.destinationOfSymbolicLink(atPath: protectedSidecar.path)
check(exclusiveFailed && symlinkDestination == missingDestination && !FileManager.default.fileExists(atPath: protectedMain.path), "criação exclusiva protege destino e desfaz publicação parcial")
print("\(checks) verificações concluídas.")
