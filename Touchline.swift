import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox
import ServiceManagement

// MARK: - App metadata & external links

enum AppInfo {
    static let name = "Touchline"
    static let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    static let author = "Angryrou"
    static let repoURL = URL(string: "https://github.com/Angryrou/touchline")!
    static let releasesURL = URL(string: "https://github.com/Angryrou/touchline/releases/latest")!
    static let latestAPIURL = URL(string: "https://api.github.com/repos/Angryrou/touchline/releases/latest")!
}

// MARK: - Local timezone (auto-detected, never hardcoded)

enum LocalTZ {
    static var abbreviation: String { TimeZone.current.abbreviation() ?? TimeZone.current.identifier }

    static var offsetString: String {
        let secs = TimeZone.current.secondsFromGMT()
        let sign = secs < 0 ? "-" : "+"
        let h = abs(secs) / 3600, m = (abs(secs) % 3600) / 60
        return m == 0 ? "UTC\(sign)\(h)" : String(format: "UTC%@%d:%02d", sign, h, m)
    }

    /// e.g. "PDT · UTC-7"
    static var label: String { "\(abbreviation) · \(offsetString)" }
}

// MARK: - ESPN JSON models (paths verified against site.api.espn.com .../soccer/fifa.world/scoreboard)

struct Scoreboard: Decodable { let events: [Event] }

struct Event: Decodable {
    let id: String
    let date: String
    let shortName: String?
    let name: String?
    let competitions: [Competition]
}

struct Competition: Decodable {
    let status: Status
    let competitors: [Competitor]
}

struct Status: Decodable {
    let displayClock: String?
    let period: Int?
    let type: StatusType
}

struct StatusType: Decodable {
    let state: String          // "pre" | "in" | "post"
    let completed: Bool
    let detail: String?
    let shortDetail: String?   // "FT", "HT", "67'", kickoff time, etc.
    let description: String?
}

struct Competitor: Decodable {
    let homeAway: String       // "home" | "away"
    let score: String?         // ESPN usually sends String; tolerate Int/Double too
    let team: Team

    enum CodingKeys: String, CodingKey { case homeAway, score, team }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        homeAway = try c.decode(String.self, forKey: .homeAway)
        team = try c.decode(Team.self, forKey: .team)
        if let s = try? c.decode(String.self, forKey: .score) { score = s }
        else if let i = try? c.decode(Int.self, forKey: .score) { score = String(i) }
        else if let d = try? c.decode(Double.self, forKey: .score) { score = String(Int(d)) }
        else { score = nil }
    }
}

struct Team: Decodable {
    let abbreviation: String?
    let displayName: String?
    let shortDisplayName: String?
    let logo: String?          // national-team flag PNG, e.g. .../countries/500/esp.png
}

// MARK: - Flattened view model

enum MatchState: String { case pre, live = "in", post }

struct Side: Identifiable {
    let abbr: String           // "ESP"
    let englishName: String    // "Spain" (for the English Google search)
    let chineseName: String    // "西班牙" (for the Chinese Google search)
    let flagURL: URL?
    let score: String

    var id: String { abbr }

    // Google search URLs for the national team, language-targeted.
    var englishSearchURL: URL? {
        Self.search(query: "\(englishName) national football team", hl: "en")
    }
    var chineseSearchURL: URL? {
        Self.search(query: "\(chineseName)国家足球队", hl: "zh-CN")
    }

    private static func search(query: String, hl: String) -> URL? {
        var c = URLComponents(string: "https://www.google.com/search")!
        c.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "hl", value: hl)]
        return c.url
    }
}

struct Match: Identifiable {
    let id: String
    let home: Side
    let away: Side
    let state: MatchState
    let detail: String
    let date: Date?

    var homeWins: Bool { (Int(home.score) ?? 0) > (Int(away.score) ?? 0) }
    var awayWins: Bool { (Int(away.score) ?? 0) > (Int(home.score) ?? 0) }
    var hasScore: Bool { state != .pre }
}

// MARK: - Date helpers

enum ESPNDate {
    static let parsers: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mmX", "yyyy-MM-dd'T'HH:mm:ssX"].map { fmt in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = fmt
            return f
        }
    }()

    static func parse(_ s: String) -> Date? {
        for p in parsers { if let d = p.date(from: s) { return d } }
        return nil
    }

    static let kickoff: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "EEE HH:mm"
        return f
    }()

    // yyyyMMdd in the user's local calendar — used for the ?dates= query param.
    static let dayKeyFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    static func dateKey(_ d: Date) -> String { dayKeyFmt.string(from: d) }
}

