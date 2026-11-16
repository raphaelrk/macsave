import Foundation

struct ProcessResult {
    var status: Int32
    var out: String
    var err: String
    var timedOut = false
}

@discardableResult
func runProcess(_ path: String, _ args: [String], stdin: String? = nil, cwd: String? = nil,
                env: [String: String]? = nil, timeout: TimeInterval = 30) -> ProcessResult {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
    if let env { p.environment = env }
    let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
    p.standardOutput = outPipe
    p.standardError = errPipe
    p.standardInput = stdin == nil ? FileHandle.nullDevice : inPipe
    do { try p.run() } catch {
        return ProcessResult(status: -1, out: "", err: "\(error)")
    }
    var outData = Data(), errData = Data()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
    group.enter()
    DispatchQueue.global().async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
    if let stdin {
        DispatchQueue.global().async {
            try? inPipe.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
            try? inPipe.fileHandleForWriting.close()
        }
    }
    var timedOut = false
    if group.wait(timeout: .now() + timeout) == .timedOut {
        timedOut = true
        p.terminate()
        _ = group.wait(timeout: .now() + 2)
    }
    p.waitUntilExit()
    return ProcessResult(status: p.terminationStatus,
                         out: String(decoding: outData, as: UTF8.self),
                         err: String(decoding: errData, as: UTF8.self),
                         timedOut: timedOut)
}

func runJXA(_ script: String, args: [String] = [], timeout: TimeInterval = 20) -> (Any?, String?) {
    let r = runProcess("/usr/bin/osascript", ["-l", "JavaScript", "-e", script] + args, timeout: timeout)
    if r.timedOut { return (nil, "timed out (waiting on an Automation permission prompt?)") }
    guard r.status == 0 else {
        return (nil, r.err.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    let data = Data(r.out.utf8)
    return ((try? JSONSerialization.jsonObject(with: data)), nil)
}

func abbreviateHome(_ path: String) -> String {
    let home = NSHomeDirectory()
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}
