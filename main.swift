// cli-pet: 터미널 위에 떠 있는 작은 펫.
// - 인자 없이 실행: 펫 창을 띄움
// - hook: Claude Code 훅 입력(JSON, stdin)을 받아 펫에게 전달
// - say <글>: 펫이 말하게 함
// - pipe: `명령 | cli-pet pipe` 로 출력 줄을 그대로 흘려보내며 펫이 보여줌
import AppKit
import JavaScriptCore

// 펫 데이터 폴더. 테스트할 때는 CLI_PET_STATE_DIR 로 바꿀 수 있다
let stateDir = ProcessInfo.processInfo.environment["CLI_PET_STATE_DIR"].map { URL(fileURLWithPath: $0) }
    ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cli-pet")
let statusURL = stateDir.appendingPathComponent("status.json")
let posURL = stateDir.appendingPathComponent("position.json")

struct Status: Codable {
    var state: String  // idle | working | think | done | alert | say
    var text: String
    var time: Double
    var key: String? = nil            // 대사 상황 (docs/lines.md). 있으면 펫이 대사를 고른다
    var vars: [String: String]? = nil // 대사 안의 {칸}에 들어갈 값
}

func writeStatus(_ state: String, _ text: String, key: String? = nil, vars: [String: String] = [:]) {
    try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    let s = Status(state: state, text: text, time: Date().timeIntervalSince1970, key: key, vars: key == nil ? nil : vars)
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

// MARK: - 대사 (docs/lines.md)

let linesURL = stateDir.appendingPathComponent("lines.json")

// 상황, 기본 대사, 설명. 순서대로 lines.json 템플릿에 들어간다
let defaultLines: [(key: String, lines: [String], help: String)] = [
    ("hello", ["안녕! 👋"], "앱을 켰을 때, Claude Code 세션이 시작될 때"),
    ("think", ["음… 생각 중"], "Claude Code에 프롬프트를 보냈을 때"),
    ("tool.read", ["📖 {file}"], "파일 읽기 — {file}"),
    ("tool.edit", ["✏️ {file}"], "파일 수정 — {file}"),
    ("tool.run", ["$ {command}"], "명령 실행 — {command}"),
    ("tool.search", ["🔍 {pattern}"], "검색 — {pattern}"),
    ("tool.web", ["🌐 {target}"], "웹 보기·검색 — {target}"),
    ("tool.agent", ["🤖 {desc}"], "도우미 에이전트 — {desc}"),
    ("tool.todo", ["📝 할 일 정리 중"], "할 일 목록 정리"),
    ("tool.mcp", ["🔌 {name}"], "MCP 도구 — {name}"),
    ("tool.other", ["🔧 {name}"], "그 밖의 도구 — {name}"),
    ("alert", ["{message}"], "권한 요청·입력 기다림 — {message}는 Claude Code가 보낸 문장"),
    ("done", ["다 했어! ✨"], "Claude Code가 답을 끝냈을 때"),
    ("pipe.done", ["끝났어! ✨"], "cli-pet pipe 로 보던 명령이 끝났을 때"),
    ("poke", ["히히", "간지러워!", "왜~?", "놀아줘!", "♪", "헤헤", "뭐해?"], "클릭했을 때"),
    ("dizzy", ["어지러워~ 😵"], "빠르게 5번 클릭했을 때"),
    ("wake", ["으음… 왜~"], "자고 있을 때 클릭했을 때"),
    ("held", [], "들어 올렸을 때"),
    ("land", [], "내려놓았을 때"),
    ("switch", ["짠! {name}"], "펫을 바꿨을 때 — {name}"),
    ("daily.morning", ["좋은 아침! ☀️", "오늘도 잘 부탁해!", "잘 잤어?"], "그날 처음 켰을 때 (새벽 5시~오전 11시)"),
    ("daily.weekend", ["오늘은 쉬는 날! 🎉", "주말인데 일해? 대단해"], "주말에 처음 켰을 때"),
    ("daily.lunch", ["배고파… 점심 먹자 🍚", "밥 먹고 하자!", "점심 뭐 먹어?"], "점심 시간 (12시)"),
    ("daily.dinner", ["저녁 먹었어? 🍜", "배꼽시계가 울려…"], "저녁 시간 (18시)"),
    ("daily.late", ["이제 자자… 🌙", "벌써 이 시간이야, 눈 아프지 않아?", "하암… 졸려"], "자정이 넘었을 때 (한 번)"),
    ("daily.break", ["기지개 한 번 켜자 🙆", "물 한 잔 마시고 하자 💧", "잠깐 쉬었다 할까?"], "1시간 넘게 쉬지 않고 작업할 때"),
    ("daily.chatter", ["심심해~", "♪ 흥얼흥얼", "오늘 날씨 어때?", "간식 없나…", "뭐 하고 있어?", "창밖 좀 봐 봐"], "한가할 때 가끔 혼잣말"),
]

// 대사 찾는 순서: ~/.cli-pet/lines.json → 지금 팩의 pack.json "lines" → 기본 대사
final class Lines {
    nonisolated(unsafe) static let shared = Lines()
    var pack: [String: [String]] = [:]
    private var user: [String: [String]] = [:]
    private var userMtime: Date?
    private let defaults = Dictionary(uniqueKeysWithValues: defaultLines.map { ($0.key, $0.lines) })

    private func reloadIfNeeded() {
        let m = (try? FileManager.default.attributesOfItem(atPath: linesURL.path))?[.modificationDate] as? Date
        guard m != userMtime else { return }
        userMtime = m
        user = [:]
        guard let data = try? Data(contentsOf: linesURL),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        for (k, v) in obj where !k.hasPrefix("_") {
            if let one = v as? String { user[k] = [one] } else if let many = v as? [String] { user[k] = many }
        }
    }

    // 정해진 상황이면 그 대사(빈 목록이면 nil = 말하지 않음), 모르는 상황이면 fallback
    func resolve(_ key: String, _ vars: [String: String] = [:], fallback: String? = nil) -> String? {
        reloadIfNeeded()
        guard let list = user[key] ?? pack[key] ?? defaults[key] else { return fallback }
        guard var line = list.randomElement() else { return nil }
        for (k, v) in vars { line = line.replacingOccurrences(of: "{\(k)}", with: v) }
        return line.isEmpty ? nil : line
    }
}

// lines.json이 없으면 기본 대사로 채워 만든다
@discardableResult
func ensureLinesFile() -> URL {
    guard !FileManager.default.fileExists(atPath: linesURL.path) else { return linesURL }
    try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    func json(_ v: Any) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed, .withoutEscapingSlashes]), encoding: .utf8)!
    }
    var out = ["{",
               "  \"_설명\": \(json("상황마다 펫이 할 말이에요. 여러 개면 무작위로 골라요. 빈 목록 []이면 말하지 않아요. 줄을 지우면 기본 대사로 돌아가요. {file} 같은 칸은 그때의 값으로 바뀌어요. 저장하면 바로 적용돼요. 자세한 설명: https://github.com/APapeIsName/cli-pet/blob/main/docs/lines.md")),"]
    for (i, d) in defaultLines.enumerated() {
        out.append("  \(json(d.key)): \(json(d.lines))" + (i == defaultLines.count - 1 ? "" : ","))
    }
    out.append("}")
    try? (out.joined(separator: "\n") + "\n").write(to: linesURL, atomically: true, encoding: .utf8)
    return linesURL
}

// MARK: - 훅 / 명령줄 모드

// 도구마다 이름이 달라서 소문자로 맞춰 묶는다 (Claude, Codex, Copilot, Cursor, Gemini)
func toolLine(_ tool: String, _ input: [String: Any]) -> (key: String, vars: [String: String]) {
    func str(_ keys: String...) -> String {
        for k in keys {
            if let v = input[k] as? String, !v.isEmpty { return v }
            if let a = input[k] as? [String], let last = a.last { return last }  // ["bash", "-lc", "명령"]
        }
        return ""
    }
    func file(_ keys: String...) -> String {
        for k in keys { if let v = input[k] as? String, !v.isEmpty { return (v as NSString).lastPathComponent } }
        return ""
    }
    let name = tool.lowercased()
    switch name {
    case "bash", "shell", "run_shell_command", "exec_command", "local_shell", "terminal":
        return ("tool.run", ["command": clip(str("command", "cmd"), 70)])
    case "read", "read_file", "view", "read_many_files":
        return ("tool.read", ["file": file("file_path", "absolute_path", "path", "target_file")])
    case "edit", "multiedit", "write", "write_file", "replace", "notebookedit", "edit_file", "create", "str_replace_based_edit_tool":
        return ("tool.edit", ["file": file("file_path", "absolute_path", "path", "target_file", "notebook_path")])
    case "apply_patch":
        // Codex: 패치 본문의 "*** Update File: 경로" 줄에서 파일 이름을 꺼낸다
        let patch = str("command", "input", "patch")
        let f = patch.components(separatedBy: "\n").first { $0.hasPrefix("*** Update File:") || $0.hasPrefix("*** Add File:") || $0.hasPrefix("*** Delete File:") }
        let path = f.map { String($0.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces) } ?? ""
        return ("tool.edit", ["file": path.isEmpty ? "패치" : (path as NSString).lastPathComponent])
    case "grep", "glob", "grep_search", "search", "find", "list_directory", "ls":
        return ("tool.search", ["pattern": clip(str("pattern", "query", "path"), 60)])
    case "webfetch", "web_fetch":
        let url = str("url", "prompt")
        return ("tool.web", ["target": URL(string: url)?.host ?? clip(url, 60)])
    case "websearch", "web_search", "google_web_search":
        return ("tool.web", ["target": clip(str("query"), 60)])
    case "task", "agent", "spawn_agent":
        return ("tool.agent", ["desc": clip(str("description", "prompt", "task"), 60)])
    case "todowrite", "update_plan", "write_todos":
        return ("tool.todo", [:])
    default:
        if name.hasPrefix("mcp__") { return ("tool.mcp", ["name": tool.components(separatedBy: "__").last ?? tool]) }
        if name.hasPrefix("mcp:") { return ("tool.mcp", ["name": String(tool.dropFirst(4))]) }
        return ("tool.other", ["name": tool])
    }
}

// 상황 키와 함께 기본 문장도 적어 둔다 (예전 버전 앱도 읽을 수 있게)
func writeLine(_ state: String, _ key: String, _ vars: [String: String] = [:]) {
    writeStatus(state, Lines.shared.resolve(key, vars) ?? "", key: key, vars: vars)
}

let debugFlagURL = stateDir.appendingPathComponent("debug")
let hookLogURL = stateDir.appendingPathComponent("hooks.log")

// 이벤트 이름을 소문자·글자만으로 맞춘 뒤 펫의 상황으로 바꾼다
let thinkEvents: Set<String> = ["userpromptsubmit", "userpromptsubmitted", "beforesubmitprompt", "beforeagent", "promptsubmit", "preinvocation"]
let toolEvents: Set<String> = ["pretooluse", "beforetool"]
let alertEvents: Set<String> = ["notification", "permissionrequest"]
let doneEvents: Set<String> = ["stop", "agentstop", "afteragent", "agentturncomplete", "sessionidle"]