// MARK: - Tournament calendar (verified from leagues[0].calendar)

enum Tournament {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    static let days: [Date] = {
        let cal = calendar
        guard
            let start = cal.date(from: DateComponents(year: 2026, month: 6, day: 11)),
            let end = cal.date(from: DateComponents(year: 2026, month: 7, day: 19))
        else { return [] }
        var out: [Date] = []
        var d = start
        while d <= end {
            out.append(d)
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return out
    }()

    // (month, dayStart, dayEnd, label) inclusive ranges
    private static let rounds: [(Int, Int, Int, String)] = [
        (6, 11, 27, "Group Stage"),
        (6, 28, 30, "Round of 32"),
        (7, 1, 3, "Round of 32"),
        (7, 4, 7, "Round of 16"),
        (7, 9, 11, "Quarterfinals"),
        (7, 14, 15, "Semifinals"),
        (7, 18, 18, "3rd-Place Match"),
        (7, 19, 19, "Final"),
    ]

    static func round(for day: Date) -> String? {
        let c = calendar.dateComponents([.month, .day], from: day)
        guard let m = c.month, let d = c.day else { return nil }
        for (rm, ds, de, label) in rounds where rm == m && d >= ds && d <= de { return label }
        return nil
    }
}

// MARK: - Chinese names for the 48 finalists (keyed by ESPN abbreviation)

enum CN {
    static let names: [String: String] = [
        "ALG": "阿尔及利亚", "ARG": "阿根廷", "AUS": "澳大利亚", "AUT": "奥地利",
        "BEL": "比利时", "BIH": "波黑", "BRA": "巴西", "CAN": "加拿大",
        "CIV": "科特迪瓦", "COD": "刚果(金)", "COL": "哥伦比亚", "CPV": "佛得角",
        "CRO": "克罗地亚", "CUW": "库拉索", "CZE": "捷克", "ECU": "厄瓜多尔",
        "EGY": "埃及", "ENG": "英格兰", "ESP": "西班牙", "FRA": "法国",
        "GER": "德国", "GHA": "加纳", "HAI": "海地", "IRN": "伊朗",
        "IRQ": "伊拉克", "JOR": "约旦", "JPN": "日本", "KOR": "韩国",
        "KSA": "沙特阿拉伯", "MAR": "摩洛哥", "MEX": "墨西哥", "NED": "荷兰",
        "NOR": "挪威", "NZL": "新西兰", "PAN": "巴拿马", "PAR": "巴拉圭",
        "POR": "葡萄牙", "QAT": "卡塔尔", "RSA": "南非", "SCO": "苏格兰",
        "SEN": "塞内加尔", "SUI": "瑞士", "SWE": "瑞典", "TUN": "突尼斯",
        "TUR": "土耳其", "URU": "乌拉圭", "USA": "美国", "UZB": "乌兹别克斯坦",
    ]

    static func name(abbr: String, fallback: String) -> String {
        names[abbr] ?? fallback
    }
}

// MARK: - Launch at login (SMAppService, macOS 13+)

@MainActor
final class LoginItem: ObservableObject {
    @Published var enabled: Bool = false

    init() { refresh() }

    func refresh() { enabled = SMAppService.mainApp.status == .enabled }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("LoginItem toggle failed: \(error)")
        }
        refresh()
    }
}

// MARK: - Update checker (queries GitHub releases API)

