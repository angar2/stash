// PasteService — paste 두 분기 + 에러 전파 + 정렬 갱신 검증
@testable import stash
import Testing
import Foundation
import AppKit

@Suite("PasteService")
@MainActor
struct PasteServiceTests {

    // MARK: - Helpers

    private func makeService(
        synthesizer: MockPasteSynthesizer = MockPasteSynthesizer(),
        pasteboard: MockPasteboard = MockPasteboard(),
        repository: InMemoryClipRepository = InMemoryClipRepository()
    ) -> (PasteService, MockPasteSynthesizer, MockPasteboard, InMemoryClipRepository) {
        let svc = PasteService(
            synthesizer: synthesizer,
            pasteboard: pasteboard,
            repository: repository,
            permissionService: PermissionService()
        )
        return (svc, synthesizer, pasteboard, repository)
    }

    private func makeClip(body: String? = "hello", isPinned: Bool = false) -> Clip {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return Clip(
            id: UUID(),
            type: body == nil ? .image : .text,
            body: body,
            filePath: nil,
            isFileExternal: false,
            fileOriginalPath: nil,
            fileBookmark: nil,
            sourceAppBundleId: nil,
            isPinned: isPinned,
            createdAt: now,
            lastUsedAt: now
        )
    }

    // MARK: - .autoPaste 분기

    @Test func autoPasteSetsStringSynthesizesAndUpdatesLastUsedAt() async throws {
        let (svc, synth, pb, repo) = makeService()
        let clip = makeClip(body: "hello")
        try await repo.insert(clip)
        let before = try await repo.fetchAll().first { $0.id == clip.id }!.lastUsedAt

        try await svc.paste(clip: clip, mode: .autoPaste)

        #expect(pb.strings[.string] == "hello")
        #expect(synth.callCount == 1)
        let after = try await repo.fetchAll().first { $0.id == clip.id }!.lastUsedAt
        #expect(after > before)
    }

    // MARK: - .copyBack 분기

    @Test func copyBackSetsStringSkipsSynthesizeAndUpdatesLastUsedAt() async throws {
        let (svc, synth, pb, repo) = makeService()
        let clip = makeClip(body: "world")
        try await repo.insert(clip)
        let before = try await repo.fetchAll().first { $0.id == clip.id }!.lastUsedAt

        try await svc.paste(clip: clip, mode: .copyBack)

        #expect(pb.strings[.string] == "world")
        #expect(synth.callCount == 0)
        let after = try await repo.fetchAll().first { $0.id == clip.id }!.lastUsedAt
        #expect(after > before)
    }

    // MARK: - synthesize 실패 → PasteError 전파 + updateLastUsedAt 미호출

    @Test func autoPasteThrowsKeyboardSimulationFailedAndLeavesLastUsedAtUnchanged() async throws {
        let (svc, synth, pb, repo) = makeService()
        synth.shouldThrow = true
        let clip = makeClip(body: "fail")
        try await repo.insert(clip)
        let before = try await repo.fetchAll().first { $0.id == clip.id }!.lastUsedAt

        await #expect(throws: PasteError.self) {
            try await svc.paste(clip: clip, mode: .autoPaste)
        }

        #expect(pb.strings[.string] == "fail")  // setString 은 synthesize 전 이미 호출됨
        #expect(synth.callCount == 1)
        let after = try await repo.fetchAll().first { $0.id == clip.id }!.lastUsedAt
        #expect(after == before)  // 정렬 갱신 미호출
    }

    // MARK: - body nil (image / file clip) → 빈 문자열 setString

    @Test func autoPasteWithNilBodyUsesEmptyString() async throws {
        let (svc, _, pb, repo) = makeService()
        let clip = makeClip(body: nil)
        try await repo.insert(clip)

        try await svc.paste(clip: clip, mode: .autoPaste)

        #expect(pb.strings[.string] == "")
    }

    // MARK: - setString 이 synthesize 전에 호출됨 (순서 보장)

    @Test func setStringHappensBeforeSynthesize() async throws {
        let (svc, synth, pb, repo) = makeService()
        let clip = makeClip(body: "ordered")
        try await repo.insert(clip)

        let capturedAtSynthesize = LockedString()
        synth.onSynthesize = { [pb] in
            capturedAtSynthesize.value = pb.strings[.string] ?? "<nil>"
        }

        try await svc.paste(clip: clip, mode: .autoPaste)

        #expect(capturedAtSynthesize.value == "ordered")
    }
}

/// onSynthesize 클로저 안에서 외부 상태 캡처용 (Sendable closure 격리).
private final class LockedString: @unchecked Sendable {
    var value: String = ""
}