func runHook(_ options: [String]) {
    // cli-pet hook [--source 도구] [--event 이벤트] [--json]
    var forcedEvent: String?, jsonOut = false
    var i = 0
    while i < options.count {
        switch options[i] {
        case "--event": if i + 1 < options.count { forcedEvent = options[i + 1]; i += 1 }
        case "--source": i += 1
        case "--json": jsonOut = true
        default: break
        }
        i += 1
    }
    // Gemini·Cursor는 표준 출력이 JSON이어야 해서 빈 객체를 돌려준다
    defer { if jsonOut { print("{}") } }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    // 문제 찾기용: CLI_PET_HOOK_LOG=<파일> 이거나 cli-pet debug on 이면 받은 입력을 그대로 한 줄씩 남긴다
    let debugLog = FileManager.default.fileExists(atPath: debugFlagURL.path) ? hookLogURL.path : nil
    if let log = env["CLI_PET_HOOK_LOG"] ?? debugLog, let h = FileHandle(forWritingAtPath: log) ?? {
        FileManager.default.createFile(atPath: log, contents: nil); return FileHandle(forWritingAtPath: log) }() {
        h.seekToEndOfFile()
        let line = "\(Date().timeIntervalSince1970) \(options.joined(separator: " ")) " + (String(data: data, encoding: .utf8) ?? "").replacingOccurrences(of: "\n", with: " ") + "\n"
        h.write(line.data(using: .utf8)!)
        h.closeFile()
    }
    let obj = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
    let rawEvent = forcedEvent ?? (obj["hook_event_name"] as? String) ?? (obj["hookEventName"] as? String) ?? ""
    let event = rawEvent.lowercased().filter(\.isLetter)
    let toolName = (obj["tool_name"] as? String) ?? (obj["toolName"] as? String) ?? ((obj["toolCall"] as? [String: Any])?["name"] as? String) ?? ""
    var input = (obj["tool_input"] as? [String: Any]) ?? (obj["toolInput"] as? [String: Any]) ?? ((obj["toolCall"] as? [String: Any])?["args"] as? [String: Any]) ?? [:]
    if input.isEmpty, let args = obj["toolArgs"] as? String, let d = args.data(using: .utf8),
       let parsed = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
        input = parsed  // Copilot camelCase: toolArgs가 JSON 문자열
    }

    switch event {
    case "sessionstart":
        writeLine("say", "hello")
    case _ where thinkEvents.contains(event):
        writeLine("think", "think")
    case _ where toolEvents.contains(event):
        let (key, vars) = toolLine(toolName, input)
        writeLine("working", key, vars)
    case "beforeshellexecution":
        writeLine("working", "tool.run", ["command": clip((obj["command"] as? String) ?? "", 70)])
    case _ where alertEvents.contains(event):
        let message = (obj["message"] as? String) ?? (toolName.isEmpty ? "나 좀 봐줘!" : "허락이 필요해요: \(toolName)")
        writeLine("alert", "alert", ["message": clip(message)])
    case _ where doneEvents.contains(event):
        writeLine("done", "done")
    case "sessionend":
        writeStatus("idle", "")
    default:
        break
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
    writeLine("done", "pipe.done")
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
    var lines: [String: PoseFiles]?  // 이 팩만의 대사 (docs/lines.md)
    var extra: Bool?       // 추가 팩 (따로 받아서 ~/.cli-pet/packs 에 있어도 기본 팩으로 보여준다)
    var walkFacing: String?  // walk 그림이 보는 방향 "right"(기본) | "left"
    var zzz: Bool?    // true면 sleep 포즈가 있어도 zzz를 그린다
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

// ~/.cli-pet/settings.json: 고른 펫, 크기
func loadSettings() -> [String: Any] {
    guard let data = try? Data(contentsOf: settingsURL),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
    return obj
}

func saveSetting(_ key: String, _ value: Any) {
    var d = loadSettings()
    d[key] = value
    try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    if let data = try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: settingsURL, options: .atomic)
    }
}

func loadSelectedPackID() -> String { loadSettings()["pack"] as? String ?? defaultPetID }
func saveSelectedPackID(_ id: String) { saveSetting("pack", id) }

// 펫 크기. 창과 그림을 같은 배율로 키운다
let baseSize = NSSize(width: 240, height: 230)
let sizeChoices: [(label: String, scale: CGFloat)] = [("작게", 0.75), ("보통", 1.0), ("크게", 1.3), ("아주 크게", 1.6)]
func loadScale() -> CGFloat { min(2.5, max(0.5, CGFloat(loadSettings()["scale"] as? Double ?? 1))) }

// 이미 떠 있는 펫에게 명령 보내기 (보이기, 숨기기, 크기)
let commandNote = Notification.Name("local.cli-pet.command")
func postCommand(_ cmd: String) {
    DistributedNotificationCenter.default().postNotificationName(commandNote, object: cmd, userInfo: nil, deliverImmediately: true)
    usleep(150_000)
}

func petIsRunning() -> Bool {
    let fd = open(stateDir.appendingPathComponent("pet.lock").path, O_CREAT | O_RDWR, 0o644)
    defer { close(fd) }
    if flock(fd, LOCK_EX | LOCK_NB) == 0 { flock(fd, LOCK_UN); return false }
    return true
}

// MARK: - 코드로 그리는 0군 캐릭터

struct RGB {
    let r, g, b: CGFloat
    var cg: CGColor { CGColor(red: r, green: g, blue: b, alpha: 1) }
}
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> RGB { RGB(r: r, g: g, b: b) }

struct Creature {
    enum Ears { case none, pointy, floppy, round, long }
    enum Tail { case none, thin, wag, fluffy, puff, zigzag }
    enum Mouth { case smile, cat, dog, nose, beak, bill, none }
    enum Mark { case none, leaf, stripes, belly, muzzle, face }
    enum Back { case none, quills, shell }
    enum Shape { case blob, ball, keycap, block, dumpling }   // 몸 모양
    enum Click { case jump, crack, press, squish }           // 클릭했을 때 반응
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
    var earTip: RGB? = nil, earSpread: CGFloat = 0     // 귀 끝 색, 긴 귀를 바깥으로 벌리는 정도
    var cheek: RGB? = nil, cheekSize: CGFloat = 1      // 볼 색과 크기 (0이면 볼 없음)
    var nose: RGB? = nil                               // 코 색 (입이 none이면 코만 그림)
    var bow: RGB? = nil                                // 머리 리본
    var brows = false
    var shape = Shape.blob
    var click = Click.jump
    var swirl: [RGB] = []                              // 몸 무늬 띠 (왁뿌볼)
    var jelly = false                                  // 반투명 젤리 (쫀득볼)
    var steam = false                                  // 일할 때 김 (만두)
    var melts = false                                  // 잘 때 녹음 (버터)
    var cat: String? = nil                             // 분류 (없으면 새싹=original, 나머지=animal)
    var lines: [String: [String]] = [:]                // 이 캐릭터만의 대사
    var eyeColor: RGB? = nil                           // 눈동자 색 (없으면 까만 눈)
    var earColor: RGB? = nil                           // 귀 색 (없으면 몸 색)
    var tuftColor: RGB? = nil                          // 앞머리 색 (없으면 몸 아래 색)
    var category: String { cat ?? (series == "sprout" ? "original" : "animal") }
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
    // 장난감 (docs/toy-candidates.md)
    Creature(id: "toy-squishy-waxball", name: "왁뿌볼", series: "squishy", w: 58, h: 56,
             top: rgb(1.0, 0.84, 0.90), bottom: rgb(0.96, 0.70, 0.80), eyeY: 0.52,
             shape: .ball, click: .crack, swirl: [rgb(0.72, 0.93, 0.86), rgb(0.84, 0.80, 1.0)], cat: "toy",
             lines: ["poke": ["콰사삭!", "아그작!", "톡, 금 갔다", "파삭파삭"], "done": ["파사삭! 다 했어 ✨"], "hello": ["말랑말랑 안녕!"]]),
    Creature(id: "toy-clicker-keycap", name: "키캡 클리커", series: "clicker", w: 58, h: 52,
             top: rgb(0.88, 0.90, 1.0), bottom: rgb(0.70, 0.74, 0.95), eyeY: 0.6,
             shape: .keycap, click: .press, cat: "toy",
             lines: ["poke": ["딸깍!", "탁!", "딸깍딸깍", "한 번 더!"], "done": ["딸깍! 엔터 ⏎ 다 했어"], "think": ["타닥타닥… 생각 중"]]),
    Creature(id: "toy-squishy-stressball", name: "쫀득볼", series: "squishy", w: 60, h: 54,
             top: rgb(0.70, 0.92, 0.98), bottom: rgb(0.45, 0.78, 0.93), eyeY: 0.5,
             shape: .ball, click: .squish, jelly: true, cat: "toy",
             lines: ["poke": ["쪼물쪼물…", "말랑~", "쭈우욱", "천천히 돌아간다…"], "dizzy": ["너무 주물렀어~ 🫠"]]),
    Creature(id: "toy-snack-dumpling", name: "만두 말랑이", series: "snack", w: 66, h: 46,
             top: rgb(1.0, 0.99, 0.95), bottom: rgb(0.95, 0.91, 0.84), eyeY: 0.42, eyeGap: 0.16,
             shape: .dumpling, steam: true, cat: "toy",
             lines: ["poke": ["말랑 만두!", "갓 쪘어~", "모락모락"], "done": ["다 쪄졌어! 🥟"], "daily.lunch": ["만두 먹을 시간… 나 말고!"]]),
    Creature(id: "toy-squishy-butter", name: "버터 말랑이", series: "squishy", w: 66, h: 44,
             top: rgb(1.0, 0.95, 0.66), bottom: rgb(0.98, 0.87, 0.48), eyeY: 0.6,
             shape: .block, melts: true, cat: "toy",
             lines: ["poke": ["부드럽지?", "스르륵~", "빵에 발라 줘"], "sleep": [], "wake": ["녹는 줄 알았어…"]]),
]
let defaultPetID = "original-sprout"

// MARK: - 분류 (docs/pack-format.md)