@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle, checking, upToDate, available(String), failed(String)
    }
    @Published var state: State = .idle

    func check() {
        state = .checking
        Task {
            do {
                var req = URLRequest(url: AppInfo.latestAPIURL)
                req.timeoutInterval = 15
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 404 {
                    state = .upToDate   // no releases yet
                    return
                }
                struct Release: Decodable { let tag_name: String }
                let release = try JSONDecoder().decode(Release.self, from: data)
                let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                if Self.isNewer(latest, than: AppInfo.version) {
                    state = .available(latest)
                } else {
                    state = .upToDate
                }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    // Numeric semver compare ("1.2.0" > "1.10.0" handled correctly).
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

// MARK: - Model

@MainActor
final class Model: ObservableObject {
    @Published var panelMatches: [Match] = []     // matches for the selected date
    @Published var liveMatches: [Match] = []       // today's matches (drives title + cadence)
    @Published var selectedDate: Date = Date()
    @Published var menuTitle: String = "⚽ Touchline"
    @Published var lastUpdated: Date?
    @Published var errorText: String?
    @Published var loading = false
    @Published private(set) var starred: Set<String> = []

    private var loopTask: Task<Void, Never>?
    private var wake: CheckedContinuation<Void, Never>?
    private let base = "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard"
    private let starKey = "starredGames"

    // Per-game completion tracking: when a game flips to .post, the group standings
    // and downstream knockout fixtures settle, so we do a few accelerated refreshes.
    private var lastStates: [String: MatchState] = [:]
    private var settleRefreshesLeft = 0

    var fastActive: Bool {
        liveMatches.contains { $0.state == .live && starred.contains($0.id) }
    }

    init() {
        if let saved = UserDefaults.standard.array(forKey: starKey) as? [String] {
            starred = Set(saved)
        }
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in await self?.loop() }
    }

    func refreshNow() { wake?.resume(); wake = nil }

    func isStarred(_ id: String) -> Bool { starred.contains(id) }

    func toggleStar(_ id: String) {
        if starred.contains(id) { starred.remove(id) } else { starred.insert(id) }
        UserDefaults.standard.set(Array(starred), forKey: starKey)
        refreshNow()    // re-evaluate cadence immediately
    }

    func selectDate(_ d: Date) {
        guard !Tournament.calendar.isDate(d, inSameDayAs: selectedDate) else { return }
        selectedDate = d
        panelMatches = []
        refreshNow()
    }

    func jumpToToday() { selectDate(Date()) }

    private func loop() async {
        while !Task.isCancelled {
            await fetchOnce()
            let seconds = nextInterval()
            await withTaskGroup(of: Void.self) { group in
                group.addTask { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
                group.addTask { await withCheckedContinuation { c in Task { @MainActor in self.wake = c } } }
                await group.next()
                group.cancelAll()
            }
            wake = nil
        }
    }

    private func nextInterval() -> Double {
        // A game just finished: refresh quickly to pick up settled standings & fixtures.
        if settleRefreshesLeft > 0 { return 20 }
        return fastActive ? 12 : 60
    }

    private func fetchOnce() async {
        loading = true
        defer { loading = false }
        do {
            let panel = try await fetchLocalDay(selectedDate)
            self.panelMatches = panel
            let todayMatches: [Match]
            if Tournament.calendar.isDateInToday(selectedDate) {
                todayMatches = panel
            } else {
                todayMatches = (try? await fetchLocalDay(Date())) ?? liveMatches
            }
            detectCompletions(in: todayMatches)
            self.liveMatches = todayMatches
            self.menuTitle = Self.title(for: self.liveMatches, starred: starred, fast: fastActive)
            self.lastUpdated = Date()
            self.errorText = nil
        } catch {
            self.errorText = error.localizedDescription
            if liveMatches.isEmpty { self.menuTitle = "⚽ Touchline ⚠︎" }
        }
    }

    // Compare each game's state to the previous poll. A live→post transition means a
    // result just settled, so schedule a short burst of faster refreshes to pull in the
    // updated group table and any newly-determined knockout matchups.
    private func detectCompletions(in matches: [Match]) {
        var justFinished = false
        for m in matches {
            if let prev = lastStates[m.id], prev != .post, m.state == .post {
                justFinished = true
            }
            lastStates[m.id] = m.state
        }
        if justFinished { settleRefreshesLeft = 3 }
        else if settleRefreshesLeft > 0 { settleRefreshesLeft -= 1 }
    }

    // ESPN buckets games by US-Eastern day, but we display by the user's LOCAL day.
    // A game's local day can differ from its Eastern bucket by at most ±1, so fetch
    // the three neighboring buckets and keep only games that land on `day` locally.
    private func fetchLocalDay(_ day: Date) async throws -> [Match] {
        let cal = Tournament.calendar
        let keys = [-1, 0, 1]
            .compactMap { cal.date(byAdding: .day, value: $0, to: day) }
            .map { ESPNDate.dateKey($0) }

        var seen = Set<String>()
        var merged: [Match] = []
        var lastError: Error?
        var anySuccess = false
        for key in keys {
            do {
                let matches = try await fetch(dateKey: key)
                anySuccess = true
                for m in matches where !seen.contains(m.id) {
                    seen.insert(m.id)
                    merged.append(m)
                }
            } catch {
                lastError = error
            }
        }
        if !anySuccess, let lastError { throw lastError }

        return merged
            .filter { m in m.date.map { cal.isDate($0, inSameDayAs: day) } ?? false }
            .sorted(by: Self.order)
    }

    private func fetch(dateKey: String) async throws -> [Match] {
        var comps = URLComponents(string: base)!
        comps.queryItems = [URLQueryItem(name: "dates", value: dateKey)]
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await URLSession.shared.data(for: req)
        let board = try JSONDecoder().decode(Scoreboard.self, from: data)
        return board.events.compactMap(Self.makeMatch).sorted(by: Self.order)
    }

    private static func makeMatch(_ e: Event) -> Match? {
        guard let comp = e.competitions.first,
              let home = comp.competitors.first(where: { $0.homeAway == "home" }),
              let away = comp.competitors.first(where: { $0.homeAway == "away" })
        else { return nil }

        let state = MatchState(rawValue: comp.status.type.state) ?? .pre
        let date = ESPNDate.parse(e.date)

        let detail: String
        switch state {
        case .live: detail = comp.status.displayClock ?? comp.status.type.shortDetail ?? "LIVE"
        case .post: detail = comp.status.type.shortDetail ?? "FT"
        case .pre:  detail = date.map { ESPNDate.kickoff.string(from: $0) } ?? (comp.status.type.shortDetail ?? "")
        }

        func side(_ c: Competitor) -> Side {
            let abbr = c.team.abbreviation ?? c.team.shortDisplayName ?? c.team.displayName ?? "—"
            let english = c.team.displayName ?? c.team.shortDisplayName ?? abbr
            return Side(
                abbr: abbr,
                englishName: english,
                chineseName: CN.name(abbr: abbr, fallback: english),
                flagURL: c.team.logo.flatMap(URL.init(string:)),
                score: c.score ?? "0"
            )
        }

        return Match(id: e.id, home: side(home), away: side(away),
                     state: state, detail: detail, date: date)
    }

    private static func order(_ a: Match, _ b: Match) -> Bool {
        func rank(_ s: MatchState) -> Int { s == .live ? 0 : (s == .pre ? 1 : 2) }
        if rank(a.state) != rank(b.state) { return rank(a.state) < rank(b.state) }
        switch (a.date, b.date) {
        case let (x?, y?): return x < y
        default: return false
        }
    }

    private static func title(for matches: [Match], starred: Set<String>, fast: Bool) -> String {
        let live = matches.filter { $0.state == .live }
        // Prefer a starred live game, else any live game.
        let pick = live.first(where: { starred.contains($0.id) }) ?? live.first
        if let m = pick {
            let bolt = (fast && starred.contains(m.id)) ? "⚡" : "🔴"
            let base = "\(bolt) \(m.home.abbr) \(m.home.score)-\(m.away.score) \(m.away.abbr) \(m.detail)"
            return live.count > 1 ? base + " +\(live.count - 1)" : base
        }
        if let next = matches.first(where: { $0.state == .pre }) {
            return "⚽ \(next.home.abbr)–\(next.away.abbr) \(next.detail)"
        }
        return "⚽ Touchline"
    }
}

// MARK: - Global hotkey (Carbon; no Accessibility permission required)

/// A persisted key combo. `keyCode`/`carbonModifiers` drive RegisterEventHotKey;
/// `display` is the ⌃⌥⌘W-style label captured at record time.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    static let `default` = Shortcut(
        keyCode: UInt32(kVK_ANSI_Grave),
        carbonModifiers: UInt32(controlKey),
        display: "⌃`"
    )
}

/// Low-level Carbon hotkey: install the handler once, then register/unregister freely.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var onPress: (() -> Void)?

    func install() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.onPress?() }
            return noErr
        }, 1, &spec, selfPtr, &handlerRef)
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()
        let hkID = EventHotKeyID(signature: OSType(0x57433236) /* 'WC26' */, id: 1)
        RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref = ref { UnregisterEventHotKey(ref); self.ref = nil }
    }

    deinit {
        unregister()
        if let handlerRef = handlerRef { RemoveEventHandler(handlerRef) }
    }
}

