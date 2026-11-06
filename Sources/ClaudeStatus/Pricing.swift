import Foundation

/// Per-million-token prices in USD, from
/// https://platform.claude.com/docs/en/about-claude/pricing (checked 2026-11-06).
/// This table is a maintenance hot spot — update it when Anthropic ships a
/// model or changes a price.
///
/// On plan-based subscriptions (Pro/Max/Team/Enterprise) you don't pay
/// per-token directly; the figure shown is the *equivalent* API cost.
struct ModelPricing: Sendable {
    let input: Double
    let output: Double
    let cacheRead: Double
    /// 5-minute TTL cache write (1.25× input on every current model).
    let cacheWrite5m: Double
    /// 1-hour TTL cache write (2× input on every current model).
    let cacheWrite1h: Double
    /// Prompt-size tier: when a request's prompt (input + cache reads +
    /// cache writes) exceeds `threshold` tokens, every rate in that request
    /// is multiplied by `multiplier`. Only Claude Haiku 5.5 has one today.
    var longPrompt: (threshold: Int, multiplier: Double)? = nil

    static let zero = ModelPricing(input: 0, output: 0, cacheRead: 0, cacheWrite5m: 0, cacheWrite1h: 0)

    /// Standard multipliers: 5m write 1.25×, 1h write 2× the input price.
    static func standard(input: Double, output: Double, cacheRead: Double,
                         longPrompt: (threshold: Int, multiplier: Double)? = nil) -> ModelPricing {
        ModelPricing(input: input, output: output, cacheRead: cacheRead,
                     cacheWrite5m: input * 1.25, cacheWrite1h: input * 2,
                     longPrompt: longPrompt)
    }
}

/// Token counts and billing modifiers of one assistant turn, as logged in
/// the session JSONL `usage` block.
struct TurnUsage: Sendable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite5m = 0
    var cacheWrite1h = 0
    var webSearchRequests = 0
    /// `usage.speed == "fast"` — fast mode bills 2× on Opus 5.5 / 5 / 4.8.
    var fast = false
    /// `usage.inference_geo == "us"` — US-only data residency bills 1.1×.
    var usOnlyInference = false

    var promptTokens: Int { input + cacheRead + cacheWrite5m + cacheWrite1h }
}

enum Pricing {
    /// Web search server tool: $10 per 1,000 searches. Web fetch has no
    /// per-call charge (its content is billed as input tokens).
    static let webSearchPerRequest = 10.0 / 1000.0
    static let fastModeMultiplier = 2.0
    static let usOnlyInferenceMultiplier = 1.1

