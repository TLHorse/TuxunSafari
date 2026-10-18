import SwiftUI
import AppKit

@MainActor
final class Controller: ObservableObject {
    @Published var mode: String
    @Published var fixed: String
    @Published var minimum: String
    @Published var maximum: String
    @Published var offset: String
    @Published var running = false
    @Published var status = "未运行"
    @Published var log = "先在 Safari 当前标签页打开图寻对局，再点击启动。\n"
    @Published var error: String?
    private var process: Process?
    private var output: Pipe?
    private var pending = Data()
    private var stopping = false
    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        mode = d.string(forKey: "mode") ?? "fixed"
        fixed = d.string(forKey: "fixed") ?? "10"
        minimum = d.string(forKey: "minimum") ?? "8"
        maximum = d.string(forKey: "maximum") ?? "15"
        offset = d.string(forKey: "offset") ?? "100"
    }

    func save() {
        do { _ = try arguments(check: false) } catch { self.error = error.localizedDescription; return }
        for (key, value) in [("mode", mode), ("fixed", fixed), ("minimum", minimum), ("maximum", maximum), ("offset", offset)] {
            defaults.set(value, forKey: key)
        }
        status = running ? status : "默认设置已保存"
    }

    private func number(_ value: String, name: String, limit: Double) throws -> Double {
        guard let n = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)), n.isFinite, n >= 0, n <= limit else {
            throw NSError(domain: "Settings", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(name)应为 0–\(Int(limit)) 之间的数字。"])
        }
        return n
    }

    private func arguments(check: Bool) throws -> [String] {
        if check { return ["--check"] }
        let radius = try number(offset, name: "偏移半径", limit: 100000)
        var result = ["--offset-meters", String(radius)]
        if mode == "random" {
            let low = try number(minimum, name: "最短等待时间", limit: 3600)
            let high = try number(maximum, name: "最长等待时间", limit: 3600)
            guard low <= high else { throw NSError(domain: "Settings", code: 2, userInfo: [NSLocalizedDescriptionKey: "最短等待时间不能大于最长等待时间。"])}
            result += ["--random-delay", String(low), String(high)]
        } else {
            result += ["--delay", String(try number(fixed, name: "等待时间", limit: 3600))]
        }
        return result
    }

    private func prepare() throws -> URL {
        let fm = FileManager.default
        let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("TuxunSafari", isDirectory: true)
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        for file in ["tuxun.py", "runner.js", "config.json"] {
            guard let source = Bundle.main.resourceURL?.appendingPathComponent(file), fm.fileExists(atPath: source.path) else {
                throw NSError(domain: "Resources", code: 1, userInfo: [NSLocalizedDescriptionKey: "应用缺少 \(file)，请重新构建或下载完整应用。"])
            }
            let target = support.appendingPathComponent(file)
            if file == "config.json" && fm.fileExists(atPath: target.path) { continue }
            try Data(contentsOf: source).write(to: target, options: .atomic)
        }
        return support
    }

    private func python() throws -> URL {
        let candidates = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/Library/Frameworks/Python.framework/Versions/Current/bin/python3", "/usr/bin/python3"]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw NSError(domain: "Python", code: 1, userInfo: [NSLocalizedDescriptionKey: "未找到 Python 3，请先安装 Python 3。"])
        }
        return URL(fileURLWithPath: path)
    }

    func start(check: Bool = false) {
        guard !running else { return }
        do {
            let args = try arguments(check: check)
            let folder = try prepare()
            let p = Process(), pipe = Pipe()
            p.executableURL = try python()
            p.arguments = ["-u", folder.appendingPathComponent("tuxun.py").path] + args
            p.currentDirectoryURL = folder
            p.standardOutput = pipe
            p.standardError = pipe
            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONUNBUFFERED"] = "1"
            environment["PYTHONIOENCODING"] = "utf-8"
            p.environment = environment
            pending.removeAll(); stopping = false
            log = check ? "检查 Safari 连接，不会选点或提交。\n" : "正在连接 Safari…\n"
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil }
                Task { @MainActor [weak self] in self?.receive(data) }
            }
            p.terminationHandler = { [weak self] completed in
                let code = completed.terminationStatus
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.running = false
                    self.status = self.stopping ? "已停止" : (code == 0 ? "运行结束" : "运行出错，请查看日志")
                    self.process = nil
                }
            }
            process = p; output = pipe
            try p.run()
            running = true; status = check ? "正在检查连接" : "运行中"
            if !check { save() }
        } catch {
            output?.fileHandleForReading.readabilityHandler = nil
            process = nil; output = nil; running = false
            self.error = error.localizedDescription
        }
    }

    private func receive(_ data: Data) {
        pending.append(data)
        while let end = pending.firstIndex(of: 10) {
            let line = String(decoding: pending[..<end], as: UTF8.self)
            pending.removeSubrange(...end)
            log += line + "\n"
            if line.hasPrefix("第 ") { status = line }
        }
        if data.isEmpty && !pending.isEmpty {
            log += String(decoding: pending, as: UTF8.self)
            pending.removeAll()
        }
        if log.count > 150000 { log = String(log.suffix(100000)) }
    }

    func stop() {
        guard let p = process, p.isRunning else { return }
        stopping = true; status = "正在停止…"
        p.interrupt()
        // A pending Apple event can take up to 25 seconds. No further ticks run after termination.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak p] in
            guard let p, p.isRunning else { return }
            p.terminate()
            self?.status = "正在结束进程…"
        }
    }
    func shutdown() { if let p = process, p.isRunning { p.terminate() } }
    func openLogs() {
        if let folder = try? prepare() { NSWorkspace.shared.open(folder) }
    }
    func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(log, forType: .string)
    }
}

