// cli-pet: 터미널 위에 떠 있는 작은 펫.
// - 인자 없이 실행: 펫 창을 띄움
// - hook: Claude Code 훅 입력(JSON, stdin)을 받아 펫에게 전달
// - say <글>: 펫이 말하게 함
// - pipe: `명령 | cli-pet pipe` 로 출력 줄을 그대로 흘려보내며 펫이 보여줌
import AppKit
import JavaScriptCore

let stateDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cli-pet")
let statusURL = stateDir.appendingPathComponent("status.json")
let posURL = stateDir.appendingPathComponent("position.json")

struct Status: Codable {
    var state: String  // idle | working | done | alert | say
    var text: String
    var time: Double
}

func writeStatus(_ state: String, _ text: String) {
    try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    let s = Status(state: state, text: text, time: Date().timeIntervalSince1970)
    if let data = try? JSONEncoder().encode(s) {
        try? data.write(to: statusURL, options: .atomic)
    }
}

let ansiRegex = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]")

func clip(_ s: String, _ n: Int = 80) -> String {
    let range = NSRange(s.startIndex..., in: s)
    let plain = ansiRegex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
    let line = plain.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed.count > n ? String(trimmed.prefix(n - 1)) + "…" : trimmed
}

// MARK: - 훅 / 명령줄 모드

func describeTool(_ tool: String, _ input: [String: Any]) -> String {
    func str(_ k: String) -> String { (input[k] as? String) ?? "" }
    func base(_ k: String) -> String { (str(k) as NSString).lastPathComponent }
    switch tool {
    case "Bash": return "$ " + clip(str("command"), 70)
    case "Read": return "📖 " + base("file_path")
    case "Edit", "MultiEdit", "Write": return "✏️ " + base("file_path")
    case "NotebookEdit": return "✏️ " + base("notebook_path")
    case "Grep", "Glob": return "🔍 " + clip(str("pattern"), 60)
    case "WebFetch": return "🌐 " + (URL(string: str("url"))?.host ?? "웹 보는 중")
    case "WebSearch": return "🌐 " + clip(str("query"), 60)
    case "Task", "Agent": return "🤖 " + clip(str("description"), 60)
    case "TodoWrite": return "📝 할 일 정리 중"
    default:
        if tool.hasPrefix("mcp__") { return "🔌 " + (tool.components(separatedBy: "__").last ?? tool) }
        return "🔧 " + tool
    }
}

func runHook() {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
    switch obj["hook_event_name"] as? String ?? "" {
    case "SessionStart": writeStatus("say", "안녕! 👋")
    case "UserPromptSubmit": writeStatus("think", "음… 생각 중")
    case "PreToolUse":
        writeStatus("working", describeTool(obj["tool_name"] as? String ?? "",
                                            obj["tool_input"] as? [String: Any] ?? [:]))
    case "Notification": writeStatus("alert", clip(obj["message"] as? String ?? "나 좀 봐줘!"))
    case "Stop": writeStatus("done", "다 했어! ✨")
    case "SessionEnd": writeStatus("idle", "")
    default: break
    }
}

func runPipe() {
    var last = 0.0
    var pending: String?
    while let line = readLine(strippingNewline: true) {
        print(line)
        fflush(stdout)
        let c = clip(line)
        if c.isEmpty { continue }
        pending = c
        let now = Date().timeIntervalSince1970
        if now - last > 0.25 {
            writeStatus("working", c)
            last = now
            pending = nil
        }
    }
    if let p = pending { writeStatus("working", p); usleep(400_000) }
    writeStatus("done", "끝났어! ✨")
}

// MARK: - 팩

let settingsURL = stateDir.appendingPathComponent("settings.json")

struct PackInfo: Decodable {
    enum PoseFiles: Decodable {
        case one(String), many([String])
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .one(s) } else { self = .many(try c.decode([String].self)) }
        }
        var files: [String] { switch self { case .one(let s): return [s]; case .many(let a): return a } }
    }
    var id: String
    var name: String
    var group: Int?
    var credit: String?
    var license: String?
    var pixel: Bool?
    var size: CGFloat?
    var fps: Double?
    var squash: Bool?
    var fit: String?  // "each"면 포즈마다 size 높이에 맞춘다 (원본 크기가 제각각인 팩용)
    var category: String?
    var series: String?
    var seriesName: String?
    var tags: [String]?
    var poses: [String: PoseFiles]
}

// 없는 포즈는 앞에서부터 찾아 대신 쓴다 (docs/animation-spec.md)
let poseFallback: [String: [String]] = [
    "normal": ["normal"],
    "happy": ["happy", "normal"],
    "focus": ["focus", "normal"],
    "surprised": ["surprised", "normal"],
    "sleep": ["sleep", "blink", "normal"],
    "blink": ["blink", "normal"],
    "dizzy": ["dizzy", "surprised", "normal"],
    "think": ["think", "focus", "normal"],
    "sad": ["sad", "surprised", "normal"],
    "held": ["held", "surprised", "normal"],
    "walk": ["walk", "normal"],
]

struct Frame {
    let image: CGImage
    let delay: Double
}

final class Pack {
    let info: PackInfo
    let dir: URL
    let isUser: Bool
    private var cache: [String: [Frame]] = [:]

    init?(dir: URL, isUser: Bool) {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("pack.json")),
              let info = try? JSONDecoder().decode(PackInfo.self, from: data),
              info.poses["normal"] != nil else { return nil }
        self.info = info
        self.dir = dir
        self.isUser = isUser
    }

    func has(_ pose: String) -> Bool { info.poses[pose] != nil }

    func frames(_ pose: String) -> [Frame] {
        for name in poseFallback[pose] ?? [pose, "normal"] where info.poses[name] != nil {
            if let f = cache[name] { return f }
            let step = 1 / (info.fps ?? 6)
            let f = info.poses[name]!.files.flatMap { loadFrames(dir.appendingPathComponent($0), step) }
            cache[name] = f
            if !f.isEmpty { return f }
        }
        return []
    }

    func frame(_ pose: String, at t: Double) -> CGImage? {
        let f = frames(pose)
        guard f.count > 1 else { return f.first?.image }
        let total = f.reduce(0) { $0 + $1.delay }
        var x = t.truncatingRemainder(dividingBy: total)
        for fr in f {
            if x < fr.delay { return fr.image }
            x -= fr.delay
        }
        return f.last?.image
    }
}

// 움직이는 PNG(APNG)면 프레임을 모두 꺼낸다
func loadFrames(_ url: URL, _ step: Double) -> [Frame] {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
    let n = CGImageSourceGetCount(src)
    return (0..<n).compactMap { i in
        guard let img = CGImageSourceCreateImageAtIndex(src, i, nil) else { return nil }
        var delay = step
        if n > 1, let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any],
           let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
            let d = (png[kCGImagePropertyAPNGUnclampedDelayTime] ?? png[kCGImagePropertyAPNGDelayTime]) as? Double
            if let d, d > 0.001 { delay = d }
        }
        return Frame(image: img, delay: delay)
    }
}