    /// Lookup by model-id substring → pricing. First match wins;
    /// case-insensitive. Specific versions come before their family
    /// fallback (`opus-5-5` before `opus-5`, which would also match it).
    /// The bare family fallbacks use the newest model's price, so an
    /// unknown future version is priced like the current one, not as $0.
    private static let table: [(match: String, p: ModelPricing)] = [
        // Fable / Mythos (same prices)
        ("fable-5-1",  .standard(input: 10, output: 50, cacheRead: 0.25)),
        ("mythos-5-1", .standard(input: 10, output: 50, cacheRead: 0.25)),
        ("fable-5",    .standard(input: 10, output: 50, cacheRead: 1.00)),
        ("mythos-5",   .standard(input: 10, output: 50, cacheRead: 1.00)),
        ("fable",      .standard(input: 10, output: 50, cacheRead: 0.25)),
        ("mythos",     .standard(input: 10, output: 50, cacheRead: 0.25)),

        // Opus
        ("opus-5-5",   .standard(input: 4, output: 20, cacheRead: 0.20)),
        ("opus-5",     .standard(input: 5, output: 25, cacheRead: 0.50)),
        ("opus-4-8",   .standard(input: 5, output: 25, cacheRead: 0.50)),
        ("opus-4-7",   .standard(input: 5, output: 25, cacheRead: 0.50)),
        ("opus-4-6",   .standard(input: 5, output: 25, cacheRead: 0.50)),
        ("opus-4-5",   .standard(input: 5, output: 25, cacheRead: 0.50)),
        ("opus-4",     .standard(input: 15, output: 75, cacheRead: 1.50)),   // Opus 4 / 4.1
        ("opus",       .standard(input: 4, output: 20, cacheRead: 0.20)),

        // Sonnet
        ("sonnet-5-5", .standard(input: 2, output: 10, cacheRead: 0.10)),
        ("sonnet-5",   .standard(input: 2, output: 10, cacheRead: 0.20)),
        ("sonnet-4",   .standard(input: 3, output: 15, cacheRead: 0.30)),    // Sonnet 4 / 4.5 / 4.6
        ("sonnet",     .standard(input: 2, output: 10, cacheRead: 0.10)),

        // Haiku
        ("haiku-5-5",  .standard(input: 0.10, output: 0.50, cacheRead: 0.01,
                                 longPrompt: (threshold: 100_000, multiplier: 5))),
        ("haiku-4-5",  .standard(input: 1, output: 5, cacheRead: 0.10)),
        ("haiku",      .standard(input: 0.10, output: 0.50, cacheRead: 0.01,
                                 longPrompt: (threshold: 100_000, multiplier: 5))),
    ]

    static func price(for model: String) -> ModelPricing {
        let lc = model.lowercased()
        for entry in table where lc.contains(entry.match) { return entry.p }
        return .zero
    }

    /// Cost in USD of one assistant turn. Prompt-size tiers, fast mode and
    /// data residency are per-request, so this is the accurate path; the
    /// scanner sums it into `ModelUsage.costUSD`.
    static func cost(_ t: TurnUsage, model: String) -> Double {
        let p = price(for: model)
        var multiplier = 1.0
        if let tier = p.longPrompt, t.promptTokens > tier.threshold { multiplier *= tier.multiplier }
        if t.fast { multiplier *= fastModeMultiplier }
        if t.usOnlyInference { multiplier *= usOnlyInferenceMultiplier }
        return tokenCost(t, p) * multiplier + Double(t.webSearchRequests) * webSearchPerRequest
    }

    /// Cost in USD for a `ModelUsage` row. Uses the per-turn sum when the
    /// scanner computed one; otherwise (demo data) estimates from the
    /// aggregate token counts at base rates, without per-request tiers or
    /// modifiers.
    static func cost(_ mu: ModelUsage) -> Double {
        if let c = mu.costUSD { return c }
        let t = TurnUsage(
            input: mu.inputTokens, output: mu.outputTokens,
            cacheRead: mu.cacheReadTokens,
            cacheWrite5m: mu.cacheCreateTokens - mu.cacheCreate1hTokens,
            cacheWrite1h: mu.cacheCreate1hTokens,
            webSearchRequests: mu.webSearchRequests
        )
        return tokenCost(t, price(for: mu.model)) + Double(t.webSearchRequests) * webSearchPerRequest
    }

    private static func tokenCost(_ t: TurnUsage, _ p: ModelPricing) -> Double {
        (Double(t.input)        * p.input
       + Double(t.output)       * p.output
       + Double(t.cacheRead)    * p.cacheRead
       + Double(t.cacheWrite5m) * p.cacheWrite5m
       + Double(t.cacheWrite1h) * p.cacheWrite1h) / 1_000_000
    }

    /// Aggregate cost across a usage window.
    static func cost(_ w: UsageWindow) -> Double {
        w.byModel.values.reduce(0) { $0 + cost($1) }
    }

    static func formatUSD(_ amount: Double) -> String {
        if amount == 0 { return "$0.00" }
        if amount >= 1000 { return String(format: "$%.0f", amount) }
        if amount >= 1    { return String(format: "$%.2f", amount) }
        return String(format: "$%.3f", amount)
    }
}