struct ContentView: View {
    @ObservedObject var controller: Controller
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(nsImage: NSImage(contentsOf: Bundle.main.url(forResource: "AppIcon", withExtension: "icns")!) ?? NSImage())
                    .resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("TuxunSafari").font(.title2.bold())
                    Text("Safari 图寻助手").foregroundStyle(.secondary)
                }
                Spacer()
                Label(controller.status, systemImage: controller.running ? "circle.fill" : "circle")
                    .foregroundStyle(controller.running ? .green : .secondary)
                    .font(.callout)
            }
            GroupBox("提交设置") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("等待模式", selection: $controller.mode) {
                        Text("固定等待").tag("fixed")
                        Text("随机等待").tag("random")
                    }.pickerStyle(.segmented)
                    HStack(spacing: 12) {
                        if controller.mode == "fixed" {
                            Text("等待时间")
                            TextField("10", text: $controller.fixed).frame(width: 85)
                            Text("秒")
                        } else {
                            Text("每轮随机等待")
                            TextField("8", text: $controller.minimum).frame(width: 85)
                            Text("至")
                            TextField("15", text: $controller.maximum).frame(width: 85)
                            Text("秒")
                        }
                        Spacer()
                    }
                    Divider()
                    HStack {
                        Text("最大偏移半径")
                        TextField("100", text: $controller.offset).frame(width: 85)
                        Text("米")
                        Spacer()
                        Text("0 表示不偏移").foregroundStyle(.secondary)
                    }
                    Text("每轮在半径内随机选点；随机等待模式会在区间内抽取一次时长。等待过长可能错过倒计时。")
                        .font(.caption).foregroundStyle(.secondary)
                }.textFieldStyle(.roundedBorder).padding(10)
            }.disabled(controller.running)
            HStack {
                Button("启动", systemImage: "play.fill") { controller.start() }
                    .buttonStyle(.borderedProminent).disabled(controller.running)
                Button("停止", systemImage: "stop.fill") { controller.stop() }
                    .disabled(!controller.running)
                Button("检查连接") { controller.start(check: true) }.disabled(controller.running)
                Spacer()
                Button("保存默认值") { controller.save() }.disabled(controller.running)
            }
            HStack {
                Text("运行日志").font(.headline)
                Spacer()
                Button("复制") { controller.copyLog() }
                Button("打开日志目录") { controller.openLogs() }.disabled(controller.running)
            }
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading) {
                        Text(controller.log).font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                .onChange(of: controller.log) { _ in reader.scrollTo("bottom", anchor: .bottom) }
            }
            Text("首次使用：Safari → 开发 → 允许来自 Apple 事件的 JavaScript。系统询问控制 Safari 时，请允许。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(minWidth: 740, minHeight: 650)
        .alert("无法运行", isPresented: Binding(get: { controller.error != nil }, set: { if !$0 { controller.error = nil } })) {
            Button("好", role: .cancel) { controller.error = nil }
        } message: { Text(controller.error ?? "") }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct TuxunSafariApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var controller = Controller()
    var body: some Scene {
        WindowGroup { ContentView(controller: controller)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in controller.shutdown() }
        }.defaultSize(width: 800, height: 740)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
