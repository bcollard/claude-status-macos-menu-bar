import Foundation

struct ClaudeProcessInfo: Equatable {
    let count: Int
    let totalRSSBytes: UInt64
}

enum ProcessScanner {
    /// Counts running Claude Code CLI processes and sums their resident
    /// memory. Uses `ps -axo pid=,rss=,comm=` and filters where the
    /// command basename is exactly `claude` — this excludes our own
    /// `ClaudeStatus` menu-bar app (whose comm= is the full bundle path)
    /// and any unrelated process that happens to contain "claude" in its
    /// arguments.
    static func scanClaudeProcesses() -> ClaudeProcessInfo {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,rss=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        let data: Data
        do {
            try task.run()
            // Drain the pipe BEFORE waitUntilExit. `ps` output is ~70 KB
            // on a typical Mac and the pipe buffer is only 16 KB, so
            // waiting first would deadlock once the buffer filled.
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
        } catch {
            return ClaudeProcessInfo(count: 0, totalRSSBytes: 0)
        }

        guard let output = String(data: data, encoding: .utf8) else {
            return ClaudeProcessInfo(count: 0, totalRSSBytes: 0)
        }

        var count = 0
        var totalRSS: UInt64 = 0
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3, let rssKB = UInt64(parts[1]) else { continue }
            // Anything from index 2 onward is the comm field (it may
            // contain spaces if ps returns a full path). We want exact
            // `claude` only.
            let comm = parts[2...].joined(separator: " ")
            guard comm == "claude" else { continue }
            count += 1
            totalRSS += rssKB * 1024
        }
        return ClaudeProcessInfo(count: count, totalRSSBytes: totalRSS)
    }
}

func formatBytes(_ bytes: UInt64) -> String {
    let kb = Double(bytes) / 1024
    if kb < 1024 { return String(format: "%.0f KB", kb) }
    let mb = kb / 1024
    if mb < 1024 { return String(format: "%.0f MB", mb) }
    return String(format: "%.1f GB", mb / 1024)
}