func findPacks() -> [Pack] {
    var roots: [(URL, Bool)] = []
    if let r = Bundle.main.resourceURL {
        roots += [(r.appendingPathComponent("packs"), false), (r.appendingPathComponent("packs-nc"), false)]
    }
    roots.append((stateDir.appendingPathComponent("packs"), true))
    var seen = Set<String>()
    var packs: [Pack] = []
    for (root, isUser) in roots {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for d in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let p = Pack(dir: d, isUser: isUser), !creatures.contains(where: { $0.id == p.info.id }), seen.insert(p.info.id).inserted else { continue }
            packs.append(p)
        }
    }
    return packs.sorted { ($0.isUser ? 9 : $0.info.group ?? 9, $0.info.name) < ($1.isUser ? 9 : $1.info.group ?? 9, $1.info.name) }
}

func loadSelectedPackID() -> String {
    guard let data = try? Data(contentsOf: settingsURL),
          let obj = try? JSONDecoder().decode([String: String].self, from: data) else { return defaultPetID }
    return obj["pack"] ?? defaultPetID
}

func saveSelectedPackID(_ id: String) {
    try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    try? JSONEncoder().encode(["pack": id]).write(to: settingsURL, options: .atomic)
}

// MARK: - 코드로 그리는 0군 캐릭터

struct RGB {
    let r, g, b: CGFloat
    var cg: CGColor { CGColor(red: r, green: g, blue: b, alpha: 1) }
}
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> RGB { RGB(r: r, g: g, b: b) }

struct Creature {
    enum Ears { case none, pointy, floppy, round, long }
    enum Tail { case none, thin, wag, fluffy, puff }
    enum Mouth { case smile, cat, dog, nose, beak, bill }
    enum Mark { case none, leaf, stripes, belly, muzzle, face }
    enum Back { case none, quills, shell }
    var id: String
    var name: String
    var series: String
    var w: CGFloat = 64, h: CGFloat = 54
    var top: RGB, bottom: RGB
    var inner = rgb(1.0, 0.72, 0.74)   // 귀 안쪽
    var patch = rgb(1.0, 0.98, 0.95)   // 배, 주둥이, 무늬, 늘어진 귀
    var ears = Ears.none, tail = Tail.none, mouth = Mouth.smile, mark = Mark.none
    var eyeY: CGFloat = 0.5, eyeGap: CGFloat = 0.18
    var back = Back.none, backColor = rgb(0.45, 0.32, 0.24)  // 몸 뒤 가시·등껍질
    var feet: RGB? = nil
    var whiskers = false, tuft = false
    var category: String { series == "sprout" ? "original" : "animal" }
    // 몸 위로 튀어나오는 부분(귀, 새싹) 높이. 말풍선 위치에 쓴다
    var headroom: CGFloat {
        switch ears {
        case .long: return 30
        case .pointy: return 13
        case .round: return 6
        default: return mark == .leaf ? 12 : tuft ? 10 : back == .quills ? 8 : back == .shell ? 5 : 0
        }
    }
}

let creatures: [Creature] = [
    Creature(id: "original-sprout", name: "새싹", series: "sprout",
             top: rgb(1.0, 0.76, 0.62), bottom: rgb(0.94, 0.52, 0.40), mark: .leaf),
    Creature(id: "animal-real-cat", name: "고양이", series: "real", w: 62,
             top: rgb(1.0, 0.84, 0.60), bottom: rgb(0.97, 0.66, 0.36), patch: rgb(0.88, 0.52, 0.25),
             ears: .pointy, tail: .thin, mouth: .cat, mark: .stripes),
    Creature(id: "animal-real-dog", name: "강아지", series: "real",
             top: rgb(0.97, 0.88, 0.74), bottom: rgb(0.88, 0.72, 0.52), patch: rgb(0.62, 0.43, 0.30),
             ears: .floppy, tail: .wag, mouth: .dog, mark: .none),
    Creature(id: "animal-real-hamster", name: "햄스터", series: "real", w: 68, h: 50,
             top: rgb(1.0, 0.85, 0.62), bottom: rgb(0.96, 0.70, 0.44), patch: rgb(1.0, 0.97, 0.92),
             ears: .round, mouth: .nose, mark: .belly, eyeY: 0.55, eyeGap: 0.2),
    Creature(id: "animal-real-rabbit", name: "토끼", series: "real", w: 60, h: 52,
             top: rgb(1.0, 0.99, 0.98), bottom: rgb(0.90, 0.89, 0.92), patch: rgb(1.0, 1.0, 1.0),
             ears: .long, tail: .puff, mouth: .nose),
    Creature(id: "animal-real-penguin", name: "펭귄", series: "real", w: 58, h: 62,
             top: rgb(0.30, 0.36, 0.50), bottom: rgb(0.18, 0.22, 0.32), patch: rgb(1.0, 1.0, 1.0),
             mouth: .beak, mark: .face, eyeY: 0.55, feet: rgb(1.0, 0.6, 0.2)),
    Creature(id: "animal-real-fox", name: "여우", series: "real", w: 62,
             top: rgb(1.0, 0.64, 0.34), bottom: rgb(0.93, 0.46, 0.20), inner: rgb(1.0, 0.92, 0.84), patch: rgb(1.0, 0.97, 0.92),
             ears: .pointy, tail: .fluffy, mouth: .cat, mark: .muzzle),
    Creature(id: "animal-real-duck", name: "오리", series: "real", w: 60, h: 52,
             top: rgb(1.0, 0.96, 0.62), bottom: rgb(0.98, 0.84, 0.36),
             mouth: .bill, eyeY: 0.58, feet: rgb(1.0, 0.6, 0.2), tuft: true),
    Creature(id: "animal-real-otter", name: "수달", series: "real", w: 62,
             top: rgb(0.74, 0.54, 0.40), bottom: rgb(0.56, 0.38, 0.26), inner: rgb(0.58, 0.40, 0.29), patch: rgb(0.95, 0.87, 0.76),
             ears: .round, tail: .wag, mouth: .dog, mark: .muzzle, whiskers: true),
    Creature(id: "animal-real-hedgehog", name: "고슴도치", series: "real", w: 60, h: 50,
             top: rgb(0.99, 0.90, 0.76), bottom: rgb(0.92, 0.76, 0.58), inner: rgb(0.95, 0.66, 0.62),
             ears: .round, mouth: .dog, back: .quills),
    Creature(id: "animal-real-turtle", name: "거북이", series: "real", w: 58, h: 50,
             top: rgb(0.66, 0.87, 0.55), bottom: rgb(0.46, 0.73, 0.38),
             back: .shell, backColor: rgb(0.66, 0.48, 0.27), feet: rgb(0.50, 0.76, 0.42)),
]
let defaultPetID = "original-sprout"

// MARK: - 분류 (docs/pack-format.md)

let categoryOrder: [(id: String, label: String)] = [
    ("original", "자체 캐릭터"), ("animal", "동물"), ("dev", "개발"), ("game", "게임"),
    ("anime", "애니·만화·일러스트"), ("virtual", "보컬로이드·버추얼"), ("brand", "브랜드"),
    ("meme", "밈"), ("public", "공공 캐릭터"), ("etc", "기타"),
]
let seriesLabels = ["sprout": "새싹", "real": "실제 동물 (자체)"]

struct PetEntry {
    var id: String
    var name: String
    var category: String
    var series: String
    var seriesName: String
    var group: Int
    var isUser: Bool
}

// MARK: - 펫 그리기

final class PetView: NSView {
    var packs: [Pack] = []
    var pack: Pack?  // nil이면 코드로 그리는 캐릭터
    var creature = creatures[0]
    var dragging = false

