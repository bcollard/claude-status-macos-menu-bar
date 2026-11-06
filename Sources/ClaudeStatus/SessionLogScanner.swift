import Foundation

struct ModelUsage: Sendable {
    var model: String
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreateTokens: Int = 0
    /// Subset of `cacheCreateTokens` written with the 1-hour TTL (billed 2×
    /// input instead of 1.25×). From `usage.cache_creation.ephemeral_1h_input_tokens`.
    var cacheCreate1hTokens: Int = 0
    var webSearchRequests: Int = 0
    var messageCount: Int = 0
    /// Sum of per-turn `Pricing.cost(_:model:)`. Set by the scanner; `nil`
    /// for hand-built rows (demo data), which `Pricing` estimates instead.
    var costUSD: Double? = nil

    var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens + cacheCreateTokens }

    /// "claude-opus-4-7" → "Opus 4.7", "claude-haiku-4-5-20251001" → "Haiku 4.5".
    var shortName: String {
        var s = model.lowercased()
        if s.hasPrefix("claude-") { s.removeFirst("claude-".count) }
        let parts = s.split(separator: "-").map(String.init)
        guard let familyRaw = parts.first else { return model }
        let family = familyRaw.prefix(1).uppercased() + familyRaw.dropFirst()
        var version: String?
        if parts.count >= 3, parts[1].allSatisfy(\.isNumber), parts[2].allSatisfy(\.isNumber) {
            version = "\(parts[1]).\(parts[2])"
        } else if parts.count >= 2 {
            version = parts[1]
        }
        return version.map { "\(family) \($0)" } ?? family
    }
}

struct UsageWindow: Sendable {
    var byModel: [String: ModelUsage] = [:]
    var sessionCount: Int = 0
    var fileCount: Int = 0

    var totalInput: Int { byModel.values.map(\.inputTokens).reduce(0, +) }
    var totalOutput: Int { byModel.values.map(\.outputTokens).reduce(0, +) }
    var totalCacheRead: Int { byModel.values.map(\.cacheReadTokens).reduce(0, +) }
    var totalCacheCreate: Int { byModel.values.map(\.cacheCreateTokens).reduce(0, +) }
    var totalMessages: Int { byModel.values.map(\.messageCount).reduce(0, +) }
    var grandTotal: Int { totalInput + totalOutput + totalCacheRead + totalCacheCreate }
}

enum SessionLogScanner {
    static let projectsURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)

    /// Aggregate token usage for assistant turns whose timestamp falls in [since, now].
    static func scan(since: Date) throws -> UsageWindow {
        var window = UsageWindow()
        let fm = FileManager.default
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()

        guard let enumerator = fm.enumerator(
            at: projectsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return window }

        var sessionIds: Set<String> = []

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let mtime = attrs[.modificationDate] as? Date,
               mtime < since {
                continue
            }
            window.fileCount += 1

            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }

            var buffer = Data()
            while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer.subdata(in: 0..<nl)
                    buffer.removeSubrange(0...nl)
                    process(
                        lineData: lineData, since: since,
                        iso: iso, isoFractional: isoFractional,
                        window: &window, sessionIds: &sessionIds
                    )
                }
            }
            if !buffer.isEmpty {
                process(
                    lineData: buffer, since: since,
                    iso: iso, isoFractional: isoFractional,
                    window: &window, sessionIds: &sessionIds
                )
            }
        }

        window.sessionCount = sessionIds.count
        return window
    }

    private static func process(
        lineData: Data,
        since: Date,
        iso: ISO8601DateFormatter,
        isoFractional: ISO8601DateFormatter,
        window: inout UsageWindow,
        sessionIds: inout Set<String>
    ) {
        guard !lineData.isEmpty else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { return }

        if let ts = obj["timestamp"] as? String {
            let d = isoFractional.date(from: ts) ?? iso.date(from: ts)
            if let d, d < since { return }
        }

        if let sid = obj["sessionId"] as? String { sessionIds.insert(sid) }

        var usage: [String: Any]? = obj["usage"] as? [String: Any]
        var modelName: String?
        if let m = obj["model"] as? String { modelName = m }

        if let msg = obj["message"] as? [String: Any] {
            if usage == nil { usage = msg["usage"] as? [String: Any] }
            if modelName == nil { modelName = msg["model"] as? String }
        }

        guard let usage else { return }
        let model = modelName ?? "unknown"
        if model == "<synthetic>" { return }

        let turn = turnUsage(from: usage)
        var mu = window.byModel[model] ?? ModelUsage(model: model)
        mu.inputTokens += turn.input
        mu.outputTokens += turn.output
        mu.cacheReadTokens += turn.cacheRead
        mu.cacheCreateTokens += turn.cacheWrite5m + turn.cacheWrite1h
        mu.cacheCreate1hTokens += turn.cacheWrite1h
        mu.webSearchRequests += turn.webSearchRequests
        mu.messageCount += 1
        mu.costUSD = (mu.costUSD ?? 0) + Pricing.cost(turn, model: model)
        window.byModel[model] = mu
    }

    /// Parses one `usage` block. Top-level totals only — `usage.iterations[]`
    /// breaks the same turn down per step and would double-count.
    static func turnUsage(from usage: [String: Any]) -> TurnUsage {
        var t = TurnUsage()
        t.input = (usage["input_tokens"] as? Int) ?? 0
        t.output = (usage["output_tokens"] as? Int) ?? 0
        t.cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0
        let cacheWriteTotal = (usage["cache_creation_input_tokens"] as? Int) ?? 0
        // Older logs have no TTL split: price the whole write at the 5m rate.
        let oneHour = ((usage["cache_creation"] as? [String: Any])?["ephemeral_1h_input_tokens"] as? Int) ?? 0
        t.cacheWrite1h = min(oneHour, cacheWriteTotal)
        t.cacheWrite5m = cacheWriteTotal - t.cacheWrite1h
        t.webSearchRequests = ((usage["server_tool_use"] as? [String: Any])?["web_search_requests"] as? Int) ?? 0
        t.fast = (usage["speed"] as? String) == "fast"
        t.usOnlyInference = (usage["inference_geo"] as? String) == "us"
        return t
    }
}