/// Owns the current shortcut, persists it, and keeps the Carbon registration in sync.
@MainActor
final class HotKeyManager: ObservableObject {
    @Published var shortcut: Shortcut?
    var onToggle: (() -> Void)?

    private let hotKey = HotKey()
    private let key = "hotkey"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode(Shortcut.self, from: data) {
            shortcut = s
        } else {
            shortcut = .default
        }
        hotKey.install()
        hotKey.onPress = { [weak self] in self?.onToggle?() }
        apply()
    }

    func update(_ s: Shortcut?) {
        shortcut = s
        if let s, let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        apply()
    }

    /// Suspend the global hotkey while the user is recording a new one, so the
    /// old combo doesn't intercept the keystroke instead of letting them record it.
    func pause() { hotKey.unregister() }
    func resume() { apply() }

    private func apply() {
        if let s = shortcut { hotKey.register(keyCode: s.keyCode, modifiers: s.carbonModifiers) }
        else { hotKey.unregister() }
    }
}

// MARK: - App delegate: status item + popover + hotkey

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = Model()
    private let hotKeys = HotKeyManager()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = model.menuTitle
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 380, height: 420)
        popover.contentViewController = NSHostingController(
            rootView: PanelView()
                .environmentObject(model)
                .environmentObject(hotKeys)
        )

        // Mirror the model title into the status bar button.
        model.$menuTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] title in
                self?.statusItem.button?.title = String(title.prefix(48))
            }
            .store(in: &cancellables)

        hotKeys.onToggle = { [weak self] in self?.togglePopover() }

        model.start()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