    var mood = "idle"
    var bubbleText: String?
    var bubbleUntil = 0.0
    var bubbleRect = NSRect.zero
    var moodSince = 0.0
    var lastEvent = CACurrentMediaTime()

    var t = CACurrentMediaTime()
    var jumpAt = -10.0
    var happyUntil = 0.0
    var blinkAt = -10.0
    var nextBlink = CACurrentMediaTime() + 2
    var dizzyUntil = 0.0
    var clickTimes: [Double] = []

    var downMouse = NSPoint.zero
    var downOrigin = NSPoint.zero
    var dragged = false

    let jumpDur = 0.55

    // 팩 그림은 normal 포즈 높이를 기준으로 한 배율을 모든 포즈에 똑같이 쓴다
    var packScale: CGFloat {
        guard let pack, let img = pack.frames("normal").first?.image else { return 1 }
        return (pack.info.size ?? 80) / CGFloat(img.height)
    }

    var petRect: NSRect {
        var w = creature.w, h = creature.h + creature.headroom
        if let pack, let img = pack.frames("normal").first?.image {
            h = pack.info.size ?? 80
            w = CGFloat(img.width) * packScale
        }
        return NSRect(x: bounds.midX - w / 2, y: 16, width: w, height: h)
    }

    func selectPack(_ id: String, announce: Bool) {
        let id = id == "sprout" ? defaultPetID : id  // 예전 설정 호환
        if let c = creatures.first(where: { $0.id == id }) {
            creature = c
            pack = nil
        } else if let p = packs.first(where: { $0.info.id == id }) {
            pack = p
        } else {
            creature = creatures[0]
            pack = nil
        }
        saveSelectedPackID(pack?.info.id ?? creature.id)
        if announce { jumpAt = t; say("짠! \(pack?.info.name ?? creature.name)", 2.5) }
    }

    var entries: [PetEntry] {
        creatures.map {
            PetEntry(id: $0.id, name: $0.name, category: $0.category, series: $0.series,
                     seriesName: seriesLabels[$0.series] ?? $0.series, group: 0, isUser: false)
        } + packs.map {
            let cat = $0.info.category ?? "etc"
            let series = $0.info.series ?? $0.info.id
            return PetEntry(id: $0.info.id, name: $0.info.name,
                            category: categoryOrder.contains { $0.id == cat } ? cat : "etc",
                            series: series, seriesName: $0.info.seriesName ?? series,
                            group: $0.info.group ?? 1, isUser: $0.isUser)
        }
    }
    var sleeping: Bool { mood == "idle" && bubbleText == nil && t - lastEvent > 90 }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func tick() {
        t = CACurrentMediaTime()
        if t > nextBlink { blinkAt = t; nextBlink = t + Double.random(in: 2...5) }
        if bubbleText != nil && t > bubbleUntil { bubbleText = nil }
        let age = t - moodSince
        if (mood == "done" || mood == "say") && age > 6 { mood = "idle" }
        if mood == "alert" && age > 30 { mood = "idle" }
        if (mood == "working" || mood == "think") && t - lastEvent > 180 { mood = "idle"; bubbleText = nil }
        needsDisplay = true
    }

    func apply(_ s: Status) {
        mood = s.state
        moodSince = t
        lastEvent = t
        if s.text.isEmpty {
            bubbleText = nil
        } else {
            bubbleText = s.text
            bubbleUntil = t + (s.state == "working" || s.state == "think" ? 60 : s.state == "alert" ? 30 : 6)
        }
        if s.state == "done" { happyUntil = t + 3 }
    }

    func say(_ s: String, _ dur: Double) { bubbleText = s; bubbleUntil = t + dur }

    func poke() {
        lastEvent = t
        clickTimes = clickTimes.filter { t - $0 < 1.5 } + [t]
        if clickTimes.count >= 5 {
            clickTimes.removeAll()
            dizzyUntil = t + 2.5
            say("어지러워~ 😵", 2.5)
            return
        }
        jumpAt = t
        happyUntil = t + 1
        if mood != "working" && mood != "think" && mood != "alert" {
            say(["히히", "간지러워!", "왜~?", "놀아줘!", "♪", "헤헤", "뭐해?"].randomElement()!, 1.8)
        }
    }

    // MARK: 마우스

    override func mouseDown(with e: NSEvent) {
        downMouse = NSEvent.mouseLocation
        downOrigin = window?.frame.origin ?? .zero
        dragged = false
    }

    override func mouseDragged(with e: NSEvent) {
        let p = NSEvent.mouseLocation
        let dx = p.x - downMouse.x, dy = p.y - downMouse.y
        if hypot(dx, dy) > 3 { dragged = true; dragging = true }
        if dragged { window?.setFrameOrigin(NSPoint(x: downOrigin.x + dx, y: downOrigin.y + dy)) }
    }

    override func mouseUp(with e: NSEvent) {
        if dragged {
            dragging = false
            jumpAt = t - jumpDur  // 착지 찌그러짐만 재생
            savePosition()
            return
        }
        let p = convert(e.locationInWindow, from: nil)
        if bubbleText != nil && bubbleRect.contains(p) {
            bubbleText = nil
        } else {
            poke()
        }
    }

