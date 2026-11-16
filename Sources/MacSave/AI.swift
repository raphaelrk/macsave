import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case claude, codex
    var id: String { rawValue }
    var displayName: String { self == .claude ? "Claude Code" : "Codex" }
}

enum AI {
    static let prompt = """
    Below is a snapshot of every open window and tab on my Mac, grouped by macOS desktop and app, \
    captured right before I close them. Write a short summary (≤200 words) to put at the top of the \
    saved note: one line per desktop or theme saying what I was working on/reading, then a short \
    "Worth returning to" list of the specific tabs/files that look unfinished or important. \
    Plain text with simple dashes, no markdown headers, no preamble. Don't use any tools.
    """

    /// GUI apps get a minimal PATH; borrow the login shell's so `node` etc. resolve.
    static let loginPATH: String = {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let r = runProcess(shell, ["-l", "-c", "printenv PATH"], timeout: 5)
        let fromShell = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        let home = NSHomeDirectory()
        let extras = ["\(home)/.local/bin", "\(home)/.claude/local", "\(home)/.npm-global/bin",
                      "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        return ([fromShell].filter { !$0.isEmpty } + extras).joined(separator: ":")
    }()

    static func locate(_ p: AIProvider) -> String? {
        for dir in loginPATH.split(separator: ":") {
            let path = "\(dir)/\(p.rawValue)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    static func available() -> [AIProvider: String] {
        var out: [AIProvider: String] = [:]
        for p in AIProvider.allCases { if let path = locate(p) { out[p] = path } }
        return out
    }

    static func summarize(_ text: String, with p: AIProvider, path: String) -> Result<String, Error> {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = loginPATH
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("macsave-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let r: ProcessResult
        var output: String
        switch p {
        case .claude:
            r = runProcess(path, ["-p", prompt], stdin: text, cwd: tmp.path, env: env, timeout: 240)
            output = r.out
        case .codex:
            let last = tmp.appendingPathComponent("last.txt")
            r = runProcess(path, ["exec", "--skip-git-repo-check", "--ephemeral", "-s", "read-only",
                                  "-o", last.path, prompt], stdin: text, cwd: tmp.path, env: env, timeout: 300)
            output = (try? String(contentsOf: last, encoding: .utf8)) ?? r.out
        }
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.timedOut { return .failure(Msg("\(p.displayName) timed out")) }
        if r.status != 0 || output.isEmpty {
            let detail = (r.err.isEmpty ? r.out : r.err).trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(Msg("\(p.displayName) failed (exit \(r.status)): \(detail.suffix(300))"))
        }
        return .success("AI summary (\(p.displayName)):\n" + output)
    }
}

struct Msg: LocalizedError {
    let text: String
    init(_ t: String) { text = t }
    var errorDescription: String? { text }
}

enum Saver {
    static let defaultTemplate = "~/projects/notes/{yyyy}/{yyyy}-{MM}-{dd}/closing-windows-{HHmm}.txt"

    static func expand(_ template: String, date: Date = Date()) -> URL {
        func f(_ s: String) -> String { let d = DateFormatter(); d.dateFormat = s; return d.string(from: date) }
        var s = template
        for token in ["yyyy", "MM", "dd", "HHmm", "HH", "mm"] { s = s.replacingOccurrences(of: "{\(token)}", with: f(token)) }
        return URL(fileURLWithPath: (s as NSString).expandingTildeInPath)
    }

    static func save(_ text: String, snapshot: Snapshot, template: String, json: Bool) throws -> URL {
        var url = expand(template, date: snapshot.date)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stem = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = url.deletingLastPathComponent().appendingPathComponent("\(stem)-\(n)" + (ext.isEmpty ? "" : ".\(ext)"))
            n += 1
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        if json {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            enc.dateEncodingStrategy = .iso8601
            try enc.encode(snapshot).write(to: url.deletingPathExtension().appendingPathExtension("json"))
        }
        return url
    }
}