@main
enum TouchlineMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

// MARK: - UI

struct PanelView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var hotKeys: HotKeyManager

    var body: some View {
        TabView {
            scoresTab
                .tabItem { Label("Scores", systemImage: "sportscourt") }
            SettingsTab()
                .environmentObject(hotKeys)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .frame(width: 380, height: 420)
    }

    private var scoresTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            DateStrip().environmentObject(model)
            Divider()
            roundHeader
            matchList
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Touchline").font(.headline)
            Text("World Cup 26").font(.caption).foregroundStyle(.secondary)
            if model.fastActive {
                Label("12s", systemImage: "bolt.fill")
                    .font(.caption2).foregroundStyle(.yellow)
                    .labelStyle(.titleAndIcon)
            }
            Spacer()
            if model.loading { ProgressView().controlSize(.small) }
            Button { model.refreshNow() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
    }

    @ViewBuilder
    private var roundHeader: some View {
        HStack(spacing: 6) {
            if let round = Tournament.round(for: model.selectedDate) {
                Text(round.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(model.selectedDate.formatted(.dateTime.weekday(.wide).month().day()))
                .font(.caption2).foregroundStyle(.secondary)
            Text("·").font(.caption2).foregroundStyle(.tertiary)
            Label(LocalTZ.label, systemImage: "clock")
                .font(.caption2).foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .help("All kickoff times are shown in your local timezone")
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
    }

    static let gridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    private var matchList: some View {
        Group {
            if model.panelMatches.isEmpty {
                VStack(spacing: 6) {
                    if model.loading {
                        ProgressView().controlSize(.small)
                        Text("Loading…").font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text(model.errorText ?? "No matches on this date.")
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
            } else {
                ScrollView {
                    LazyVGrid(columns: Self.gridColumns, spacing: 8) {
                        ForEach(model.panelMatches) { m in
                            MatchCard(match: m).environmentObject(model)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let t = model.lastUpdated {
                Text("Updated \(t.formatted(date: .omitted, time: .standard))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if model.errorText != nil && !model.panelMatches.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(.orange)
            }
            Spacer()
            if let s = hotKeys.shortcut {
                Text(s.display).font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless).font(.caption)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

// MARK: - Settings tab (Itsycal-style: a shortcut recorder + show/hide hint)

struct SettingsTab: View {
    @EnvironmentObject var hotKeys: HotKeyManager
    @StateObject private var login = LoginItem()
    @StateObject private var updates = UpdateChecker()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Shortcut recorder
            VStack(alignment: .leading, spacing: 6) {
                Text("Show / hide shortcut").font(.headline)
                Text("Press this combo anywhere to toggle the panel.")
                    .font(.caption).foregroundStyle(.secondary)
                ShortcutRecorder()
                    .environmentObject(hotKeys)
                    .frame(height: 26)
            }

            Divider()

            // Launch at login
            Toggle(isOn: Binding(get: { login.enabled }, set: { login.set($0) })) {
                Text("Launch at login").font(.callout)
            }
            .toggleStyle(.switch)

            Divider()

            // Update check
            HStack(spacing: 8) {
                Button { updates.check() } label: { Text("Check for Updates") }
                    .disabled(updates.state == .checking)
                updateStatusView
                Spacer()
            }

            // Links
            HStack(spacing: 16) {
                Link(destination: AppInfo.repoURL) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            .font(.callout)
            .buttonStyle(.plain)

            Spacer()

            // Author / version footer
            HStack {
                Spacer()
                Link("\(AppInfo.author)@", destination: AppInfo.repoURL)
                    .foregroundStyle(.secondary)
                Text("· v\(AppInfo.version)")
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .font(.caption)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updates.state {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .available(let v):
            Link(destination: AppInfo.releasesURL) {
                Label("v\(v) available", systemImage: "arrow.down.circle.fill")
                    .font(.caption).foregroundStyle(.blue)
            }
        case .failed:
            Label("Check failed", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        }
    }
}

struct DateStrip: View {
    @EnvironmentObject var model: Model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Tournament.days, id: \.self) { day in
                        DateChip(day: day,
                                 selected: Tournament.calendar.isDate(day, inSameDayAs: model.selectedDate),
                                 isToday: Tournament.calendar.isDateInToday(day))
                            .id(day)
                            .onTapGesture { model.selectDate(day) }
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
            }
            .onAppear {
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo(dayID(model.selectedDate), anchor: .center) }
                }
            }
            .onChange(of: model.selectedDate) { newValue in
                withAnimation { proxy.scrollTo(dayID(newValue), anchor: .center) }
            }
        }
    }

    private func dayID(_ d: Date) -> Date {
        Tournament.days.first { Tournament.calendar.isDate($0, inSameDayAs: d) } ?? d
    }
}

struct DateChip: View {
    let day: Date
    let selected: Bool
    let isToday: Bool

    var body: some View {
        VStack(spacing: 1) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption2)
            Text(day.formatted(.dateTime.day()))
                .font(.callout.weight(.semibold))
        }
        .frame(width: 40, height: 40)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor : Color.secondary.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isToday ? Color.accentColor : .clear, lineWidth: selected ? 0 : 1.5)
        )
        .foregroundStyle(selected ? Color.white : (isToday ? Color.accentColor : .primary))
    }
}

struct MatchCard: View {
    @EnvironmentObject var model: Model
    let match: Match

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Status line + star
            HStack(spacing: 4) {
                Circle().fill(dotColor).frame(width: 6, height: 6)
                Text(match.detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(match.state == .live ? Color.red : .secondary)
                    .fontWeight(match.state == .live ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Button {
                    model.toggleStar(match.id)
                } label: {
                    Image(systemName: model.isStarred(match.id) ? "bolt.fill" : "bolt")
                        .font(.caption2)
                        .foregroundStyle(model.isStarred(match.id) ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Quick-refresh (12s) while this match is live")
            }

            teamLine(match.home, winner: match.homeWins)
            teamLine(match.away, winner: match.awayWins)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(match.state == .live ? Color.red.opacity(0.08) : Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(match.state == .live ? Color.red.opacity(0.35) : .clear, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func teamLine(_ side: Side, winner: Bool) -> some View {
        HStack(spacing: 5) {
            flag(side.flagURL)

            // ABC -> English Google search
            link(text: side.abbr, url: side.englishSearchURL, winner: winner, mono: true)

            // Chinese name -> Chinese Google search
            link(text: side.chineseName, url: side.chineseSearchURL, winner: winner, mono: false)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)

            Spacer(minLength: 2)

            Text(match.hasScore ? side.score : "–")
                .font(.callout.monospacedDigit())
                .fontWeight(winner ? .bold : .regular)
                .foregroundStyle(match.hasScore ? .primary : .secondary)
        }
    }

    @ViewBuilder
    private func flag(_ url: URL?) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().aspectRatio(contentMode: .fit)
            default:
                RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.15))
            }
        }
        .frame(width: 18, height: 12)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))
    }

    @ViewBuilder
    private func link(text: String, url: URL?, winner: Bool, mono: Bool) -> some View {
        let label = Text(text)
            .font(mono ? .callout.monospaced() : .system(.callout, design: .rounded))
            .fontWeight(winner ? .bold : .regular)
        if let url {
            Link(destination: url) { label }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
        } else {
            label
        }
    }

    private var dotColor: Color {
        switch match.state {
        case .live: return .red
        case .pre:  return .secondary.opacity(0.4)
        case .post: return .green.opacity(0.6)
        }
    }
}

// MARK: - Shortcut recorder (native; mirrors MASShortcutView's behavior)

struct ShortcutRecorder: NSViewRepresentable {
    @EnvironmentObject var hotKeys: HotKeyManager

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.shortcut = hotKeys.shortcut
        v.onRecordStart = { hotKeys.pause() }
        v.onRecordEnd = { hotKeys.resume() }
        v.onChange = { newValue in hotKeys.update(newValue) }
        return v
    }

    func updateNSView(_ v: RecorderView, context: Context) {
        if !v.isRecording { v.shortcut = hotKeys.shortcut; v.needsDisplay = true }
    }
}

/// A click-to-record control. Click → captures the next modifier+key combo.
/// Esc cancels; Delete/Backspace clears. Requires ≥1 modifier to be valid.
final class RecorderView: NSView {
    var shortcut: Shortcut?
    var isRecording = false
    var onChange: ((Shortcut?) -> Void)?
    var onRecordStart: (() -> Void)?
    var onRecordEnd: (() -> Void)?

    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15)
                     : NSColor.unemphasizedSelectedContentBackgroundColor).setFill()
        bg.fill()
        NSColor.separatorColor.setStroke()
        bg.lineWidth = 1
        bg.stroke()

        let text: String
        if isRecording { text = "Type shortcut… (esc to cancel)" }
        else if let s = shortcut { text = s.display }
        else { text = "Click to record" }

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: isRecording ? .regular : .medium),
            .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor,
            .paragraphStyle: style,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let rect = NSRect(x: 0, y: (bounds.height - size.height) / 2, width: bounds.width, height: size.height)
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        isRecording ? endRecording() : beginRecording()
    }

    private func beginRecording() {
        isRecording = true
        onRecordStart?()
        // Capture keys locally while recording so they don't trigger other UI.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] ev in
            guard let self, self.isRecording else { return ev }
            if ev.type == .keyDown { return self.handleKey(ev) ? nil : ev }
            return ev
        }
        needsDisplay = true
    }

    private func endRecording() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        onRecordEnd?()
        needsDisplay = true
    }

    /// Returns true if the event was consumed.
    private func handleKey(_ ev: NSEvent) -> Bool {
        let keyCode = UInt32(ev.keyCode)

        // Esc cancels.
        if keyCode == UInt32(kVK_Escape) { endRecording(); return true }
        // Delete/Backspace clears the binding.
        if keyCode == UInt32(kVK_Delete) || keyCode == UInt32(kVK_ForwardDelete) {
            shortcut = nil; onChange?(nil); endRecording(); return true
        }

        let flags = ev.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Require at least one of ⌘⌥⌃ so a bare key can't hijack global typing.
        let hasReqMod = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
        guard hasReqMod else { NSSound.beep(); return true }

        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }

        let display = Self.modifierGlyphs(flags) + Self.keyName(keyCode: keyCode, event: ev)
        let s = Shortcut(keyCode: keyCode, carbonModifiers: carbon, display: display)
        shortcut = s
        onChange?(s)
        endRecording()
        return true
    }

    private static func modifierGlyphs(_ f: NSEvent.ModifierFlags) -> String {
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option)  { s += "⌥" }
        if f.contains(.shift)   { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        return s
    }

    private static func keyName(keyCode: UInt32, event: NSEvent) -> String {
        if let special = specialKeys[Int(keyCode)] { return special }
        let chars = (event.charactersIgnoringModifiers ?? "").uppercased()
        return chars.isEmpty ? "?" : chars
    }

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_ANSI_KeypadEnter: "⌅",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}