    override func rightMouseDown(with e: NSEvent) {
        let menu = NSMenu()
        let reset = NSMenuItem(title: "구석으로 보내기", action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(packMenuItem())
        if let pack, let credit = pack.info.credit {
            let line = [credit, pack.info.license].compactMap { $0 }.joined(separator: " · ")
            let info = NSMenuItem(title: "그림: " + line, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }
        menu.addItem(.separator())
        let hooks = NSMenuItem(title: "Claude Code 연결", action: #selector(toggleHooks), keyEquivalent: "")
        hooks.target = self
        hooks.state = hooksInstalled() ? .on : .off
        menu.addItem(hooks)
        let login = NSMenuItem(title: "로그인할 때 자동 실행", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = loginItemOn() ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        NSMenu.popUpContextMenu(menu, with: e, for: self)
    }

    // 펫 바꾸기 ▸ 분류 ▸ (시리즈 ▸) 펫
    func packMenuItem() -> NSMenuItem {
        packs = findPacks().map { found in packs.first { $0.info.id == found.info.id && $0.dir == found.dir } ?? found }
        let current = pack?.info.id ?? creature.id
        let all = entries
        let root = NSMenu()
        func petItem(_ e: PetEntry) -> NSMenuItem {
            var title = e.name
            if e.group == 3 { title += "  · 비상업" }
            if e.isUser { title += "  · 내 팩" }
            let item = NSMenuItem(title: title, action: #selector(pickPack(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = e.id
            item.state = e.id == current ? .on : .off
            return item
        }
        func folder(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let m = NSMenu()
            items.forEach(m.addItem)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = m
            if items.contains(where: { $0.state == .on }) { item.state = .on }
            return item
        }
        for (cat, label) in categoryOrder {
            let inCat = all.filter { $0.category == cat }
            guard !inCat.isEmpty else { continue }
            var seriesOrder: [String] = []
            for e in inCat where !seriesOrder.contains(e.series) { seriesOrder.append(e.series) }
            var items: [NSMenuItem] = []
            for s in seriesOrder {
                let inSeries = inCat.filter { $0.series == s }
                if inSeries.count > 1 && seriesOrder.count > 1 {
                    items.append(folder(inSeries[0].seriesName, inSeries.map(petItem)))
                } else {
                    items += inSeries.map(petItem)
                }
            }
            root.addItem(folder(label, items))
        }
        root.addItem(.separator())
        let open = NSMenuItem(title: "내 팩 폴더 열기…", action: #selector(openUserPacks), keyEquivalent: "")
        open.target = self
        root.addItem(open)
        let item = NSMenuItem(title: "펫 바꾸기", action: nil, keyEquivalent: "")
        item.submenu = root
        return item
    }

    @objc func pickPack(_ sender: NSMenuItem) {
        selectPack(sender.representedObject as? String ?? defaultPetID, announce: true)
    }

    @objc func openUserPacks() {
        let dir = stateDir.appendingPathComponent("packs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc func toggleHooks() {
        let on = !hooksInstalled()
        do {
            try setHooks(on)
            say(on ? "이제 Claude Code 따라다닐게! (새 세션부터)" : "Claude Code 연결 끊었어", 4)
        } catch {
            say("설정 파일을 못 읽었어 😢", 4)
        }
    }

    @objc func toggleLogin() {
        let on = !loginItemOn()
        try? setLoginItem(on)
        say(on ? "로그인하면 나타날게!" : "자동 실행 껐어", 3)
    }

    @objc func resetPosition() {
        window?.setFrameOrigin(defaultOrigin(size: window?.frame.size ?? .zero))
        savePosition()
    }

    func savePosition() {
        guard let o = window?.frame.origin else { return }
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try? JSONEncoder().encode([o.x, o.y]).write(to: posURL)
    }

    // MARK: 그리기

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let base = petRect
        let dizzy = t < dizzyUntil
        let happy = t < happyUntil || mood == "say"
        let age = t - moodSince

        var dx: CGFloat = 0, dy: CGFloat = 0, sx: CGFloat = 1, sy: CGFloat = 1, rot: CGFloat = 0
        switch mood {
        case _ where dragging:
            rot = CGFloat(sin(t * 5)) * 0.12
        case "working":
            dy = CGFloat(abs(sin(t * 7))) * 5
        case "think":
            dx = CGFloat(sin(t * 1.6)) * 2
            rot = CGFloat(sin(t * 1.6)) * 0.05
        case "alert":
            if age.truncatingRemainder(dividingBy: 2) < 0.4 { dx = CGFloat(sin(t * 50)) * 3 }
        case "done" where age < 2:
            dy = CGFloat(abs(sin(age * 6))) * 10
        default:
            let speed = sleeping ? 1.2 : 2.0
            let amt: CGFloat = sleeping ? 0.04 : 0.025
            sy = 1 + CGFloat(sin(t * speed)) * amt
            sx = 1 - CGFloat(sin(t * speed)) * amt * 0.8
        }
        if dizzy {
            rot = CGFloat(sin(t * 7)) * 0.18
            dx += CGFloat(sin(t * 3.5)) * 4
        }

        // 점프 (클릭)
        var jumpDy: CGFloat = 0
        let jp = (t - jumpAt) / jumpDur
        if jp >= 0 && jp < 1 {
            jumpDy = CGFloat(sin(jp * .pi)) * 34
            if jp < 0.15 { sx *= 0.9; sy *= 1.12 } else { sx *= 0.96; sy *= 1.05 }
        } else if jp >= 1 && jp < 1.25 {
            let k = CGFloat(sin((jp - 1) / 0.25 * .pi))
            sx *= 1 + 0.14 * k
            sy *= 1 - 0.16 * k
        }
        dy += jumpDy

        drawBubble(base: base, lift: jumpDy)

        // 그림자
        let shrink = max(0.4, 1 - dy / 70)
        ctx.setFillColor(NSColor(white: 0, alpha: 0.18 * shrink).cgColor)
        let sw = min(base.width, 80) * 0.85 * shrink
        ctx.fillEllipse(in: CGRect(x: base.midX - sw / 2 + dx, y: base.minY - 5, width: sw, height: 9))

        if let pack, pack.info.squash == false { sx = 1; sy = 1 }
        ctx.saveGState()
        ctx.translateBy(x: base.midX + dx, y: base.minY + dy)
        ctx.rotate(by: rot)
        ctx.scaleBy(x: sx, y: sy)
        if let pack {
            drawPack(ctx, pack, pose: currentPose(dizzy: dizzy, happy: happy))
        } else {
            drawBody(ctx, dizzy: dizzy, happy: happy)
        }
        ctx.restoreGState()

        if sleeping && pack?.has("sleep") != true { drawZzz(base: base) }
    }

    func currentPose(dizzy: Bool, happy: Bool) -> String {
        if dragging { return "held" }
        if dizzy { return "dizzy" }
        if sleeping { return "sleep" }
        switch mood {
        case "alert": return "surprised"
        case "working": return "focus"
        case "think": return "think"
        case "error": return "sad"
        default: break
        }
        if happy || mood == "done" { return "happy" }
        if t - blinkAt < 0.15, pack?.has("blink") == true { return "blink" }
        return "normal"
    }

    func drawPack(_ ctx: CGContext, _ pack: Pack, pose: String) {
        guard let img = pack.frame(pose, at: t) else { return }
        let s = pack.info.fit == "each" ? (pack.info.size ?? 80) / CGFloat(img.height) : packScale
        var w = CGFloat(img.width) * s, h = CGFloat(img.height) * s
        // 포즈마다 그림 크기가 달라도 창 밖으로 넘치지 않게
        let fit = min(1, (bounds.width - 16) / w, (pack.info.size ?? 80) * 1.4 / h)
        w *= fit
        h *= fit
        ctx.interpolationQuality = pack.info.pixel == true ? .none : .high
        ctx.draw(img, in: CGRect(x: -w / 2, y: 0, width: w, height: h))
    }

    func drawBody(_ ctx: CGContext, dizzy: Bool, happy: Bool) {
        let c = creature
        let w = c.w, h = c.h
        let ink = inkColor
        let happyFace = happy || mood == "done"
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)

        // 몸 뒤: 등껍질·가시, 꼬리, 귀, 새싹
        drawBack(ctx, c)
        drawTail(ctx, c, happy: happyFace)
        if c.ears != .floppy { drawEars(ctx, c) }
        if c.mark == .leaf { drawLeaf(ctx, h) }
        if c.tuft { drawTuft(ctx, c) }

        // 몸
        let body = CGMutablePath()
        body.move(to: CGPoint(x: -w / 2, y: h * 0.35))
        body.addCurve(to: CGPoint(x: 0, y: h), control1: CGPoint(x: -w / 2, y: h * 0.85), control2: CGPoint(x: -w * 0.28, y: h))
        body.addCurve(to: CGPoint(x: w / 2, y: h * 0.35), control1: CGPoint(x: w * 0.28, y: h), control2: CGPoint(x: w / 2, y: h * 0.85))
        body.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: w / 2, y: h * 0.06), control2: CGPoint(x: w * 0.3, y: 0))
        body.addCurve(to: CGPoint(x: -w / 2, y: h * 0.35), control1: CGPoint(x: -w * 0.3, y: 0), control2: CGPoint(x: -w / 2, y: h * 0.06))
        body.closeSubpath()

        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [c.top.cg, c.bottom.cg] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])
        drawMarks(ctx, c)
        ctx.restoreGState()

        ctx.addPath(body)
        ctx.setStrokeColor(ink)
        ctx.setLineWidth(2)
        ctx.strokePath()

        if c.ears == .floppy { drawEars(ctx, c) }
        if let f = c.feet { drawFeet(ctx, w, f.cg) }

        // 반짝이
        ctx.setFillColor(NSColor(white: 1, alpha: 0.55).cgColor)
        ctx.fillEllipse(in: CGRect(x: -w * 0.32, y: h * 0.66, width: 10, height: 6))

        // 볼
        ctx.setFillColor(NSColor(red: 1, green: 0.45, blue: 0.5, alpha: 0.45).cgColor)
        ctx.fillEllipse(in: CGRect(x: -w * 0.36 - 4, y: h * 0.30, width: 9, height: 5))
        ctx.fillEllipse(in: CGRect(x: w * 0.36 - 5, y: h * 0.30, width: 9, height: 5))

        if c.whiskers { drawWhiskers(ctx, c) }
        drawEyes(ctx, c, dizzy: dizzy, happy: happyFace)
        drawMouth(ctx, c, dizzy: dizzy, happy: happyFace)
    }

    var inkColor: CGColor { CGColor(red: 0.28, green: 0.14, blue: 0.10, alpha: 1) }

    func drawLeaf(_ ctx: CGContext, _ h: CGFloat) {
        let sway = CGFloat(sin(t * 2.2)) * 3
        ctx.setStrokeColor(CGColor(red: 0.30, green: 0.55, blue: 0.25, alpha: 1))
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: 0, y: h - 2))
        ctx.addQuadCurve(to: CGPoint(x: sway, y: h + 9), control: CGPoint(x: -2, y: h + 5))
        ctx.strokePath()
        ctx.setFillColor(CGColor(red: 0.45, green: 0.75, blue: 0.35, alpha: 1))
        ctx.saveGState()
        ctx.translateBy(x: sway, y: h + 9)
        ctx.rotate(by: 0.5 + sway * 0.05)
        ctx.fillEllipse(in: CGRect(x: 0, y: -3, width: 11, height: 6))
        ctx.restoreGState()
    }

    // 채우고 테두리 긋기
    func fillStroke(_ ctx: CGContext, _ path: CGPath, _ color: CGColor, width: CGFloat = 2) {
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(inkColor)
        ctx.setLineWidth(width)
        ctx.strokePath()
    }

    func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ ew: CGFloat, _ eh: CGFloat, rot: CGFloat = 0) -> CGPath {
        var tr = CGAffineTransform(translationX: cx, y: cy).rotated(by: rot)
        return CGPath(ellipseIn: CGRect(x: -ew / 2, y: -eh / 2, width: ew, height: eh), transform: &tr)
    }

    func drawEars(_ ctx: CGContext, _ c: Creature) {
        let w = c.w, h = c.h
        for s in [-1.0, 1.0] as [CGFloat] {
            switch c.ears {
            case .pointy:
                let outer = CGMutablePath()
                outer.move(to: CGPoint(x: s * w * 0.08, y: h * 0.97))
                outer.addLine(to: CGPoint(x: s * w * 0.33, y: h * 1.24))
                outer.addLine(to: CGPoint(x: s * w * 0.44, y: h * 0.72))
                outer.closeSubpath()
                fillStroke(ctx, outer, c.top.cg)
                let inner = CGMutablePath()
                inner.move(to: CGPoint(x: s * w * 0.17, y: h * 0.95))
                inner.addLine(to: CGPoint(x: s * w * 0.32, y: h * 1.14))
                inner.addLine(to: CGPoint(x: s * w * 0.39, y: h * 0.82))
                inner.closeSubpath()
                ctx.addPath(inner)
                ctx.setFillColor(c.inner.cg)
                ctx.fillPath()
            case .round:
                fillStroke(ctx, ellipse(s * w * 0.32, h * 0.9, 17, 17), c.top.cg)
                ctx.addPath(ellipse(s * w * 0.32, h * 0.92, 9, 9))
                ctx.setFillColor(c.inner.cg)
                ctx.fillPath()
            case .long:
                let droop: CGFloat = sleeping || mood == "error" ? 0.5 : 0.12 + CGFloat(sin(t * 1.8 + Double(s))) * 0.04
                fillStroke(ctx, ellipse(s * w * 0.17, h * 1.18, 13, 34, rot: -s * droop), c.top.cg)
                ctx.addPath(ellipse(s * w * 0.17, h * 1.18, 6, 24, rot: -s * droop))
                ctx.setFillColor(c.inner.cg)
                ctx.fillPath()
            case .floppy:
                let flap = CGFloat(sin(t * (mood == "working" ? 8 : 2) + Double(s))) * 0.06
                fillStroke(ctx, ellipse(s * w * 0.43, h * 0.62, 15, 27, rot: s * (0.35 + flap)), c.patch.cg)
            case .none:
                break
            }
        }
    }

    func drawTail(_ ctx: CGContext, _ c: Creature, happy: Bool) {
        let w = c.w, h = c.h
        let sway = CGFloat(sin(t * 2))
        switch c.tail {
        case .thin:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: w * 0.36, y: h * 0.18))
            p.addQuadCurve(to: CGPoint(x: w * 0.62 + sway * 3, y: h * 0.62),
                           control: CGPoint(x: w * 0.72, y: h * 0.12))
            ctx.addPath(p); ctx.setStrokeColor(inkColor); ctx.setLineWidth(8); ctx.strokePath()
            ctx.addPath(p); ctx.setStrokeColor(c.bottom.cg); ctx.setLineWidth(4.5); ctx.strokePath()
        case .wag:
            let wag = CGFloat(sin(t * (happy ? 18 : 5))) * (happy ? 6 : 2)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: w * 0.38, y: h * 0.25))
            p.addQuadCurve(to: CGPoint(x: w * 0.56 + wag, y: h * 0.5), control: CGPoint(x: w * 0.56, y: h * 0.24))
            ctx.addPath(p); ctx.setStrokeColor(inkColor); ctx.setLineWidth(9); ctx.strokePath()
            ctx.addPath(p); ctx.setStrokeColor(c.bottom.cg); ctx.setLineWidth(5.5); ctx.strokePath()
        case .fluffy:
            let rot = 0.9 + sway * 0.08
            fillStroke(ctx, ellipse(w * 0.5, h * 0.3, 36, 17, rot: rot), c.bottom.cg)
            let tip = CGPoint(x: w * 0.5 + cos(rot) * 13, y: h * 0.3 + sin(rot) * 13)
            ctx.saveGState()
            ctx.addPath(ellipse(w * 0.5, h * 0.3, 36, 17, rot: rot))
            ctx.clip()
            ctx.addPath(ellipse(tip.x, tip.y, 14, 18, rot: rot))
            ctx.setFillColor(c.patch.cg)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.addPath(ellipse(w * 0.5, h * 0.3, 36, 17, rot: rot))
            ctx.setStrokeColor(inkColor); ctx.setLineWidth(2); ctx.strokePath()
        case .puff:
            fillStroke(ctx, ellipse(w * 0.44, h * 0.16, 14, 14), c.patch.cg)
        case .none:
            break
        }
    }

    func drawMarks(_ ctx: CGContext, _ c: Creature) {
        let w = c.w, h = c.h
        switch c.mark {
        case .stripes:
            ctx.setStrokeColor(c.patch.cg)
            ctx.setLineWidth(3)
            for x in [-7.0, 0.0, 7.0] as [CGFloat] {
                ctx.move(to: CGPoint(x: x, y: h + 1))
                ctx.addLine(to: CGPoint(x: x * 0.8, y: h * 0.83 + (x == 0 ? -2 : 1)))
            }
            ctx.strokePath()
        case .belly:
            ctx.addPath(ellipse(0, h * 0.1, w * 0.62, h * 0.5))
            ctx.setFillColor(c.patch.cg)
            ctx.fillPath()
        case .muzzle:
            ctx.addPath(ellipse(0, h * 0.28, w * 0.56, h * 0.36))
            ctx.setFillColor(c.patch.cg)
            ctx.fillPath()
        case .face:
            ctx.addPath(ellipse(0, h * 0.4, w * 0.82, h * 0.74))
            ctx.setFillColor(c.patch.cg)
            ctx.fillPath()
        case .leaf, .none:
            break
        }
    }

    func drawFeet(_ ctx: CGContext, _ w: CGFloat, _ color: CGColor) {
        for s in [-1.0, 1.0] as [CGFloat] {
            fillStroke(ctx, ellipse(s * w * 0.2, 0, 15, 7), color, width: 1.5)
        }
    }

    func drawBack(_ ctx: CGContext, _ c: Creature) {
        let w = c.w, h = c.h
        switch c.back {
        case .quills:
            // 몸 둘레를 따라 뾰족뾰족한 테두리
            let p = CGMutablePath()
            let n = 13
            for i in 0...(n * 2) {
                let a = (-0.25 + 1.5 * Double(i) / Double(n * 2)) * .pi
                let outer = i % 2 == 0
                let rx = w * (outer ? 0.66 : 0.5), ry = h * (outer ? 0.66 : 0.52)
                let pt = CGPoint(x: CGFloat(cos(a)) * rx, y: h * 0.46 + CGFloat(sin(a)) * ry)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            fillStroke(ctx, p, c.backColor.cg)
        case .shell:
            let shell = ellipse(0, h * 0.5, w * 1.22, h * 1.08)
            fillStroke(ctx, shell, c.backColor.cg)
            // 등껍질 무늬: 테두리를 따라 칸 나누기
            ctx.saveGState()
            ctx.addPath(shell)
            ctx.clip()
            ctx.setStrokeColor(CGColor(red: 0.45, green: 0.31, blue: 0.16, alpha: 1))
            ctx.setLineWidth(1.6)
            for i in 0..<10 {
                let a = Double(i) / 10 * 2 * .pi
                ctx.move(to: CGPoint(x: CGFloat(cos(a)) * w * 0.42, y: h * 0.5 + CGFloat(sin(a)) * h * 0.38))
                ctx.addLine(to: CGPoint(x: CGFloat(cos(a)) * w * 0.7, y: h * 0.5 + CGFloat(sin(a)) * h * 0.62))
            }
            ctx.strokePath()
            ctx.addPath(ellipse(0, h * 0.5, w * 0.98, h * 0.86))
            ctx.strokePath()
            ctx.restoreGState()
        case .none:
            break
        }
    }

    func drawTuft(_ ctx: CGContext, _ c: Creature) {
        let h = c.h
        let sway = CGFloat(sin(t * 2.4)) * 2
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -2, y: h - 2))
        p.addQuadCurve(to: CGPoint(x: 3 + sway, y: h + 9), control: CGPoint(x: -4, y: h + 8))
        p.addQuadCurve(to: CGPoint(x: 4, y: h - 2), control: CGPoint(x: 8 + sway, y: h + 3))
        fillStroke(ctx, p, c.bottom.cg, width: 1.6)
    }

    func drawWhiskers(_ ctx: CGContext, _ c: Creature) {
        let w = c.w, y = c.h * 0.32
        ctx.setStrokeColor(inkColor)
        ctx.setLineWidth(1)
        for s in [-1.0, 1.0] as [CGFloat] {
            for dy in [2.0, -2.0] as [CGFloat] {
                ctx.move(to: CGPoint(x: s * w * 0.2, y: y + dy * 0.5))
                ctx.addLine(to: CGPoint(x: s * w * 0.46, y: y + dy * 1.6))
            }
        }
        ctx.strokePath()
    }

    func drawEyes(_ ctx: CGContext, _ c: Creature, dizzy: Bool, happy: Bool) {
        let w = c.w, h = c.h
        let ink = inkColor
        let look: CGFloat = mood == "working" || mood == "think" ? CGFloat(sin(t * 1.3)) * 3 : 0
        let eyeY = h * c.eyeY
        ctx.setStrokeColor(ink)
        ctx.setFillColor(ink)
        ctx.setLineWidth(2.2)
        for side in [-1.0, 1.0] as [CGFloat] {
            let ex = side * w * c.eyeGap + look
            if dizzy {
                ctx.move(to: CGPoint(x: ex - 4, y: eyeY - 4)); ctx.addLine(to: CGPoint(x: ex + 4, y: eyeY + 4))
                ctx.move(to: CGPoint(x: ex - 4, y: eyeY + 4)); ctx.addLine(to: CGPoint(x: ex + 4, y: eyeY - 4))
                ctx.strokePath()
            } else if sleeping {
                ctx.move(to: CGPoint(x: ex - 5, y: eyeY))
                ctx.addQuadCurve(to: CGPoint(x: ex + 5, y: eyeY), control: CGPoint(x: ex, y: eyeY - 4))
                ctx.strokePath()
            } else if happy {
                ctx.move(to: CGPoint(x: ex - 5, y: eyeY - 2))
                ctx.addQuadCurve(to: CGPoint(x: ex + 5, y: eyeY - 2), control: CGPoint(x: ex, y: eyeY + 6))
                ctx.strokePath()
            } else if t - blinkAt < 0.12 {
                ctx.move(to: CGPoint(x: ex - 4, y: eyeY)); ctx.addLine(to: CGPoint(x: ex + 4, y: eyeY))
                ctx.strokePath()
            } else {
                let big = mood == "alert" || dragging
                let ew: CGFloat = big ? 8 : 6, eh: CGFloat = big ? 11 : 9
                ctx.setFillColor(ink)
                ctx.fillEllipse(in: CGRect(x: ex - ew / 2, y: eyeY - eh / 2, width: ew, height: eh))
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: CGRect(x: ex - ew / 2 + 1, y: eyeY + eh / 2 - 4.5, width: 3, height: 3))
                ctx.setFillColor(ink)
            }
        }
    }

    func drawMouth(_ ctx: CGContext, _ c: Creature, dizzy: Bool, happy: Bool) {
        let h = c.h
        let ink = inkColor
        let surprised = mood == "alert" || dizzy || dragging
        let my = h * 0.33
        ctx.setStrokeColor(ink)
        ctx.setFillColor(ink)
        ctx.setLineWidth(1.8)

        func omega(_ y: CGFloat, _ s: CGFloat) {
            ctx.move(to: CGPoint(x: -5 * s, y: y))
            ctx.addQuadCurve(to: CGPoint(x: 0, y: y), control: CGPoint(x: -2.5 * s, y: y - 4 * s))
            ctx.addQuadCurve(to: CGPoint(x: 5 * s, y: y), control: CGPoint(x: 2.5 * s, y: y - 4 * s))
            ctx.strokePath()
        }

        switch c.mouth {
        case .smile:
            if surprised {
                ctx.fillEllipse(in: CGRect(x: -2.5, y: my - 4, width: 5, height: 6))
            } else if happy {
                ctx.move(to: CGPoint(x: -5, y: my))
                ctx.addQuadCurve(to: CGPoint(x: 5, y: my), control: CGPoint(x: 0, y: my - 7))
                ctx.closePath()
                ctx.fillPath()
            } else if sleeping {
                ctx.strokeEllipse(in: CGRect(x: -1.5, y: my - 3, width: 3, height: 3))
            } else if mood == "working" {
                ctx.move(to: CGPoint(x: -3, y: my - 1)); ctx.addLine(to: CGPoint(x: 3, y: my - 1))
                ctx.strokePath()
            } else {
                ctx.move(to: CGPoint(x: -3.5, y: my))
                ctx.addQuadCurve(to: CGPoint(x: 3.5, y: my), control: CGPoint(x: 0, y: my - 4))
                ctx.strokePath()
            }
        case .cat, .nose:
            let ny = h * 0.39
            ctx.setFillColor(c.mouth == .cat ? CGColor(red: 0.95, green: 0.5, blue: 0.55, alpha: 1) : CGColor(red: 0.9, green: 0.45, blue: 0.5, alpha: 1))
            let nose = CGMutablePath()
            nose.move(to: CGPoint(x: -3, y: ny + 1.5)); nose.addLine(to: CGPoint(x: 3, y: ny + 1.5)); nose.addLine(to: CGPoint(x: 0, y: ny - 1.5))
            nose.closeSubpath()
            ctx.addPath(nose); ctx.fillPath()
            ctx.setFillColor(ink)
            if surprised {
                ctx.fillEllipse(in: CGRect(x: -2.5, y: ny - 9, width: 5, height: 6))
            } else {
                omega(ny - 2, happy ? 1.2 : (sleeping ? 0.7 : 0.9))
            }
        case .dog:
            let ny = h * 0.36
            ctx.fillEllipse(in: CGRect(x: -4, y: ny - 1, width: 8, height: 5.5))
            if surprised {
                ctx.fillEllipse(in: CGRect(x: -2.5, y: ny - 9, width: 5, height: 6))
            } else {
                ctx.move(to: CGPoint(x: 0, y: ny - 1)); ctx.addLine(to: CGPoint(x: 0, y: ny - 3)); ctx.strokePath()
                omega(ny - 3, happy ? 1.1 : 0.9)
                if happy {
                    ctx.setFillColor(CGColor(red: 0.95, green: 0.45, blue: 0.5, alpha: 1))
                    ctx.fillEllipse(in: CGRect(x: -3, y: ny - 10, width: 6, height: 7))
                }
            }
        case .beak:
            let by = h * 0.35
            let orange = CGColor(red: 1, green: 0.62, blue: 0.2, alpha: 1)
            let open: CGFloat = surprised || happy ? 3 : 0
            let top = CGMutablePath()
            top.move(to: CGPoint(x: -5, y: by + 1)); top.addLine(to: CGPoint(x: 5, y: by + 1)); top.addLine(to: CGPoint(x: 0, y: by - 4))
            top.closeSubpath()
            if open > 0 {
                let bottom = CGMutablePath()
                bottom.move(to: CGPoint(x: -4, y: by - 4)); bottom.addLine(to: CGPoint(x: 4, y: by - 4)); bottom.addLine(to: CGPoint(x: 0, y: by - 4 - open * 1.6))
                bottom.closeSubpath()
                fillStroke(ctx, bottom, orange, width: 1.2)
            }
            fillStroke(ctx, top, orange, width: 1.2)
        case .bill:
            // 넓적한 오리 부리. 웃거나 놀라면 벌어진다
            let by = h * 0.36
            let orange = CGColor(red: 1, green: 0.62, blue: 0.2, alpha: 1)
            let open: CGFloat = surprised || happy ? 4 : 0
            if open > 0 {
                fillStroke(ctx, ellipse(0, by - 4 - open / 2, 13, 6 + open), CGColor(red: 0.95, green: 0.45, blue: 0.3, alpha: 1), width: 1.2)
            }
            fillStroke(ctx, ellipse(0, by, 17, 8), orange, width: 1.4)
            ctx.setFillColor(inkColor)
            ctx.fillEllipse(in: CGRect(x: -3.5, y: by + 0.5, width: 1.8, height: 1.4))
            ctx.fillEllipse(in: CGRect(x: 1.7, y: by + 0.5, width: 1.8, height: 1.4))
        }
    }

    func drawZzz(base: NSRect) {
        for i in 0..<3 {
            let phase = (t * 0.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9 + CGFloat(phase) * 6, weight: .bold),
                .foregroundColor: NSColor(white: 0.35, alpha: 1 - phase),
            ]
            ("z" as NSString).draw(at: NSPoint(x: base.maxX - 4 + CGFloat(phase) * 14,
                                               y: base.maxY - 8 + CGFloat(phase) * 22), withAttributes: attrs)
        }
    }

    func drawBubble(base: NSRect, lift: CGFloat) {
        guard let text = bubbleText, let ctx = NSGraphicsContext.current?.cgContext else {
            bubbleRect = .zero
            return
        }
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(white: 0.12, alpha: 1),
            .paragraphStyle: para,
        ]
        let maxTextW = bounds.width - 40
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: maxTextW, height: 1000),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        let tw = ceil(measured.width), th = min(ceil(measured.height), 46)
        let bw = tw + 20, bh = th + 12
        let tailH: CGFloat = 7, tailW: CGFloat = 12
        let rect = CGRect(x: bounds.midX - bw / 2, y: base.maxY + 26 + lift, width: bw, height: bh)
        bubbleRect = rect.insetBy(dx: 0, dy: -tailH)

        let p = CGMutablePath()
        let r: CGFloat = 10
        p.move(to: CGPoint(x: rect.midX + tailW / 2, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: r)
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: r)
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: r)
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: r)
        p.addLine(to: CGPoint(x: rect.midX - tailW / 2, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY - tailH))
        p.closeSubpath()

        let border: NSColor
        switch mood {
        case "alert": border = NSColor(red: 0.95, green: 0.55, blue: 0.1, alpha: 1)
        case "done": border = NSColor(red: 0.35, green: 0.7, blue: 0.35, alpha: 1)
        default: border = NSColor(white: 0.7, alpha: 1)
        }
        ctx.addPath(p)
        ctx.setFillColor(NSColor(white: 1, alpha: 0.97).cgColor)
        ctx.fillPath()
        ctx.addPath(p)
        ctx.setStrokeColor(border.cgColor)
        ctx.setLineWidth(mood == "alert" || mood == "done" ? 2 : 1)
        ctx.strokePath()

        (text as NSString).draw(
            with: NSRect(x: rect.minX + 10, y: rect.minY + 6, width: tw, height: th),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }
}

