import Foundation
import Combine

/// Confirms the *running* app bundle is genuinely signed by the developer
/// and notarized by Apple — not that it corresponds to any particular
/// source commit. The signature and stapled notarization ticket travel
/// inside the `.app` bundle itself and are checked against Apple's public
/// root certificates, already trusted by every Mac — so this gives the
/// same result on anyone's machine, offline, using none of the developer's
/// own credentials. It is intentionally *not* a build-provenance check
/// (that would need source-to-binary attestation, e.g. Sigstore/SLSA via
/// GitHub Actions — a different, much larger change to how releases are
/// built, not a Diagnostics-pane feature).
struct CodeSignatureStatus {
    let signingAuthority: String?
    let teamIdentifier: String?
    let isValidSignature: Bool
    let isNotarized: Bool
    let gatekeeperSource: String?
    let error: String?
}

enum CodeSignatureCheck {
    /// Blocking — call off the main actor.
    static func run() -> CodeSignatureStatus {
        let path = Bundle.main.bundlePath

        let verify = shell("/usr/bin/codesign", ["--verify", "--deep", "--strict", path])
        // -dvvv (not the default -dv) is needed for codesign to print the
        // Authority= chain at all — confirmed empirically, not documented
        // clearly by `codesign --help`.
        let info = shell("/usr/bin/codesign", ["-dvvv", path])
        let gatekeeper = shell("/usr/sbin/spctl", ["-a", "-vv", path])

        var authority: String?
        var teamID: String?
        for line in info.output.split(separator: "\n") {
            if authority == nil, line.hasPrefix("Authority=") {
                authority = String(line.dropFirst("Authority=".count))
            }
            if line.hasPrefix("TeamIdentifier=") {
                teamID = String(line.dropFirst("TeamIdentifier=".count))
            }
        }

        var gatekeeperSource: String?
        for line in gatekeeper.output.split(separator: "\n") {
            if line.hasPrefix("source=") {
                gatekeeperSource = String(line.dropFirst("source=".count))
            }
        }
        let accepted = gatekeeper.output.contains(": accepted")

        let error: String?
        if verify.status != 0 {
            error = verify.output.isEmpty ? "codesign verification failed" : verify.output
        } else if !accepted {
            error = gatekeeper.output.isEmpty ? "Gatekeeper rejected this app" : gatekeeper.output
        } else {
            error = nil
        }

        return CodeSignatureStatus(
            signingAuthority: authority,
            teamIdentifier: teamID,
            isValidSignature: verify.status == 0,
            isNotarized: accepted && (gatekeeperSource?.contains("Notarized") ?? false),
            gatekeeperSource: gatekeeperSource,
            error: error
        )
    }

    private static func shell(_ launchPath: String, _ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, "\(error)")
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

@MainActor
final class CodeSignatureModel: ObservableObject {
    @Published private(set) var status: CodeSignatureStatus?
    @Published private(set) var isChecking = false

    func check() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                CodeSignatureCheck.run()
            }.value
            status = result
            isChecking = false
        }
    }
}