let categoryOrder: [(id: String, label: String)] = [
    ("original", "자체 캐릭터"), ("toy", "장난감"), ("animal", "동물"), ("dev", "개발"), ("game", "게임"),
    ("anime", "애니·만화·일러스트"), ("virtual", "보컬로이드·버추얼"), ("brand", "브랜드"),
    ("meme", "밈"), ("public", "공공 캐릭터"), ("etc", "기타"),
]
let seriesLabels = ["sprout": "새싹", "real": "실제 동물 (자체)", "squishy": "말랑이", "clicker": "딸깍이", "snack": "간식 말랑이"]

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
    var scale: CGFloat = 1
    var hideTimer: Timer?

    // 일상 대사
    var lastDailyCheck = 0.0
    var firedToday: Set<String> = []
    var dailyDay = ""
    var workStreakStart: Double?
    var lastBreakAt = -1e9
    var nextChatter = CACurrentMediaTime() + Double.random(in: 600...1200)

    // 장난감 반응
    var crackAt = -10.0
    var pressAt = -10.0
    var squishAt = -10.0

    // 돌아다니기
    var walking = false
    var walkDir: CGFloat = 1
    var walkTargetX: CGFloat = 0
    var nextWalk = CACurrentMediaTime() + Double.random(in: 20...50)
    var lastTick = CACurrentMediaTime()
    // 배율을 뺀 논리 좌표의 크기 (그리기는 이 크기 기준)
    var lb: NSRect { NSRect(x: 0, y: 0, width: bounds.width / scale, height: bounds.height / scale) }

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
        return NSRect(x: lb.midX - w / 2, y: 16, width: w, height: h)
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
        Lines.shared.pack = pack.map { ($0.info.lines ?? [:]).mapValues { $0.files } } ?? creature.lines
        if announce { jumpAt = t; sayLine("switch", ["name": pack?.info.name ?? creature.name], for: 2.5) }
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
                            group: $0.info.group ?? 1, isUser: $0.isUser && $0.info.extra != true)
        }
    }
    // 5분 동안 아무 일 없으면 잠든다
    var sleeping: Bool { mood == "idle" && bubbleText == nil && !walking && t - lastEvent > 300 }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func tick() {
        t = CACurrentMediaTime()
        let dt = min(0.1, t - lastTick)
        lastTick = t
        if t - lastDailyCheck > 1 { lastDailyCheck = t; checkDaily() }
        updateWalk(dt)
        if t > nextBlink { blinkAt = t; nextBlink = t + Double.random(in: 2...5) }
        if bubbleText != nil && t > bubbleUntil { bubbleText = nil }
        let age = t - moodSince
        if (mood == "done" || mood == "say") && age > 6 { mood = "idle" }
        if mood == "alert" && age > 30 { mood = "idle" }
        if (mood == "working" || mood == "think") && t - lastEvent > 180 { mood = "idle"; bubbleText = nil }
        needsDisplay = true
    }

    func apply(_ s: Status) {
        if walking { stopWalk() }
        if s.state == "working" || s.state == "think" {
            // 15분 넘게 조용했으면 새 작업 흐름으로 본다
            if workStreakStart == nil || t - lastEvent > 15 * 60 { workStreakStart = t }
        }
        mood = s.state
        moodSince = t
        lastEvent = t
        let text = s.key.map { Lines.shared.resolve($0, s.vars ?? [:], fallback: s.text) ?? "" } ?? s.text
        if text.isEmpty {
            bubbleText = nil
        } else {
            bubbleText = text
            bubbleUntil = t + (s.state == "working" || s.state == "think" ? 60 : s.state == "alert" ? 30 : 6)
        }
        if s.state == "done" {
            happyUntil = t + 3
            if pack == nil && creature.click == .crack { crackAt = t }
            if pack == nil && creature.click == .press { pressAt = t }
        }
    }

    func say(_ s: String, _ dur: Double) { bubbleText = s; bubbleUntil = t + dur }

    // 상황 키로 말하기. 대사가 비어 있으면 조용히 있는다
    func sayLine(_ key: String, _ vars: [String: String] = [:], for dur: Double) {
        if let text = Lines.shared.resolve(key, vars) { say(text, dur) }
    }

    // MARK: 일상 대사 (docs/lines.md)

    var now: () -> Date = Date.init  // 시험할 때 시각을 바꿔 넣는다

    var busy: Bool { mood == "working" || mood == "think" || mood == "alert" || dragging }

    // 그날 처음 켰을 때 인사: 주말 → daily.weekend, 아침 → daily.morning, 그 밖 → hello
    func greetOnLaunch() {
        let now = now()
        let today = dayString(now)
        let first = (loadSettings()["lastDay"] as? String) != today
        saveSetting("lastDay", today)
        guard dailyOn() && first else { sayLine("hello", for: 3); return }
        let cal = Calendar.current
        if cal.isDateInWeekend(now) {
            sayLine("daily.weekend", for: 4)
        } else if (5..<11).contains(cal.component(.hour, from: now)) {
            sayLine("daily.morning", for: 4)
        } else {
            sayLine("hello", for: 3)
        }
        jumpAt = t
    }

    func checkDaily() {
        guard dailyOn(), petVisible else { return }
        let now = now()
        let day = dayString(now)
        if day != dailyDay { dailyDay = day; firedToday = [] }
        let hour = Calendar.current.component(.hour, from: now)
        func once(_ key: String, _ dur: Double) -> Bool {
            guard !firedToday.contains(key), !busy, bubbleText == nil else { return false }
            firedToday.insert(key)
            sayLine(key, for: dur)
            jumpAt = t
            lastEvent = t
            return true
        }
        if hour == 12 && once("daily.lunch", 5) { return }
        if hour == 18 && once("daily.dinner", 5) { return }
        if (0..<4).contains(hour) && once("daily.late", 5) { return }
        // 오래 쉬지 않고 작업 중이면 쉬자고 한다 (한 시간에 한 번)
        if let start = workStreakStart {
            if t - lastEvent > 15 * 60 {
                workStreakStart = nil
            } else if t - start > 60 * 60 && t - lastBreakAt > 60 * 60 && mood != "alert" && bubbleText == nil {
                lastBreakAt = t
                workStreakStart = t
                sayLine("daily.break", for: 5)
                return
            }
        }
        // 한가할 때 가끔 혼잣말
        if t > nextChatter {
            nextChatter = t + Double.random(in: 600...1500)
            if !busy && !sleeping && !walking && bubbleText == nil && t - lastEvent > 60 { sayLine("daily.chatter", for: 4) }
        }
    }

    // MARK: 돌아다니기

    func updateWalk(_ dt: Double) {
        guard let w = window, w.isVisible else { return }
        if walking {
            if dragging || busy { stopWalk(); return }
            var f = w.frame
            let step = walkDir * 28 * scale * CGFloat(dt)
            if (walkDir > 0 && f.origin.x + step >= walkTargetX) || (walkDir < 0 && f.origin.x + step <= walkTargetX) {
                f.origin.x = walkTargetX
                w.setFrameOrigin(f.origin)
                stopWalk()
            } else {
                f.origin.x += step
                w.setFrameOrigin(f.origin)
            }
            return
        }
        guard walkOn(), t > nextWalk else { return }
        nextWalk = t + Double.random(in: 25...70)
        guard !busy, !sleeping, bubbleText == nil, t - jumpAt > 1, mood == "idle" || mood == "say" || mood == "done" else { return }
        let vf = (w.screen ?? NSScreen.main)?.visibleFrame ?? w.frame
        // 펫 몸이 화면 밖으로 나가지 않게, 창의 투명한 가장자리는 넘어가도 된다
        let half = petRect.width / 2 * scale + 8
        let minX = vf.minX - (w.frame.width / 2 - half), maxX = vf.maxX - w.frame.width / 2 - half
        guard maxX > minX else { return }
        var dir: CGFloat = Bool.random() ? 1 : -1
        let dist = CGFloat.random(in: 40...150) * scale
        if w.frame.minX + dir * dist > maxX || w.frame.minX + dir * dist < minX { dir = -dir }
        let target = min(maxX, max(minX, w.frame.minX + dir * dist))
        guard abs(target - w.frame.minX) > 10 else { return }
        walkDir = dir
        walkTargetX = target
        walking = true
    }

    func stopWalk() {
        guard walking else { return }
        walking = false
        savePosition()
    }

    // 걷는 방향으로 그림을 뒤집을지. 코드 캐릭터는 꼬리가 오른쪽이라 왼쪽을 보는 셈
    var flipForWalk: Bool {
        guard walking else { return false }
        if let pack {
            guard pack.has("walk") else { return false }
            let facesLeft = pack.info.walkFacing == "left"
            return (walkDir < 0) != facesLeft
        }
        return walkDir > 0
    }

    func poke() {
        let wasSleeping = sleeping
        if walking { stopWalk() }
        lastEvent = t
        clickTimes = clickTimes.filter { t - $0 < 1.5 } + [t]
        if clickTimes.count >= 5 {
            clickTimes.removeAll()
            dizzyUntil = t + 2.5
            sayLine("dizzy", for: 2.5)
            return
        }
        switch pack == nil ? creature.click : .jump {
        case .jump: jumpAt = t
        case .crack: jumpAt = t; crackAt = t
        case .press: pressAt = t
        case .squish: squishAt = t
        }
        happyUntil = t + 1
        if wasSleeping {
            sayLine("wake", for: 2)
        } else if mood != "working" && mood != "think" && mood != "alert" {
            sayLine("poke", for: 1.8)
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
        if hypot(dx, dy) > 3 && !dragged { dragged = true; dragging = true; stopWalk(); sayLine("held", for: 1.5) }
        if dragged { window?.setFrameOrigin(NSPoint(x: downOrigin.x + dx, y: downOrigin.y + dy)) }
    }

    override func mouseUp(with e: NSEvent) {
        if dragged {
            dragging = false
            jumpAt = t - jumpDur  // 착지 찌그러짐만 재생
            sayLine("land", for: 1.5)
            savePosition()
            return
        }
        let raw = convert(e.locationInWindow, from: nil)
        let p = NSPoint(x: raw.x / scale, y: raw.y / scale)
        if bubbleText != nil && bubbleRect.contains(p) {
            bubbleText = nil
        } else {
            poke()
        }
    }

    override func rightMouseDown(with e: NSEvent) {
        NSMenu.popUpContextMenu(buildMenu(forStatusBar: false), with: e, for: self)
    }

    var petVisible: Bool { window?.isVisible ?? false }

    // 펫 오른쪽 클릭 메뉴와 메뉴 막대 아이콘 메뉴가 같이 쓴다
    func buildMenu(forStatusBar: Bool) -> NSMenu {
        let menu = NSMenu()
        if forStatusBar {
            let toggle = NSMenuItem(title: petVisible ? "펫 숨기기" : "펫 보이기", action: #selector(toggleVisible), keyEquivalent: "")
            toggle.target = self
            menu.addItem(toggle)
            menu.addItem(.separator())
        }
        let reset = NSMenuItem(title: "구석으로 보내기", action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(packMenuItem())
        let lines = NSMenuItem(title: "대사 바꾸기…", action: #selector(editLines), keyEquivalent: "")
        lines.target = self
        menu.addItem(lines)
        menu.addItem(sizeMenuItem())
        menu.addItem(.separator())
        if !forStatusBar || petVisible {
            for (title, sel) in [("숨기기", #selector(hidePet)), ("30분 동안 숨기기", #selector(hidePet30))] {
                let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            }
        }
        let hint = NSMenuItem(title: statusBarOn() ? "다시 부르기: 메뉴 막대의 🌱 아이콘" : "다시 부르기: CLIPet 다시 열기 또는 cli-pet show",
                              action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        if let pack, let credit = pack.info.credit {
            let line = [credit, pack.info.license].compactMap { $0 }.joined(separator: " · ")
            let info = NSMenuItem(title: "그림: " + line, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }
        menu.addItem(.separator())
        menu.addItem(connectMenuItem())
        let login = NSMenuItem(title: "로그인할 때 자동 실행", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = loginItemOn() ? .on : .off
        menu.addItem(login)
        for (title, key, sel) in [("일상 대사", "daily", #selector(toggleDaily)), ("돌아다니기", "walk", #selector(toggleWalk))] {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.target = self
            item.state = (loadSettings()[key] as? Bool ?? true) ? .on : .off
            menu.addItem(item)
        }
        let bar = NSMenuItem(title: "메뉴 막대에 아이콘 보이기", action: #selector(toggleStatusBar), keyEquivalent: "")
        bar.target = self
        bar.state = statusBarOn() ? .on : .off
        menu.addItem(bar)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        return menu
    }

    @objc func toggleDaily() {
        let on = !dailyOn()
        saveSetting("daily", on)
        say(on ? "이제 가끔 말 걸게!" : "조용히 있을게", 3)
    }

    @objc func toggleWalk() {
        let on = !walkOn()
        saveSetting("walk", on)
        if !on { stopWalk() }
        say(on ? "산책 다녀올게~" : "가만히 있을게", 3)
    }

    @objc func toggleVisible() {
        if petVisible { hide(for: nil) } else { show() }
    }

    @objc func toggleStatusBar() {
        let on = !statusBarOn()
        saveSetting("statusBar", on)
        (NSApp.delegate as? AppDelegate)?.updateStatusItem()
        if !on { say("아이콘은 숨겼어. 다시 켜려면 여기서!", 3) }
    }

    // 펫 바꾸기 ▸ 기본 팩 / 커스텀 팩 ▸ 분류 ▸ (시리즈 ▸) 펫
    func packMenuItem() -> NSMenuItem {
        packs = findPacks().map { found in packs.first { $0.info.id == found.info.id && $0.dir == found.dir } ?? found }
        let current = pack?.info.id ?? creature.id
        let all = entries
        let root = NSMenu()
        func petItem(_ e: PetEntry) -> NSMenuItem {
            let item = NSMenuItem(title: e.group == 3 ? e.name + "  · 비상업" : e.name, action: #selector(pickPack(_:)), keyEquivalent: "")
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
        func tree(_ list: [PetEntry]) -> [NSMenuItem] {
            var out: [NSMenuItem] = []
            for (cat, label) in categoryOrder {
                let inCat = list.filter { $0.category == cat }
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
                out.append(folder(label, items))
            }
            return out
        }
        func header(_ title: String) {
            let h = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            h.isEnabled = false
            root.addItem(h)
        }
        header("기본 팩")
        tree(all.filter { !$0.isUser }).forEach(root.addItem)
        let extras = extraPackList().filter { !extraInstalled($0.id) }
        if !extras.isEmpty {
            let sub = NSMenu()
            var bySeries: [(String, [ExtraPack])] = []
            for e in extras {
                let key = e.seriesName ?? "기타"
                if let i = bySeries.firstIndex(where: { $0.0 == key }) { bySeries[i].1.append(e) } else { bySeries.append((key, [e])) }
            }
            for (series, list) in bySeries {
                let h = NSMenuItem(title: series, action: nil, keyEquivalent: "")
                h.isEnabled = false
                sub.addItem(h)
                for e in list {
                    let item = NSMenuItem(title: e.name, action: #selector(getExtra(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = e.id
                    item.indentationLevel = 1
                    sub.addItem(item)
                }
                let all = NSMenuItem(title: "모두 받기 (\(list.count)개)", action: #selector(getExtraSeries(_:)), keyEquivalent: "")
                all.target = self
                all.representedObject = list.map(\.id)
                all.indentationLevel = 1
                sub.addItem(all)
            }
            let item = NSMenuItem(title: "추가 팩 받기", action: nil, keyEquivalent: "")
            item.submenu = sub
            root.addItem(item)
        }
        root.addItem(.separator())
        header("커스텀 팩")
        let custom = tree(all.filter { $0.isUser })
        if custom.isEmpty {
            let none = NSMenuItem(title: "아직 없어요", action: nil, keyEquivalent: "")
            none.isEnabled = false
            root.addItem(none)
        } else {
            custom.forEach(root.addItem)
        }
        let open = NSMenuItem(title: "커스텀 팩 폴더 열기…", action: #selector(openUserPacks), keyEquivalent: "")
        open.target = self
        root.addItem(open)
        let help = NSMenuItem(title: "커스텀 팩 만드는 법…", action: #selector(openPackHelp), keyEquivalent: "")
        help.target = self
        root.addItem(help)
        root.addItem(.separator())
        let credits = NSMenuItem(title: "크레딧 보기…", action: #selector(openCredits), keyEquivalent: "")
        credits.target = self
        root.addItem(credits)
        let item = NSMenuItem(title: "펫 바꾸기", action: nil, keyEquivalent: "")
        item.submenu = root
        return item
    }

    func sizeMenuItem() -> NSMenuItem {
        let sub = NSMenu()
        for (label, s) in sizeChoices {
            let item = NSMenuItem(title: label, action: #selector(pickSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s
            item.state = abs(s - scale) < 0.01 ? .on : .off
            sub.addItem(item)
        }
        let item = NSMenuItem(title: "크기", action: nil, keyEquivalent: "")
        item.submenu = sub
        return item
    }

    @objc func pickSize(_ sender: NSMenuItem) {
        applyScale(sender.representedObject as? CGFloat ?? 1, save: true)
    }

    // 바닥 가운데를 기준으로 창 크기를 바꾼다
    func applyScale(_ s: CGFloat, save: Bool) {
        let s = min(2.5, max(0.5, s))
        scale = s
        if let w = window {
            let old = w.frame
            let size = NSSize(width: baseSize.width * s, height: baseSize.height * s)
            w.setFrame(NSRect(x: old.midX - size.width / 2, y: old.minY, width: size.width, height: size.height), display: true)
        }
        needsDisplay = true
        if save { saveSetting("scale", Double(s)); savePosition() }
    }

    @objc func hidePet() { hide(for: nil) }
    @objc func hidePet30() { hide(for: 30 * 60) }

    func hide(for seconds: Double?) {
        hideTimer?.invalidate()
        hideTimer = nil
        window?.orderOut(nil)
        if let seconds {
            let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.show() }
            }
            RunLoop.main.add(timer, forMode: .common)
            hideTimer = timer
        }
    }

    func show() {
        hideTimer?.invalidate()
        hideTimer = nil
        let wasHidden = window?.isVisible == false
        window?.orderFrontRegardless()
        if wasHidden { jumpAt = t; sayLine("hello", for: 2) }
    }

    @objc func editLines() {
        let url = ensureLinesFile()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-e", url.path]  // 텍스트 편집기로 연다
        try? p.run()
        say("저장하면 바로 바뀌어요", 3)
    }

    @objc func openCredits() {
        NSWorkspace.shared.open(URL(string: "https://github.com/APapeIsName/cli-pet/blob/main/CREDITS.md")!)
    }

    @objc func getExtra(_ sender: NSMenuItem) { fetchExtras([sender.representedObject as? String ?? ""]) }
    @objc func getExtraSeries(_ sender: NSMenuItem) { fetchExtras(sender.representedObject as? [String] ?? []) }

    // 받는 동안 앱이 멈추지 않게 뒤에서 받는다
    func fetchExtras(_ ids: [String]) {
        let list = extraPackList().filter { ids.contains($0.id) }
        guard !list.isEmpty else { return }
        say("추가 팩 받는 중… (\(list.count)개)", 30)
        DispatchQueue.global().async {
            var failed = 0
            for p in list { if (try? downloadExtra(p)) == nil { failed += 1 } }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.packs = findPacks()
                    if failed == 0 {
                        self.say("받았어! 펫 바꾸기에서 골라 봐 🎁", 4)
                    } else {
                        self.say("\(failed)개는 못 받았어 (인터넷 확인)", 4)
                    }
                }
            }
        }
    }

    @objc func openPackHelp() {
        NSWorkspace.shared.open(URL(string: "https://github.com/APapeIsName/cli-pet/blob/main/docs/custom-packs.md")!)
    }

    @objc func pickPack(_ sender: NSMenuItem) {
        selectPack(sender.representedObject as? String ?? defaultPetID, announce: true)
    }

    @objc func openUserPacks() {
        let dir = stateDir.appendingPathComponent("packs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    func connectMenuItem() -> NSMenuItem {
        let sub = NSMenu()
        for t in targets {
            let installed = targetInstalled(t)
            var title = t.name
            if case .viaClaude = t.kind { title += "  · Claude Code 연결로 동작" } else if !installed { title += "  · 설치 안 됨" }
            let item = NSMenuItem(title: title, action: #selector(toggleTarget(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = t.id
            item.state = isConnected(t) ? .on : .off
            if case .viaClaude = t.kind { item.action = nil; item.isEnabled = false }
            sub.addItem(item)
        }
        sub.addItem(.separator())
        let help = NSMenuItem(title: "다른 도구 연결하는 법…", action: #selector(openIntegrations), keyEquivalent: "")
        help.target = self
        sub.addItem(help)
        let item = NSMenuItem(title: "AI 도구 연결", action: nil, keyEquivalent: "")
        item.submenu = sub
        if targets.contains(where: isConnected) { item.state = .on }
        return item
    }

    @objc func toggleTarget(_ sender: NSMenuItem) {
        guard let t = target(sender.representedObject as? String ?? "") else { return }
        let on = !isConnected(t)
        do {
            try setConnected(t, on)
            say(on ? "\(t.name) 따라다닐게! " + (t.id == "codex" ? "(Codex에서 /hooks 로 신뢰해 줘)" : "(새 세션부터)") : "\(t.name) 연결 끊었어", 5)
        } catch {
            say("설정 파일을 못 읽었어 😢", 4)
        }
    }

    @objc func openIntegrations() {
        NSWorkspace.shared.open(URL(string: "https://github.com/APapeIsName/cli-pet/blob/main/docs/integrations.md")!)
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
        ctx.scaleBy(x: scale, y: scale)
        let base = petRect
        let dizzy = t < dizzyUntil
        let happy = t < happyUntil || mood == "say"
        let age = t - moodSince

        var dx: CGFloat = 0, dy: CGFloat = 0, sx: CGFloat = 1, sy: CGFloat = 1, rot: CGFloat = 0
        switch mood {
        case _ where dragging:
            rot = CGFloat(sin(t * 5)) * 0.12
        case _ where walking:
            // 종종걸음: 통통 튀면서 살짝 흔들린다
            dy = CGFloat(abs(sin(t * 9))) * 3
            rot = CGFloat(sin(t * 9)) * 0.04
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

        // 장난감 반응 (코드 캐릭터만)
        if pack == nil {
            switch creature.click {
            case .press:
                // 작업 중엔 타이핑하듯 딸깍딸깍, 클릭·완료 땐 크게 한 번
                if mood == "working" || mood == "think" {
                    dy = 0
                    let ph = (t * 4.5).truncatingRemainder(dividingBy: 1)
                    if ph < 0.3 { sy *= 1 - 0.1 * CGFloat(sin(ph / 0.3 * .pi)) }
                }
                let pp = t - pressAt
                if pp >= 0 && pp < 0.35 { sy *= 1 - 0.24 * CGFloat(sin(pp / 0.35 * .pi)); sx *= 1 + 0.04 * CGFloat(sin(pp / 0.35 * .pi)) }
            case .squish:
                // 꾹 눌렸다가 아주 천천히 돌아온다
                let sp = t - squishAt
                if sp >= 0 && sp < 1.6 {
                    let k = CGFloat(sp < 0.12 ? sp / 0.12 : pow(1 - (sp - 0.12) / 1.48, 2))
                    sx *= 1 + 0.38 * k
                    sy *= 1 - 0.42 * k
                }
            default: break
            }
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
        ctx.scaleBy(x: flipForWalk ? -sx : sx, y: sy)
        if let pack {
            drawPack(ctx, pack, pose: currentPose(dizzy: dizzy, happy: happy))
        } else {
            drawBody(ctx, dizzy: dizzy, happy: happy)
        }
        ctx.restoreGState()

        if sleeping && (pack?.has("sleep") != true || pack?.info.zzz == true) { drawZzz(base: base) }
    }

    func currentPose(dizzy: Bool, happy: Bool) -> String {
        if dragging { return "held" }
        if walking { return "walk" }
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
        let fit = min(1, (lb.width - 16) / w, (pack.info.size ?? 80) * 1.4 / h)
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

        // 버터는 잘 때 녹아서 퍼진다
        let melt: CGFloat = c.melts && sleeping ? min(1, CGFloat(t - lastEvent - 300) / 8) : 0
        if melt > 0 {
            fillStroke(ctx, ellipse(0, 1, c.w * (1 + 0.45 * melt), 11 * melt), c.bottom.cg, width: 1.4)
            ctx.scaleBy(x: 1 + 0.12 * melt, y: 1 - 0.18 * melt)
        }
        if c.steam && (mood == "working" || mood == "think" || mood == "done") { drawSteam(ctx, c) }

        // 몸
        let body = bodyPath(c)
        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        let top = c.jelly ? c.top.cg.copy(alpha: 0.82)! : c.top.cg
        let bottom = c.jelly ? c.bottom.cg.copy(alpha: 0.9)! : c.bottom.cg
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top, bottom] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])
        drawMarks(ctx, c)
        drawToyDetails(ctx, c)
        ctx.restoreGState()

        ctx.addPath(body)
        ctx.setStrokeColor(ink)
        ctx.setLineWidth(2)
        ctx.strokePath()
        if c.shape == .keycap { drawKeycapTop(ctx, c) }
        if c.shape == .dumpling { drawPleats(ctx, c) }
        if c.click == .crack { drawCracks(ctx, c) }

        if c.ears == .floppy { drawEars(ctx, c) }
        if let f = c.feet { drawFeet(ctx, w, f.cg) }

        // 반짝이 (젤리·공은 더 크게)
        ctx.setFillColor(NSColor(white: 1, alpha: c.jelly ? 0.7 : 0.55).cgColor)
        if c.shape == .ball {
            ctx.fillEllipse(in: CGRect(x: -w * 0.3, y: h * 0.62, width: c.jelly ? 15 : 12, height: c.jelly ? 10 : 8))
            if c.jelly { ctx.fillEllipse(in: CGRect(x: w * 0.18, y: h * 0.22, width: 5, height: 4)) }
        } else if c.shape != .keycap {
            ctx.fillEllipse(in: CGRect(x: -w * 0.32, y: h * (c.shape == .dumpling ? 0.5 : 0.66), width: 10, height: 6))
        }

        // 볼
        if c.cheekSize > 0 {
            ctx.setFillColor(c.cheek.map { $0.cg.copy(alpha: 0.9)! } ?? NSColor(red: 1, green: 0.45, blue: 0.5, alpha: 0.45).cgColor)
            let cw = 9 * c.cheekSize, ch = 5 * c.cheekSize
            ctx.fillEllipse(in: CGRect(x: -w * 0.36 - cw / 2, y: h * 0.325 - ch / 2, width: cw, height: ch))
            ctx.fillEllipse(in: CGRect(x: w * 0.36 - cw / 2, y: h * 0.325 - ch / 2, width: cw, height: ch))
        }
        if let bow = c.bow { drawBow(ctx, c, bow.cg) }
        if c.brows { drawBrows(ctx, c) }

        if c.whiskers { drawWhiskers(ctx, c) }
        drawEyes(ctx, c, dizzy: dizzy, happy: happyFace)
        drawMouth(ctx, c, dizzy: dizzy, happy: happyFace)
    }

    var inkColor: CGColor { CGColor(red: 0.28, green: 0.14, blue: 0.10, alpha: 1) }

    // MARK: 장난감 모양

    func bodyPath(_ c: Creature) -> CGPath {
        let w = c.w, h = c.h
        switch c.shape {
        case .ball:
            return CGPath(ellipseIn: CGRect(x: -w / 2, y: 0, width: w, height: h), transform: nil)
        case .keycap:
            return CGPath(roundedRect: CGRect(x: -w / 2, y: 0, width: w, height: h), cornerWidth: 11, cornerHeight: 11, transform: nil)
        case .block:
            return CGPath(roundedRect: CGRect(x: -w / 2, y: 0, width: w, height: h), cornerWidth: 8, cornerHeight: 8, transform: nil)
        case .dumpling:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -w / 2, y: h * 0.22))
            p.addCurve(to: CGPoint(x: w / 2, y: h * 0.22), control1: CGPoint(x: -w * 0.42, y: h * 1.28), control2: CGPoint(x: w * 0.42, y: h * 1.28))
            p.addCurve(to: CGPoint(x: -w / 2, y: h * 0.22), control1: CGPoint(x: w * 0.36, y: -h * 0.08), control2: CGPoint(x: -w * 0.36, y: -h * 0.08))
            p.closeSubpath()
            return p
        case .blob:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -w / 2, y: h * 0.35))
            p.addCurve(to: CGPoint(x: 0, y: h), control1: CGPoint(x: -w / 2, y: h * 0.85), control2: CGPoint(x: -w * 0.28, y: h))
            p.addCurve(to: CGPoint(x: w / 2, y: h * 0.35), control1: CGPoint(x: w * 0.28, y: h), control2: CGPoint(x: w / 2, y: h * 0.85))
            p.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: w / 2, y: h * 0.06), control2: CGPoint(x: w * 0.3, y: 0))
            p.addCurve(to: CGPoint(x: -w / 2, y: h * 0.35), control1: CGPoint(x: -w * 0.3, y: 0), control2: CGPoint(x: -w / 2, y: h * 0.06))
            p.closeSubpath()
            return p
        }
    }

    // 몸 안쪽 무늬 (몸 모양으로 잘린 상태에서 그린다)
    func drawToyDetails(_ ctx: CGContext, _ c: Creature) {
        let w = c.w, h = c.h
        // 왁뿌볼: 파스텔 소용돌이 띠
        for (i, color) in c.swirl.enumerated() {
            let p = CGMutablePath()
            let y0 = h * (0.3 + 0.28 * CGFloat(i))
            p.move(to: CGPoint(x: -w * 0.6, y: y0))
            p.addCurve(to: CGPoint(x: w * 0.6, y: y0 + h * 0.12), control1: CGPoint(x: -w * 0.2, y: y0 + h * 0.3), control2: CGPoint(x: w * 0.2, y: y0 - h * 0.25))
            ctx.addPath(p)
            ctx.setStrokeColor(color.cg.copy(alpha: 0.85)!)
            ctx.setLineWidth(h * 0.14)
            ctx.strokePath()
        }
        // 버터: 아래쪽을 감싼 은박지
        if c.shape == .block {
            let foil = CGMutablePath()
            foil.move(to: CGPoint(x: -w / 2 - 2, y: h * 0.22))
            let n = 9
            for i in 0...n {
                let x = -w / 2 + w * CGFloat(i) / CGFloat(n)
                foil.addLine(to: CGPoint(x: x, y: h * (i % 2 == 0 ? 0.22 : 0.16)))
            }
            foil.addLine(to: CGPoint(x: w / 2 + 2, y: -2))
            foil.addLine(to: CGPoint(x: -w / 2 - 2, y: -2))
            foil.closeSubpath()
            ctx.addPath(foil)
            let silver = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: [CGColor(gray: 0.93, alpha: 1), CGColor(gray: 0.72, alpha: 1)] as CFArray, locations: [0, 1])!
            ctx.saveGState(); ctx.clip()
            ctx.drawLinearGradient(silver, start: CGPoint(x: 0, y: h * 0.22), end: CGPoint(x: 0, y: 0), options: [])
            ctx.restoreGState()
            ctx.setStrokeColor(CGColor(gray: 0.6, alpha: 0.8)); ctx.setLineWidth(0.8)
            for x in [-0.3, -0.05, 0.22] as [CGFloat] {
                ctx.move(to: CGPoint(x: w * x, y: h * 0.15)); ctx.addLine(to: CGPoint(x: w * x + 2, y: h * 0.03))
            }
            ctx.strokePath()
        }
    }

    // 키캡: 윗면(살짝 들어간 면)
    func drawKeycapTop(_ ctx: CGContext, _ c: Creature) {
        let w = c.w, h = c.h
        let face = CGPath(roundedRect: CGRect(x: -w / 2 + 6, y: h * 0.2, width: w - 12, height: h * 0.74), cornerWidth: 8, cornerHeight: 8, transform: nil)
        ctx.addPath(face)
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(red: 0.97, green: 0.97, blue: 1, alpha: 1), c.top.cg] as CFArray, locations: [0, 1])!
        ctx.saveGState(); ctx.clip()
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h * 0.2), options: [])
        ctx.restoreGState()
        ctx.addPath(face); ctx.setStrokeColor(inkColor.copy(alpha: 0.35)!); ctx.setLineWidth(1.2); ctx.strokePath()
        ctx.setFillColor(NSColor(white: 1, alpha: 0.8).cgColor)
        ctx.fillEllipse(in: CGRect(x: -w / 2 + 10, y: h * 0.8, width: 9, height: 4))
    }

    // 만두: 윗부분 주름
    func drawPleats(_ ctx: CGContext, _ c: Creature) {
        let w = c.w, h = c.h
        ctx.setStrokeColor(inkColor.copy(alpha: 0.55)!)
        ctx.setLineWidth(1.4)
        for x in [-0.22, -0.08, 0.06, 0.2] as [CGFloat] {
            ctx.move(to: CGPoint(x: w * x, y: h * 1.01))
            ctx.addQuadCurve(to: CGPoint(x: w * x + 4, y: h * 0.8), control: CGPoint(x: w * x + 5, y: h * 0.95))
        }
        ctx.strokePath()
    }

    // 만두: 김 모락모락
    func drawSteam(_ ctx: CGContext, _ c: Creature) {
        let h = c.h
        ctx.setLineWidth(2)
        for i in 0..<3 {
            let ph = (t * 0.7 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let x = CGFloat(i - 1) * 12 + CGFloat(sin(t * 2 + Double(i))) * 2
            let y = h * 1.0 + CGFloat(ph) * 18
            ctx.setStrokeColor(CGColor(gray: 0.65, alpha: 0.6 * (1 - ph)))
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addCurve(to: CGPoint(x: x, y: y + 10), control1: CGPoint(x: x + 4, y: y + 3), control2: CGPoint(x: x - 4, y: y + 7))
            ctx.strokePath()
        }
    }

    // 왁뿌볼: 클릭하거나 일이 끝나면 금이 가고 조각이 튄다
    func drawCracks(_ ctx: CGContext, _ c: Creature) {
        let age = t - crackAt
        guard age >= 0 && age < 1.6 else { return }
        let w = c.w, h = c.h
        let fade = CGFloat(age < 1.2 ? 1 : (1.6 - age) / 0.4)
        ctx.setStrokeColor(inkColor.copy(alpha: 0.8 * fade)!)
        ctx.setLineWidth(1.4)
        let cracks: [[(CGFloat, CGFloat)]] = [[(-0.1, 0.98), (-0.02, 0.8), (-0.14, 0.7), (-0.05, 0.58)],
                                              [(0.42, 0.72), (0.3, 0.66), (0.34, 0.54)],
                                              [(-0.46, 0.4), (-0.34, 0.44), (-0.36, 0.3)]]
        for crack in cracks {
            for (i, (x, y)) in crack.enumerated() {
                let pt = CGPoint(x: w * x, y: h * y)
                if i == 0 { ctx.move(to: pt) } else { ctx.addLine(to: pt) }
            }
        }
        ctx.strokePath()
        // 튀는 조각
        let a = CGFloat(min(age, 0.8) / 0.8)
        for (i, dir) in [(-1.0, 1.2), (1.0, 1.0), (-0.6, 0.6), (0.8, 1.5), (0.2, 1.7)].enumerated() {
            let (dx, dy) = (CGFloat(dir.0), CGFloat(dir.1))
            let x = dx * (w * 0.4 + a * 22), y = h * 0.6 + dy * a * 24 - a * a * 18
            let color = ([c.top] + c.swirl)[i % (c.swirl.count + 1)].cg.copy(alpha: fade)!
            let shard = CGMutablePath()
            shard.move(to: CGPoint(x: x, y: y + 3)); shard.addLine(to: CGPoint(x: x + 3, y: y - 2)); shard.addLine(to: CGPoint(x: x - 3, y: y - 2))
            shard.closeSubpath()
            ctx.addPath(shard); ctx.setFillColor(color); ctx.fillPath()
        }
    }

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
                fillStroke(ctx, outer, (c.earColor ?? c.top).cg)
                let inner = CGMutablePath()
                inner.move(to: CGPoint(x: s * w * 0.17, y: h * 0.95))
                inner.addLine(to: CGPoint(x: s * w * 0.32, y: h * 1.14))
                inner.addLine(to: CGPoint(x: s * w * 0.39, y: h * 0.82))
                inner.closeSubpath()
                ctx.addPath(inner)
                ctx.setFillColor(c.inner.cg)
                ctx.fillPath()
            case .round:
                fillStroke(ctx, ellipse(s * w * 0.32, h * 0.9, 17, 17), (c.earColor ?? c.top).cg)
                ctx.addPath(ellipse(s * w * 0.32, h * 0.92, 9, 9))
                ctx.setFillColor(c.inner.cg)
                ctx.fillPath()
            case .long:
                let droop: CGFloat = sleeping || mood == "error" ? 0.5 : 0.12 + CGFloat(sin(t * 1.8 + Double(s))) * 0.04
                let rot = -s * (droop + c.earSpread)
                let cx = s * (w * 0.17 + c.earSpread * 16), cy = h * 1.18 - c.earSpread * 6
                let ear = ellipse(cx, cy, 13, 34, rot: rot)
                fillStroke(ctx, ear, (c.earColor ?? c.top).cg)
                if let tip = c.earTip {
                    ctx.saveGState()
                    ctx.addPath(ear)
                    ctx.clip()
                    ctx.addPath(ellipse(cx - sin(rot) * 15, cy + cos(rot) * 15, 18, 14, rot: rot))
                    ctx.setFillColor(tip.cg)
                    ctx.fillPath()
                    ctx.restoreGState()
                    ctx.addPath(ear); ctx.setStrokeColor(inkColor); ctx.setLineWidth(2); ctx.strokePath()
                } else {
                    ctx.addPath(ellipse(cx, cy, 6, 24, rot: rot))
                    ctx.setFillColor(c.inner.cg)
                    ctx.fillPath()
                }
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
        case .zigzag:
            let wag = CGFloat(sin(t * (happy ? 10 : 2.5))) * 0.08
            let pts: [(CGFloat, CGFloat)] = [(0.30, 0.18), (0.52, 0.30), (0.46, 0.44), (0.70, 0.62), (0.66, 0.82), (0.98, 1.02),
                                             (0.80, 0.70), (0.84, 0.54), (0.62, 0.38), (0.66, 0.24), (0.38, 0.08)]
            let p = CGMutablePath()
            for (i, (x, y)) in pts.enumerated() {
                let pt = CGPoint(x: w * x, y: h * y).applying(CGAffineTransform(rotationAngle: wag))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            fillStroke(ctx, p, c.top.cg)
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
        fillStroke(ctx, p, (c.tuftColor ?? c.bottom).cg, width: 1.6)
    }

    func drawBow(_ ctx: CGContext, _ c: Creature, _ color: CGColor) {
        let x = -c.w * 0.3, y = c.h * 0.94
        fillStroke(ctx, ellipse(x - 7, y + 3, 15, 11, rot: 0.45), color, width: 1.8)
        fillStroke(ctx, ellipse(x + 7, y - 3, 15, 11, rot: 0.45), color, width: 1.8)
        fillStroke(ctx, ellipse(x, y, 7, 7), color, width: 1.8)
    }

    func drawBrows(_ ctx: CGContext, _ c: Creature) {
        let y = c.h * c.eyeY + 8
        ctx.setStrokeColor(inkColor)
        ctx.setLineWidth(3)
        ctx.setLineCap(.round)
        for s in [-1.0, 1.0] as [CGFloat] {
            let x = s * c.w * c.eyeGap
            ctx.move(to: CGPoint(x: x - 5, y: y + (s < 0 ? 1 : -1)))
            ctx.addLine(to: CGPoint(x: x + 5, y: y + (s < 0 ? -1 : 1)))
        }
        ctx.strokePath()
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
                var ew: CGFloat = big ? 8 : 6, eh: CGFloat = big ? 11 : 9
                if let iris = c.eyeColor {
                    // 큰 눈: 까만 테두리 안에 색 눈동자
                    ew += 2; eh += 3
                    ctx.setFillColor(ink)
                    ctx.fillEllipse(in: CGRect(x: ex - ew / 2, y: eyeY - eh / 2, width: ew, height: eh))
                    ctx.setFillColor(iris.cg)
                    ctx.fillEllipse(in: CGRect(x: ex - ew / 2 + 1.2, y: eyeY - eh / 2 + 0.8, width: ew - 2.4, height: eh * 0.62))
                    ctx.setFillColor(ink)
                }
                ctx.setFillColor(ink)
                if c.eyeColor == nil { ctx.fillEllipse(in: CGRect(x: ex - ew / 2, y: eyeY - eh / 2, width: ew, height: eh)) }
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
            ctx.setFillColor(c.nose?.cg ?? (c.mouth == .cat ? CGColor(red: 0.95, green: 0.5, blue: 0.55, alpha: 1) : CGColor(red: 0.9, green: 0.45, blue: 0.5, alpha: 1)))
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
        case .none:
            if let nose = c.nose {
                fillStroke(ctx, ellipse(0, h * 0.38, 7, 5), nose.cg, width: 1.2)
            }
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
        let maxTextW = lb.width - 40
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: maxTextW, height: 1000),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        let tw = ceil(measured.width), th = min(ceil(measured.height), 46)
        let bw = tw + 20, bh = th + 12
        let tailH: CGFloat = 7, tailW: CGFloat = 12
        let rect = CGRect(x: lb.midX - bw / 2, y: base.maxY + 26 + lift, width: bw, height: bh)
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
// 다른 도구 설정 파일의 기준 홈. 테스트할 때는 CLI_PET_USER_HOME 으로 바꿀 수 있다
let userHome = env["CLI_PET_USER_HOME"] ?? NSHomeDirectory()
let claudeSettingsURL = URL(fileURLWithPath: env["CLI_PET_CLAUDE_SETTINGS"]
    ?? userHome + "/.claude/settings.json")
let agentURL = URL(fileURLWithPath: env["CLI_PET_LAUNCH_AGENT"]
    ?? NSHomeDirectory() + "/Library/LaunchAgents/local.cli-pet.plist")
let exePath = stablePath(URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
    .resolvingSymlinksInPath().path)

// Homebrew는 버전마다 Cellar/<이름>/<버전>/ 에 설치하고 opt/<이름> 링크를 최신 버전으로 옮긴다.
// 훅과 자동 실행이 업그레이드 뒤에도 살아 있도록 opt 경로를 쓴다.
func stablePath(_ path: String) -> String {
    let parts = path.components(separatedBy: "/Cellar/")
    guard parts.count == 2 else { return path }
    let rest = parts[1].split(separator: "/", maxSplits: 2).map(String.init)  // 이름, 버전, 나머지
    guard rest.count == 3 else { return path }
    let opt = "\(parts[0])/opt/\(rest[0])/\(rest[2])"
    return FileManager.default.fileExists(atPath: opt) ? opt : path
}
let hookCommand = "'\(exePath)' hook"

// JSON 순서와 들여쓰기를 지키려고 JS로 편집. 이 펫이 넣은 항목만 건드림.
// Claude, Codex, Gemini는 같은 모양: { "hooks": { 이벤트: [ { "matcher"?, "hooks": [ { "type", "command" } ] } ] } }
let hooksJS = """
const isMineCmd = c => typeof c === 'string' && /cli-pet'?\\s+hook(\\s|$)/.test(c);
const isMine = h => Array.isArray(h && h.hooks) && h.hooks.some(x => isMineCmd(x.command));
function load(text) { return text.trim() ? JSON.parse(text) : {}; }
function has(text) {
  const hooks = load(text).hooks || {};
  return Object.values(hooks).some(list => Array.isArray(list) && list.some(isMine));
}
// events: [[이벤트, matcher 또는 null], ...]
function edit(text, cmd, add, events) {
  const s = load(text);
  const hooks = s.hooks || {};
  for (const ev of Object.keys(hooks)) {
    if (!Array.isArray(hooks[ev])) continue;
    hooks[ev] = hooks[ev].filter(h => !isMine(h));
    if (!hooks[ev].length) delete hooks[ev];
  }
  if (add) {
    for (const [ev, matcher] of events) {
      const entry = matcher ? { matcher } : {};
      entry.hooks = [{ type: 'command', command: cmd }];
      (hooks[ev] = hooks[ev] || []).push(entry);
    }
  }
  if (Object.keys(hooks).length) s.hooks = hooks; else delete s.hooks;
  return JSON.stringify(s, null, 2) + '\\n';
}
"""

enum SetupError: Error, CustomStringConvertible {
    case badSettings(String, String)
    var description: String {
        switch self {
        case .badSettings(let path, let m): return "설정 파일(\(path))을 읽을 수 없어요: \(m)"
        }
    }
}

func callHooksJS(_ fn: String, _ args: [Any], path: String) throws -> JSValue {
    let ctx = JSContext()!
    ctx.evaluateScript(hooksJS)
    let result = ctx.objectForKeyedSubscript(fn).call(withArguments: args)
    if let e = ctx.exception { throw SetupError.badSettings(path, e.toString()) }
    return result!
}

// MARK: 연결할 수 있는 AI 도구 (docs/integrations.md)

struct Target {
    enum Kind {
        case nested([[Any]])     // 설정 파일 안의 hooks를 고친다
        case ownFile([String])   // CLIPet 전용 파일을 따로 둔다 (Copilot)
        case viaClaude           // Claude 훅을 그대로 가져다 쓴다 (Cursor)
    }
    let id: String
    let name: String
    let file: URL
    let appDir: URL           // 이 폴더가 있으면 설치된 것으로 본다
    let kind: Kind
    let command: String
    let note: String          // 연결한 뒤 안내
}

let targets: [Target] = [
    Target(id: "claude", name: "Claude Code", file: claudeSettingsURL, appDir: URL(fileURLWithPath: userHome + "/.claude"),
           kind: .nested([["SessionStart", NSNull()], ["UserPromptSubmit", NSNull()], ["PreToolUse", "*"], ["Notification", NSNull()], ["Stop", NSNull()]]),
           command: "'\(exePath)' hook", note: "새로 여는 Claude Code 세션부터 적용돼요. VS Code·JetBrains 확장, 데스크톱 앱, Cursor에서도 같이 동작해요."),
    Target(id: "codex", name: "Codex", file: URL(fileURLWithPath: userHome + "/.codex/hooks.json"), appDir: URL(fileURLWithPath: userHome + "/.codex"),
           kind: .nested([["SessionStart", NSNull()], ["UserPromptSubmit", NSNull()], ["PreToolUse", ".*"], ["PermissionRequest", NSNull()], ["Stop", NSNull()]]),
           command: "'\(exePath)' hook --source codex", note: "Codex에서 /hooks 를 열어 CLIPet 훅을 한 번 신뢰(trust)해 주세요. CLI, IDE 확장, 앱에 모두 적용돼요."),
    Target(id: "copilot", name: "GitHub Copilot CLI", file: URL(fileURLWithPath: userHome + "/.copilot/hooks/cli-pet.json"), appDir: URL(fileURLWithPath: userHome + "/.copilot"),
           kind: .ownFile(["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "Stop"]),
           command: "'\(exePath)' hook --source copilot || true", note: "새로 여는 Copilot CLI 세션부터 적용돼요."),
    Target(id: "gemini", name: "Gemini CLI", file: URL(fileURLWithPath: userHome + "/.gemini/settings.json"), appDir: URL(fileURLWithPath: userHome + "/.gemini"),
           kind: .nested([["SessionStart", NSNull()], ["BeforeAgent", NSNull()], ["BeforeTool", ".*"], ["Notification", NSNull()], ["AfterAgent", NSNull()]]),
           command: "'\(exePath)' hook --source gemini --json", note: "훅이 꺼져 있으면 Gemini CLI에서 /hooks enable-all 을 실행하세요."),
    Target(id: "cursor", name: "Cursor", file: claudeSettingsURL, appDir: URL(fileURLWithPath: userHome + "/.cursor"),
           kind: .viaClaude, command: "", note: "Cursor는 Claude Code 훅(~/.claude/settings.json)을 기본으로 가져와요. Claude Code를 연결하면 Cursor 에이전트에도 적용돼요."),
]

func target(_ id: String) -> Target? { targets.first { $0.id == id } }
func targetInstalled(_ t: Target) -> Bool { FileManager.default.fileExists(atPath: t.appDir.path) }

func readText(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }

func isConnected(_ t: Target) -> Bool {
    switch t.kind {
    case .nested: return (try? callHooksJS("has", [readText(t.file)], path: t.file.path).toBool()) ?? false
    case .ownFile: return FileManager.default.fileExists(atPath: t.file.path)
    case .viaClaude: return isConnected(targets[0])
    }
}

// CLIPet이 처음 건드리기 전 원본을 <파일>.cli-pet-backup 으로 한 번만 남긴다
// (해제할 때나 다시 연결할 때 덮어쓰면 원본이 사라진다)
func writeWithBackup(_ url: URL, _ text: String) throws {
    let fm = FileManager.default
    let backup = url.appendingPathExtension("cli-pet-backup")
    if fm.fileExists(atPath: url.path) && !fm.fileExists(atPath: backup.path) {
        try fm.copyItem(at: url, to: backup)
    }
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

func setConnected(_ t: Target, _ on: Bool) throws {
    switch t.kind {
    case .nested(let events):
        let text = readText(t.file)
        let out = try callHooksJS("edit", [text, t.command, on, events], path: t.file.path).toString()!
        let backup = t.file.path + ".cli-pet-backup"
        if !on && out.trimmingCharacters(in: .whitespacesAndNewlines) == "{}" && !FileManager.default.fileExists(atPath: backup) {
            try? FileManager.default.removeItem(at: t.file)  // CLIPet이 새로 만든 파일이었으면 지운다
        } else if out != text {
            try writeWithBackup(t.file, out)
        }
    case .ownFile(let events):
        if !on { try? FileManager.default.removeItem(at: t.file); return }
        // Copilot: PascalCase 이벤트 이름이면 Claude와 같은 모양의 데이터를 보낸다
        var hooks: [String: Any] = [:]
        for ev in events { hooks[ev] = [["type": "command", "bash": t.command, "command": t.command, "timeoutSec": 5]] }
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "hooks": hooks], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: t.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: t.file, options: .atomic)
    case .viaClaude:
        try setConnected(targets[0], on)
    }
}

// 예전 이름 (Claude Code)
func hooksInstalled() -> Bool { isConnected(targets[0]) }
func setHooks(_ on: Bool) throws { try setConnected(targets[0], on) }

func runConnect(_ ids: [String], _ on: Bool) -> Int32 {
    let list = ids == ["all"] ? targets.filter { $0.id != "cursor" && targetInstalled($0) } : ids.compactMap { target($0) }
    if list.isEmpty || list.count != (ids == ["all"] ? list.count : ids.count) {
        print("사용법: cli-pet \(on ? "connect" : "disconnect") <" + targets.map(\.id).joined(separator: "|") + "|all>")
        return 1
    }
    var code: Int32 = 0
    for t in list {
        do {
            try setConnected(t, on)
            print(on ? "✓ \(t.name) 연결" : "✓ \(t.name) 연결 해제")
            if on { print("  \(t.note)") }
            if on, case .nested = t.kind, FileManager.default.fileExists(atPath: t.file.path + ".cli-pet-backup") {
                print("  원래 설정 백업: \(t.file.path).cli-pet-backup")
            }
            if on && !targetInstalled(t) { print("  (이 Mac에서 \(t.name) 설정 폴더를 못 찾았어요. 설치한 뒤 쓰면 적용돼요)") }
        } catch {
            print("✗ \(t.name): \(error)")
            code = 1
        }
    }
    return code
}

func printConnections() {
    for t in targets {
        let state = isConnected(t) ? "✓ 연결됨" : "  연결 안 됨"
        let inst = targetInstalled(t) ? "" : " (설치 안 됨)"
        print("\(state)  \(t.name.padding(toLength: 20, withPad: " ", startingAt: 0)) cli-pet connect \(t.id)\(inst)")
    }
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
        if !on {
            for t in targets where t.id != "cursor" && isConnected(t) {
                try setConnected(t, false)
                print("✓ \(t.name) 연결 해제")
            }
        } else if hooks {
            try setHooks(on)
            print("✓ Claude Code 연결 (새로 여는 Claude Code 세션부터 적용)")
            print("  다른 AI 도구도 연결하려면: cli-pet connections")
        } else {
            print("· Claude Code 설정 파일은 건드리지 않음")
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

// MARK: - 추가 팩 (extra-packs/, docs/custom-packs.md)

struct ExtraPack: Decodable {
    var id: String
    var name: String
    var seriesName: String?
    var credit: String?
    var files: [String]
    var bytes: Int?
}

let extraBaseURL = env["CLI_PET_EXTRA_BASE"] ?? "https://raw.githubusercontent.com/APapeIsName/cli-pet/main/extra-packs/"  // 시험용으로 바꿀 수 있다

// 앱에 같이 들어 있는 목록 (없으면 GitHub에서)
func extraPackList() -> [ExtraPack] {
    let local = Bundle.main.resourceURL?.appendingPathComponent("extra-packs-index.json")
    if let local, let data = try? Data(contentsOf: local), let list = try? JSONDecoder().decode([ExtraPack].self, from: data) { return list }
    if let url = URL(string: extraBaseURL + "index.json"), let data = try? Data(contentsOf: url),
       let list = try? JSONDecoder().decode([ExtraPack].self, from: data) { return list }
    return []
}

func extraInstalled(_ id: String) -> Bool {
    FileManager.default.fileExists(atPath: userPacksDir.appendingPathComponent(id).appendingPathComponent("pack.json").path)
}

// 파일을 모두 받은 뒤에 한 번에 옮긴다 (중간에 끊겨도 반쯤 받은 팩이 남지 않게)
func downloadExtra(_ p: ExtraPack) throws {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("cli-pet-\(p.id)-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }
    for f in p.files {
        guard let url = URL(string: extraBaseURL + p.id + "/" + (f.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? f)) else { continue }
        let data = try Data(contentsOf: url)
        try data.write(to: tmp.appendingPathComponent(f))
    }
    let dest = userPacksDir.appendingPathComponent(p.id)
    try fm.createDirectory(at: userPacksDir, withIntermediateDirectories: true)
    try? fm.removeItem(at: dest)
    try fm.moveItem(at: tmp, to: dest)
}

// MARK: - 커스텀 팩 도구 (docs/custom-packs.md)

let userPacksDir = stateDir.appendingPathComponent("packs")
let requiredPoses = ["normal", "happy", "focus", "surprised", "sleep"]
let recommendedPoses = ["blink", "dizzy", "think", "sad"]
let optionalPoses = ["held", "walk"]

func runPackCommand(_ a: [String]) -> Int32 {
    switch a.first {
    case "new":
        guard a.count >= 2 else { print("사용법: cli-pet pack new <id> [그림 폴더]"); return 1 }
        return packNew(a[1], from: a.count >= 3 ? URL(fileURLWithPath: a[2]) : nil)
    case "check":
        guard a.count >= 2 else { print("사용법: cli-pet pack check <id|폴더>"); return 1 }
        return packCheck(a[1])
    case "get":
        let list = extraPackList()
        guard a.count >= 2, a[1] != "list" else {
            print("추가 팩 (cli-pet pack get <id|all>):")
            for p in list { print("  \(extraInstalled(p.id) ? "✓" : " ") \(p.id.padding(toLength: 26, withPad: " ", startingAt: 0)) \(p.name)") }
            return 0
        }
        let want = a[1] == "all" ? list : list.filter { $0.id == a[1] }
        if want.isEmpty { print("✗ 그런 추가 팩이 없어요: \(a[1]) (목록: cli-pet pack get list)"); return 1 }
        var code: Int32 = 0
        for p in want {
            do { try downloadExtra(p); print("✓ \(p.name) 받음") } catch { print("✗ \(p.name): \(error.localizedDescription)"); code = 1 }
        }
        return code
    case "remove":
        guard a.count >= 2 else { print("사용법: cli-pet pack remove <id>"); return 1 }
        let dir = userPacksDir.appendingPathComponent(a[1])
        guard FileManager.default.fileExists(atPath: dir.path) else { print("✗ 없어요: \(dir.path)"); return 1 }
        try? FileManager.default.removeItem(at: dir)
        print("✓ 지웠어요: \(a[1])")
        return 0
    default:
        print("사용법:\n  cli-pet pack new <id> [그림 폴더]\n  cli-pet pack check <id|폴더>\n  cli-pet pack get <id|all|list>\n  cli-pet pack remove <id>")
        return 1
    }
}

// 그림 폴더에서 <포즈>.png 또는 <포즈>-1.png, <포즈>-2.png … 를 찾는다
func findPoseFiles(in dir: URL) -> [String: [String]] {
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.lowercased().hasSuffix(".png") }.sorted {
        $0.localizedStandardCompare($1) == .orderedAscending
    }
    var found: [String: [String]] = [:]
    for pose in requiredPoses + recommendedPoses + optionalPoses {
        let one = files.filter { $0.lowercased() == pose + ".png" }
        let many = files.filter { $0.lowercased().hasPrefix(pose + "-") }
        if !one.isEmpty { found[pose] = one } else if !many.isEmpty { found[pose] = many }
    }
    return found
}

func packNew(_ id: String, from: URL?) -> Int32 {
    guard id.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil else {
        print("✗ id는 영어 소문자, 숫자, 하이픈만 쓸 수 있어요. 예: anime-myseries-mychar")
        return 1
    }
    let dir = userPacksDir.appendingPathComponent(id)
    let fm = FileManager.default
    if fm.fileExists(atPath: dir.path) { print("✗ 이미 있어요: \(dir.path)"); return 1 }
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    var poses: [String: Any] = [:]
    if let from {
        for (pose, files) in findPoseFiles(in: from) {
            for f in files { try? fm.copyItem(at: from.appendingPathComponent(f), to: dir.appendingPathComponent(f)) }
            poses[pose] = files.count == 1 ? files[0] : files
        }
    }
    if poses["normal"] == nil { poses["normal"] = "normal.png" }
    let parts = id.split(separator: "-").map(String.init)
    let category = categoryOrder.contains { $0.id == parts[0] } ? parts[0] : "etc"
    let info: [String: Any] = [
        "id": id, "name": id, "category": category, "series": parts.count > 2 ? parts[1] : "custom",
        "credit": "", "license": "개인 사용", "size": 80, "poses": poses,
    ]
    let data = try! JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try? data.write(to: dir.appendingPathComponent("pack.json"))
    print("✓ 만들었어요: \(dir.path)")
    print("  pack.json의 name(메뉴 이름)과 credit(그림 출처)을 채워 주세요.")
    _ = packCheck(dir.path)
    return 0
}

func packCheck(_ arg: String) -> Int32 {
    let dir = arg.contains("/") ? URL(fileURLWithPath: arg) : userPacksDir.appendingPathComponent(arg)
    guard let data = try? Data(contentsOf: dir.appendingPathComponent("pack.json")) else {
        print("✗ pack.json이 없어요: \(dir.path)"); return 1
    }
    let info: PackInfo
    do { info = try JSONDecoder().decode(PackInfo.self, from: data) } catch {
        print("✗ pack.json을 읽을 수 없어요: \(error)"); return 1
    }
    var ok = true
    print("팩: \(info.name) (\(info.id)) · 분류 \(info.category ?? "etc") ▸ \(info.series ?? "-")")
    if info.id != dir.lastPathComponent { print("  ! id(\(info.id))와 폴더 이름(\(dir.lastPathComponent))이 달라요") }
    for (label, list) in [("필수", requiredPoses), ("권장", recommendedPoses), ("선택", optionalPoses)] {
        var line: [String] = []
        for pose in list {
            guard let files = info.poses[pose]?.files else { line.append("\(pose) ✗"); continue }
            let frames = files.map { loadFrames(dir.appendingPathComponent($0), 0.1).count }
            if frames.contains(0) {
                line.append("\(pose) ⚠︎파일 없음"); ok = false
            } else {
                let n = frames.reduce(0, +)
                line.append(n > 1 ? "\(pose) ✓(\(n)프레임)" : "\(pose) ✓")
            }
        }
        print("  \(label): " + line.joined(separator: "  "))
    }
    if info.poses["normal"] == nil { print("  ✗ normal 포즈는 꼭 있어야 해요"); ok = false }
    let missing = requiredPoses.filter { info.poses[$0] == nil }
    if !missing.isEmpty { print("  없는 필수 포즈는 비슷한 포즈로 대신해요 (docs/animation-spec.md).") }
    print(ok ? "✓ 앱에서 쓸 수 있어요. 펫 오른쪽 클릭 → 펫 바꾸기 → " + (info.extra == true ? "기본 팩" : "커스텀 팩") : "✗ 위 문제를 고쳐 주세요")
    return ok ? 0 : 1
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

func statusBarOn() -> Bool { loadSettings()["statusBar"] as? Bool ?? true }
func dailyOn() -> Bool { loadSettings()["daily"] as? Bool ?? true }
func walkOn() -> Bool { loadSettings()["walk"] as? Bool ?? true }
func dayString(_ d: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

// 메뉴 막대 아이콘: 새싹 모양 (템플릿 이미지라 다크 모드에서도 색이 맞춰진다)
func sproutIcon() -> NSImage {
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
        let body = NSBezierPath()
        body.move(to: NSPoint(x: 2.5, y: 5))
        body.curve(to: NSPoint(x: 9, y: 12.5), controlPoint1: NSPoint(x: 2.5, y: 10.5), controlPoint2: NSPoint(x: 5.5, y: 12.5))
        body.curve(to: NSPoint(x: 15.5, y: 5), controlPoint1: NSPoint(x: 12.5, y: 12.5), controlPoint2: NSPoint(x: 15.5, y: 10.5))
        body.curve(to: NSPoint(x: 9, y: 1.5), controlPoint1: NSPoint(x: 15.5, y: 2), controlPoint2: NSPoint(x: 12, y: 1.5))
        body.curve(to: NSPoint(x: 2.5, y: 5), controlPoint1: NSPoint(x: 6, y: 1.5), controlPoint2: NSPoint(x: 2.5, y: 2))
        body.lineWidth = 1.6
        NSColor.black.setStroke()
        body.stroke()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 6, y: 6, width: 1.8, height: 2.4)).fill()
        NSBezierPath(ovalIn: NSRect(x: 10.2, y: 6, width: 1.8, height: 2.4)).fill()
        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: 9, y: 12.5))
        stem.curve(to: NSPoint(x: 10, y: 15.5), controlPoint1: NSPoint(x: 9, y: 14), controlPoint2: NSPoint(x: 9.5, y: 15))
        stem.lineWidth = 1.4
        stem.stroke()
        let leaf = NSBezierPath()
        leaf.move(to: NSPoint(x: 10, y: 15.5))
        leaf.curve(to: NSPoint(x: 15.5, y: 16.5), controlPoint1: NSPoint(x: 11.5, y: 17.5), controlPoint2: NSPoint(x: 14, y: 17.5))
        leaf.curve(to: NSPoint(x: 10, y: 15.5), controlPoint1: NSPoint(x: 14, y: 14.5), controlPoint2: NSPoint(x: 11.5, y: 14.5))
        leaf.fill()
        return true
    }
    img.isTemplate = true
    img.accessibilityDescription = "CLIPet"
    return img
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var panel: NSPanel!
    var view: PetView!
    var lastMtime: Date?
    var statusItem: NSStatusItem?

    func updateStatusItem() {
        if statusBarOn() {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = sproutIcon()
            item.button?.toolTip = "CLIPet"
            let menu = NSMenu()
            menu.delegate = self  // 열 때마다 새로 채운다
            item.menu = menu
            statusItem = item
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let fresh = view.buildMenu(forStatusBar: true)
        for item in fresh.items {
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        let scale = loadScale()
        let size = NSSize(width: baseSize.width * scale, height: baseSize.height * scale)
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
        view.scale = scale
        view.packs = findPacks()
        view.selectPack(loadSelectedPackID(), announce: false)
        panel.contentView = view
        panel.orderFrontRegardless()
        updateStatusItem()

        lastMtime = mtime()
        view.greetOnLaunch()

        let anim = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.view.tick() }
        }
        let watch = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkStatus() }
        }
        RunLoop.main.add(anim, forMode: .common)
        RunLoop.main.add(watch, forMode: .common)

        DistributedNotificationCenter.default().addObserver(forName: commandNote, object: nil, queue: .main) { [weak self] note in
            let cmd = note.object as? String ?? ""
            MainActor.assumeIsolated { self?.handle(cmd) }
        }
    }

    // 이미 떠 있는데 앱을 다시 열면 (Finder, open, Spotlight) 숨긴 펫을 보여준다
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        view.show()
        return false
    }

    func handle(_ cmd: String) {
        switch cmd {
        case "show": view.show()
        case "hide": view.hide(for: nil)
        case "statusbar": updateStatusItem()
        case _ where cmd.hasPrefix("size:"):
            if let v = Double(cmd.dropFirst(5)) { view.applyScale(CGFloat(v), save: true) }
        default: break
        }
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
  cli-pet            펫 띄우기 (이 터미널에 붙어서 실행)
  cli-pet start      펫 띄우기 (터미널과 분리)
  cli-pet show / hide  펫 보이기 / 숨기기
  cli-pet menubar on|off  메뉴 막대 아이콘 켜기 / 끄기
  cli-pet size <작게|보통|크게|아주크게|배율>  펫 크기
  cli-pet say <글>   펫이 말하게 하기
  cli-pet hook       Claude Code 훅용 (stdin JSON)
  명령 | cli-pet pipe 명령 출력을 펫이 보여주기
  cli-pet lines      상황별 대사 파일 만들기·위치 보기
  cli-pet pack new <id> [그림 폴더]   커스텀 팩 만들기
  cli-pet pack check <id|폴더>       커스텀 팩 검사
  cli-pet connections                AI 도구 연결 상태 보기
  cli-pet connect <도구|all>         AI 도구 연결 (claude, codex, copilot, gemini, cursor)
  cli-pet disconnect <도구|all>      연결 해제
  cli-pet status <상태> [글]         다른 도구에서 펫 상태 바꾸기
  cli-pet debug on|off|log           훅으로 받은 입력 기록 (문제 찾기용)
  cli-pet install    Claude Code 연결 + 로그인 시 자동 실행 (--no-hooks: 연결은 빼고)
  cli-pet uninstall  위 설정 되돌리기
"""

var args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "hook":
    runHook(Array(args.dropFirst()))
case "status":
    // 다른 도구에서 펫 상태 바꾸기: cli-pet status <idle|think|working|done|alert> [글]
    let states = ["idle", "think", "working", "done", "alert", "say"]
    guard let st = args.dropFirst().first, states.contains(st) else {
        print("사용법: cli-pet status <" + states.joined(separator: "|") + "> [글]"); exit(1)
    }
    let text = args.dropFirst(2).joined(separator: " ")
    if text.isEmpty && st == "done" { writeLine("done", "done") } else { writeStatus(st, text) }
case "connect":
    exit(runConnect(Array(args.dropFirst()), true))
case "disconnect":
    exit(runConnect(Array(args.dropFirst()), false))
case "connections":
    printConnections()
case "debug":
    // cli-pet debug on|off|log : 훅으로 받은 입력을 ~/.cli-pet/hooks.log 에 남긴다 (GUI 앱에서 온 훅 확인용)
    switch args.dropFirst().first {
    case "on":
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: debugFlagURL.path, contents: nil)
        print("훅 기록을 켰어요: \(hookLogURL.path)")
    case "off":
        try? FileManager.default.removeItem(at: debugFlagURL)
        print("훅 기록을 껐어요 (기록 파일은 남아 있어요: \(hookLogURL.path))")
    case "log":
        print((try? String(contentsOf: hookLogURL, encoding: .utf8)) ?? "(기록 없음)")
    default:
        print("사용법: cli-pet debug on|off|log")
        exit(1)
    }
case "start":
    // 앱 번들을 open 으로 띄워 터미널을 닫아도 펫이 남게 한다
    let app = URL(fileURLWithPath: exePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = [app.pathExtension == "app" ? app.path : exePath]
    try? open.run()
    open.waitUntilExit()
    exit(open.terminationStatus)
case "install":
    exit(runSetup(true, hooks: !args.contains("--no-hooks")))
case "pack":
    exit(runPackCommand(Array(args.dropFirst())))
case "show":
    if petIsRunning() {
        postCommand("show")
    } else {
        print("펫이 꺼져 있어서 새로 띄워요. (cli-pet start)")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        let app = URL(fileURLWithPath: exePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        p.arguments = [app.pathExtension == "app" ? app.path : exePath]
        try? p.run()
        p.waitUntilExit()
    }
case "hide":
    postCommand("hide")
case "menubar":
    guard let v = args.dropFirst().first, v == "on" || v == "off" else { print("사용법: cli-pet menubar on|off"); exit(1) }
    saveSetting("statusBar", v == "on")
    if petIsRunning() { postCommand("statusbar") }
    print(v == "on" ? "메뉴 막대 아이콘을 켰어요" : "메뉴 막대 아이콘을 껐어요")
case "size":
    let arg = args.count > 1 ? args[1] : ""
    let named = sizeChoices.first { $0.label.replacingOccurrences(of: " ", with: "") == arg.replacingOccurrences(of: " ", with: "") }?.scale
    guard let v = named ?? Double(arg).map({ CGFloat($0) }) else {
        print("사용법: cli-pet size <" + sizeChoices.map { $0.label.replacingOccurrences(of: " ", with: "") }.joined(separator: "|") + "|0.5~2.5>")
        exit(1)
    }
    let clamped = min(2.5, max(0.5, v))
    saveSetting("scale", Double(clamped))
    if petIsRunning() { postCommand("size:\(clamped)") }
    print("크기: \(clamped)배")
case "lines":
    let url = ensureLinesFile()
    print("대사 파일: \(url.path)")
    print("고치고 저장하면 바로 적용돼요. 상황 목록:")
    for d in defaultLines { print("  \(d.key.padding(toLength: 12, withPad: " ", startingAt: 0)) \(d.help)") }
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
        postCommand("show")
        print("펫이 이미 떠 있어서 앞으로 불러왔어요.")
        exit(0)
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