// MARK: - 설치 (Claude Code 훅, 로그인 시 실행)

let env = ProcessInfo.processInfo.environment
let claudeSettingsURL = URL(fileURLWithPath: env["CLI_PET_CLAUDE_SETTINGS"]
    ?? NSHomeDirectory() + "/.claude/settings.json")
let agentURL = URL(fileURLWithPath: env["CLI_PET_LAUNCH_AGENT"]
    ?? NSHomeDirectory() + "/Library/LaunchAgents/local.cli-pet.plist")
let exePath = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
    .resolvingSymlinksInPath().path
let hookCommand = "'\(exePath)' hook"

// JSON 순서와 들여쓰기를 지키려고 JS로 편집. 이 펫이 넣은 항목만 건드림.
let hooksJS = """
const isMine = h => Array.isArray(h && h.hooks) && h.hooks.some(x =>
  typeof x.command === 'string' && /cli-pet'?\\s+hook$/.test(x.command));
function load(text) { return text.trim() ? JSON.parse(text) : {}; }
function has(text) {
  const hooks = load(text).hooks || {};
  return Object.values(hooks).some(list => Array.isArray(list) && list.some(isMine));
}
function edit(text, cmd, add) {
  const s = load(text);
  const hooks = s.hooks || {};
  for (const ev of Object.keys(hooks)) {
    if (!Array.isArray(hooks[ev])) continue;
    hooks[ev] = hooks[ev].filter(h => !isMine(h));
    if (!hooks[ev].length) delete hooks[ev];
  }
  if (add) {
    for (const ev of ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'Notification', 'Stop']) {
      const entry = ev === 'PreToolUse' ? { matcher: '*' } : {};
      entry.hooks = [{ type: 'command', command: cmd }];
      (hooks[ev] = hooks[ev] || []).push(entry);
    }
  }
  if (Object.keys(hooks).length) s.hooks = hooks; else delete s.hooks;
  return JSON.stringify(s, null, 2) + '\\n';
}
"""

