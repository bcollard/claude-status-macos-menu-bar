import Foundation

/// Per-million-token prices in USD. Values reflect the public Anthropic
/// price list as of 2026-05 (Opus 4.x, Sonnet 4.x, Haiku 4.x). Adjust if
/// Anthropic publishes changes — this table is a maintenance hot spot.
///
/// On plan-based subscriptions (Pro/Max/Team/Enterprise) you don't pay
/// per-token directly; the figure shown is the *equivalent* API cost.
struct ModelPricing: Sendable {
    let input: Double
    let output: Double
    let cacheRead: Double
    let cacheWrite: Double

    static let zero = ModelPricing(input: 0, output: 0, cacheRead: 0, cacheWrite: 0)
}

enum Pricing {
    /// Lookup by family substring → pricing. First match wins; case-insensitive.
    private static let table: [(match: String, p: ModelPricing)] = [
        ("opus",   ModelPricing(input: 15.00, output: 75.00, cacheRead: 1.50,  cacheWrite: 18.75)),
        ("sonnet", ModelPricing(input:  3.00, output: 15.00, cacheRead: 0.30,  cacheWrite:  3.75)),
        ("haiku",  ModelPricing(input:  0.80, output:  4.00, cacheRead: 0.08,  cacheWrite:  1.00)),
    ]

    static func price(for model: String) -> ModelPricing {
        let lc = model.lowercased()
        for entry in table where lc.contains(entry.match) { return entry.p }
        return .zero
    }

    /// Cost in USD for a `ModelUsage` row.
    static func cost(_ mu: ModelUsage) -> Double {
        let p = price(for: mu.model)
        let m = 1_000_000.0
        return (Double(mu.inputTokens)       * p.input
              + Double(mu.outputTokens)      * p.output
              + Double(mu.cacheReadTokens)   * p.cacheRead
              + Double(mu.cacheCreateTokens) * p.cacheWrite) / m
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
