import Foundation

@main
struct SetupWizardTests {
    @MainActor static func main() async throws {
        var count = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
            count += 1
        }
        let source = URL(fileURLWithPath: "/tmp/a project; echo test")
        let destination = URL(fileURLWithPath: "/tmp/Apps $literal")
        let fixtureHome = URL(fileURLWithPath: "/fixture/home with spaces", isDirectory: true)
        let personalApplications = fixtureHome.appendingPathComponent("Applications", isDirectory: true)
        let candidates = SetupDestination.candidates(home: fixtureHome)
        expect(candidates == [SetupDestination.system, personalApplications], "Default candidates prefer system Applications, then the current user's Applications")
        expect(SetupDestination.preferred(candidates: candidates, canUse: { _ in true }) == SetupDestination.system, "Writable system Applications has priority")
        expect(SetupDestination.preferred(candidates: candidates, canUse: { $0 == personalApplications }) == personalApplications, "Writable existing personal Applications is used when system Applications is unavailable")
        expect(SetupDestination.preferred(candidates: candidates, canUse: { _ in false }) == SetupDestination.system, "Unavailable or missing destinations keep system path for explicit guidance")
        expect(SetupDestination.preferred(candidates: [], canUse: { _ in true }) == SetupDestination.system, "Empty candidate list has a stable fallback")
        expect(SetupDestination.chooserDirectory(destination: personalApplications, home: fixtureHome, canUse: { _ in true }) == personalApplications, "Chooser starts at an accessible destination")
        expect(SetupDestination.chooserDirectory(destination: SetupDestination.system, home: fixtureHome, canUse: { _ in false }) == fixtureHome, "Chooser starts in home when the selected destination is unavailable")
        let unavailable = SetupModel(source: source, preview: true, destinationCandidates: candidates, canUseDestination: { _ in false })
        expect(unavailable.destination == SetupDestination.system && unavailable.destinationGuidance?.contains("crie Applications") == true, "Missing writable destination is accompanied by actionable guidance")
        let personal = SetupModel(source: source, preview: true, destinationCandidates: candidates, canUseDestination: { $0 == personalApplications })
        expect(personal.destination == personalApplications && personal.destinationGuidance == nil, "A usable personal destination requires no warning")
        expect(SetupCommand.arguments(source: source, destination: destination, check: true) == ["/tmp/a project; echo test/install.sh", "--check", "--destination", "/tmp/Apps $literal"], "Check arguments stay literal")
        expect(SetupCommand.arguments(source: source, destination: destination, check: false)[1] == "--yes", "Install requires affirmative backend argument")
        expect(SetupStep.marker(in: "PS12_STEP:download-ps1:Downloading: 12%")?.0 == .downloadPS1, "Known progress step")
        expect(SetupStep.marker(in: "PS12_STEP:download-ps1:Downloading: 12%")?.1 == "Downloading: 12%", "Messages retain colons")
        expect(SetupStep.marker(in: "PS12_STEP:unknown:message") == nil, "Unknown steps ignored")
        expect(SetupStep.marker(in: "prefix PS12_STEP:build:message") == nil, "Only whole-line markers accepted")
        expect(SetupStep.marker(in: "PS12_STEP:build") == nil, "Malformed markers ignored")
        var log = SetupLog()
        log.append("first\n")
        expect(log.text == "first\n", "Log append")
        log.append(String(repeating: "á", count: SetupLog.limit * 2))
        expect(log.text.utf8.count <= SetupLog.limit, "Unicode logs remain bounded")
        expect(log.text.hasPrefix("[As linhas mais antigas"), "Log truncation disclosed")
        var decoder = SetupLineDecoder()
        let unicode = Array("Ação\n".utf8)
        expect(decoder.consume(Data(unicode.prefix(2))).isEmpty, "Partial UTF-8 line buffered")
        expect(decoder.consume(Data(unicode.dropFirst(2))) == ["Ação"], "UTF-8 across chunks decoded intact")
        expect(decoder.consume(Data("one\r\ntwo\rthree".utf8)) == ["one", "two"], "CR/LF output handled without blank duplicates")
        expect(decoder.consume(Data(), finished: true) == ["three"], "Last unterminated line drained")
        expect(decoder.consume(Data(), finished: true).isEmpty, "Drain idempotent")
        expect(decoder.consume(Data(repeating: 65, count: 17 * 1024)).count == 1, "Oversize incomplete line flushed")
        expect(SetupApplication.allCases.map(\.bundleID).count == 3, "Only three known apps exposed")
        expect(SetupApplication.central.filename == "PS1-2.app", "Central path is filename, not slash title")
        let fixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent("PS12SetupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let absentDestination = fixtureRoot.appendingPathComponent("Applications", isDirectory: true)
        let fileDestination = fixtureRoot.appendingPathComponent("not-a-directory")
        try Data().write(to: fileDestination)
        expect(SetupDestination.isWritableDirectory(fixtureRoot), "Existing writable fixture directory is usable")
        expect(!SetupDestination.isWritableDirectory(fileDestination), "Writable files cannot be installation destinations")
        expect(!SetupDestination.isWritableDirectory(absentDestination), "Missing destination is rejected")
        expect(!FileManager.default.fileExists(atPath: absentDestination.path), "Checking a missing destination does not create it")
        func makeModel(source: URL, preview: Bool) -> SetupModel {
            SetupModel(source: source, preview: preview, destinationCandidates: [destination], canUseDestination: { $0 == destination })
        }
        let backend = #"""
        #!/bin/bash
        set -euo pipefail
        printf 'RUN\n' >> invocations.txt
        printf 'ARG:%s\n' "$@" >> invocations.txt
        if [ "${1:-}" = --check ] && [ -f fail-check ]; then
            printf 'PS12_STEP:preflight:Fixture preflight failed\n' >&2
            printf 'fixture failure without newline' >&2
            exit 7
        fi
        if [ "${1:-}" = --yes ] && [ -f fail-install ]; then
            printf 'PS12_STEP:build:Fixture build failure\n'
            printf 'fixture install failure without newline' >&2
            exit 8
        fi
        if [ "${1:-}" = --check ]; then
            printf 'PS12_STEP:preflight:Fixture preflight\n'
        else
            printf 'PS12_STEP:build:Fixture build\n'
            printf 'PS12_STEP:download-ps1:Fixture PS1\n'
            printf 'PS12_STEP:download-ps2:Fixture PS2\n'
            printf 'PS12_STEP:install:Fixture publication\n'
        fi
        if [ -f flood ]; then
            for ((index=0; index<5000; index++)); do
                printf 'fixture stdout %s: 0123456789 0123456789 0123456789 0123456789\n' "$index"
                printf 'fixture stderr %s: 0123456789 0123456789 0123456789 0123456789\n' "$index" >&2
            done
        fi
        if [ "${1:-}" = --check ]; then
            printf 'fixture preflight finished without newline'
        else
            printf 'PS12_STEP:complete:fixture installation finished without newline'
        fi
        """#
        func makeFixture(_ name: String) throws -> URL {
            let directory = fixtureRoot.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try backend.write(to: directory.appendingPathComponent("install.sh"), atomically: true, encoding: .utf8)
            return directory
        }
        func invocations(_ directory: URL) -> String {
            (try? String(contentsOf: directory.appendingPathComponent("invocations.txt"), encoding: .utf8)) ?? ""
        }
        func runCount(_ directory: URL) -> Int { invocations(directory).split(separator: "\n").filter { $0 == "RUN" }.count }

        let successSource = try makeFixture("source with spaces $literal; punctuation")
        try Data().write(to: successSource.appendingPathComponent("flood"))
        let success = makeModel(source: successSource, preview: false)
        expect(success.phase == .checking && !success.canInstall, "Real model initially awaits preflight")
        success.install()
        expect(runCount(successSource) == 0, "Installation before successful preflight does nothing")
        success.preflight()
        success.preflight()
        success.install()
        let preflightFinished = await waitUntil { !success.isBusy }
        expect(preflightFinished, "Asynchronous preflight drains a large combined pipe within timeout")
        expect(success.phase == .ready && success.canInstall, "Successful preflight enables explicit installation")
        expect(runCount(successSource) == 1, "Duplicate preflight and premature install cannot start extra processes")
        expect(invocations(successSource).contains("ARG:--check\nARG:--destination\nARG:/tmp/Apps $literal\n"), "Backend receives exact check/destination arguments")
        expect(success.log.text.utf8.count <= SetupLog.limit, "Large streamed preflight log stays bounded")
        expect(success.log.text.hasPrefix("[As linhas mais antigas"), "Stream truncation is visible to user")
        expect(success.log.text.contains("fixture stdout 4999") && success.log.text.contains("fixture stderr 4999"), "Both output streams are drained")
        expect(success.log.text.hasSuffix("fixture preflight finished without newline\n"), "EOF preserves final line without LF")
        expect(success.exitCode == 0 && !success.showLog, "Successful preflight final state")
        success.install()
        success.install()
        success.preflight()
        let installationFinished = await waitUntil { !success.isBusy }
        expect(installationFinished, "Explicit fixture installation finishes asynchronously")
        expect(success.phase == .complete && success.step == .complete, "Explicit install moves to complete")
        expect(runCount(successSource) == 2, "Duplicate install and preflight are guarded during installation")
        expect(invocations(successSource).contains("ARG:--yes\nARG:--destination\nARG:/tmp/Apps $literal\n"), "Only explicit install sends affirmative backend argument")
        expect(success.log.text.hasSuffix("PS12_STEP:complete:fixture installation finished without newline\n"), "Final progress marker without LF is drained")
        expect(success.log.text.utf8.count <= SetupLog.limit && success.exitCode == 0, "Completed large-output install remains bounded and successful")

        let failureSource = try makeFixture("retry fixture")
        try Data().write(to: failureSource.appendingPathComponent("fail-check"))
        let retry = makeModel(source: failureSource, preview: false)
        retry.preflight()
        let failureFinished = await waitUntil { !retry.isBusy }
        expect(failureFinished && retry.phase == .failed, "Failed preflight becomes failed")
        expect(retry.exitCode == 7 && retry.showLog && !retry.canInstall, "Failure exposes logs and status but cannot install")
        expect(retry.log.text.hasSuffix("fixture failure without newline\n"), "Failure stderr final line is retained")
        retry.install()
        expect(runCount(failureSource) == 1, "Failure cannot bypass preflight with install")
        try FileManager.default.removeItem(at: failureSource.appendingPathComponent("fail-check"))
        retry.preflight()
        let retryFinished = await waitUntil { !retry.isBusy }
        expect(retryFinished && retry.phase == .ready && retry.canInstall, "Corrected prerequisite can be rechecked")
        expect(retry.exitCode == 0 && retry.notice == nil && runCount(failureSource) == 2, "Retry resets stale failure state without installing")
        try Data().write(to: failureSource.appendingPathComponent("fail-install"))
        retry.install()
        let installFailureFinished = await waitUntil { !retry.isBusy }
        expect(installFailureFinished && retry.phase == .failed && retry.exitCode == 8, "Failed install reports a nonzero backend status")
        expect(retry.showLog && retry.log.text.hasSuffix("fixture install failure without newline\n"), "Install failure exposes drained stderr")
        expect(!retry.canInstall && runCount(failureSource) == 3, "Install failure requires another preflight before retry")

        let previewSource = try makeFixture("preview fixture")
        let preview = makeModel(source: previewSource, preview: true)
        preview.preflight()
        preview.install()
        try await Task.sleep(nanoseconds: 50_000_000)
        expect(preview.phase == .ready && !preview.canInstall, "Preview stays non-installable")
        expect(runCount(previewSource) == 0 && preview.log.text.isEmpty, "Preview never invokes backend")
        let missing = makeModel(source: fixtureRoot.appendingPathComponent("missing"), preview: false)
        missing.preflight()
        expect(missing.phase == .failed && missing.exitCode == 1 && missing.notice != nil, "Missing repository fails without a process")
        print("SetupWizardTests: \(count) checks passed")
    }

    @MainActor private static func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}