enum SetupError: Error, CustomStringConvertible {
    case badSettings(String)
    var description: String {
        switch self {
        case .badSettings(let m): return "Claude 설정 파일(\(claudeSettingsURL.path))을 읽을 수 없어요: \(m)"
        }
    }
}

func callHooksJS(_ fn: String, _ args: [Any]) throws -> JSValue {
    let ctx = JSContext()!
    ctx.evaluateScript(hooksJS)
    let result = ctx.objectForKeyedSubscript(fn).call(withArguments: args)
    if let e = ctx.exception { throw SetupError.badSettings(e.toString()) }
    return result!
}

func readClaudeSettings() -> String {
    (try? String(contentsOf: claudeSettingsURL, encoding: .utf8)) ?? ""
}

func hooksInstalled() -> Bool {
    (try? callHooksJS("has", [readClaudeSettings()]).toBool()) ?? false
}

func setHooks(_ on: Bool) throws {
    let text = readClaudeSettings()
    let out = try callHooksJS("edit", [text, hookCommand, on]).toString()!
    if out == text { return }
    let fm = FileManager.default
    if fm.fileExists(atPath: claudeSettingsURL.path) {
        let backup = claudeSettingsURL.appendingPathExtension("cli-pet-backup")
        try? fm.removeItem(at: backup)
        try fm.copyItem(at: claudeSettingsURL, to: backup)
    }
    try fm.createDirectory(at: claudeSettingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try out.write(to: claudeSettingsURL, atomically: true, encoding: .utf8)
}

func loginItemOn() -> Bool { FileManager.default.fileExists(atPath: agentURL.path) }

func setLoginItem(_ on: Bool) throws {
    if !on {
        try? FileManager.default.removeItem(at: agentURL)
        return
    }
    let plist: [String: Any] = [
        "Label": "local.cli-pet",
        "ProgramArguments": [exePath],
        "RunAtLoad": true,
        "ProcessType": "Interactive",
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: agentURL, options: .atomic)
}

func runSetup(_ on: Bool, hooks: Bool = true) -> Int32 {
    do {
        if hooks || !on {
            try setHooks(on)
            print(on ? "✓ Claude Code 연결 (새로 여는 Claude Code 세션부터 적용)" : "✓ Claude Code 연결 해제")
        } else {
            print("· Claude Code 설정 파일은 건드리지 않음 (플러그인으로 연결)")
        }
        if on && hooks && FileManager.default.fileExists(atPath: claudeSettingsURL.path + ".cli-pet-backup") {
            print("  원래 설정 백업: \(claudeSettingsURL.path).cli-pet-backup")
        }
        try setLoginItem(on)
        print(on ? "✓ 로그인할 때 자동 실행" : "✓ 자동 실행 해제")
        return 0
    } catch {
        print("✗ \(error)")
        return 1
    }
}

// MARK: - 앱

func defaultOrigin(size: NSSize) -> NSPoint {
    let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    return NSPoint(x: vf.maxX - size.width - 20, y: vf.minY + 10)
}

func savedOrigin(size: NSSize) -> NSPoint? {
    guard let data = try? Data(contentsOf: posURL),
          let xy = try? JSONDecoder().decode([CGFloat].self, from: data), xy.count == 2 else { return nil }
    let o = NSPoint(x: xy[0], y: xy[1])
    let center = NSPoint(x: o.x + size.width / 2, y: o.y + 40)
    return NSScreen.screens.contains { $0.frame.contains(center) } ? o : nil
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var view: PetView!
    var lastMtime: Date?

    func applicationDidFinishLaunching(_ note: Notification) {
        let size = NSSize(width: 240, height: 230)
        let origin = savedOrigin(size: size) ?? defaultOrigin(size: size)
        panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        view = PetView(frame: NSRect(origin: .zero, size: size))
        view.packs = findPacks()
        view.selectPack(loadSelectedPackID(), announce: false)
        panel.contentView = view
        panel.orderFrontRegardless()

        lastMtime = mtime()
        view.say("안녕! 👋", 3)

        let anim = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.view.tick() }
        }
        let watch = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkStatus() }
        }
        RunLoop.main.add(anim, forMode: .common)
        RunLoop.main.add(watch, forMode: .common)
    }

    func mtime() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: statusURL.path))?[.modificationDate] as? Date
    }

    func checkStatus() {
        let m = mtime()
        guard m != lastMtime else { return }
        lastMtime = m
        guard let data = try? Data(contentsOf: statusURL),
              let s = try? JSONDecoder().decode(Status.self, from: data),
              Date().timeIntervalSince1970 - s.time < 10 else { return }
        view.apply(s)
    }
}

let usage = """
사용법:
  cli-pet            펫 띄우기
  cli-pet say <글>   펫이 말하게 하기
  cli-pet hook       Claude Code 훅용 (stdin JSON)
  명령 | cli-pet pipe 명령 출력을 펫이 보여주기
  cli-pet install    Claude Code 연결 + 로그인 시 자동 실행 (--no-hooks: 연결은 빼고)
  cli-pet uninstall  위 설정 되돌리기
"""

var args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "hook":
    runHook()
case "install":
    exit(runSetup(true, hooks: !args.contains("--no-hooks")))
case "uninstall":
    exit(runSetup(false))
case "say":
    writeStatus("say", args.dropFirst().joined(separator: " "))
case "pipe":
    runPipe()
case "-h", "--help", "help":
    print(usage)
default:
    try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    let lockFD = open(stateDir.appendingPathComponent("pet.lock").path, O_CREAT | O_RDWR, 0o644)
    if flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
        print("펫이 이미 떠 있어요.")
        exit(0)
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
