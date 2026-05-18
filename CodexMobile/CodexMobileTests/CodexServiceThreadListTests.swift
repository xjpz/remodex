// FILE: CodexServiceThreadListTests.swift
// Purpose: Verifies thread-list fetch shape and local ordering so sidebar results stay recent-activity ordered.
// Layer: Unit Test
// Exports: CodexServiceThreadListTests
// Depends on: XCTest, CodexMobile

import XCTest
@testable import CodexMobile

@MainActor
final class CodexServiceThreadListTests: XCTestCase {
    private static var retainedServices: [CodexService] = []

    func testListThreadsRequestsCappedActiveThreadsAndAppServerSourceKinds() async throws {
        let service = makeService()
        service.isConnected = true
        service.isInitialized = true

        var activeRequestParams: RPCObject?
        var requestCount = 0

        service.requestTransportOverride = { method, params in
            guard method == "thread/list" else {
                return RPCMessage(
                    id: .string(UUID().uuidString),
                    result: .object([:]),
                    includeJSONRPC: false
                )
            }

            requestCount += 1
            activeRequestParams = params?.objectValue

            return RPCMessage(
                id: .string(UUID().uuidString),
                result: .object([
                    "threads": .array([]),
                ]),
                includeJSONRPC: false
            )
        }

        try await service.listThreads()

        XCTAssertEqual(activeRequestParams?["limit"]?.intValue, 70)
        XCTAssertNil(activeRequestParams?["archived"])
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(
            activeRequestParams?["sourceKinds"]?.arrayValue?.compactMap(\.stringValue),
            ["cli", "vscode", "appServer", "exec", "unknown"]
        )
    }

    func testListThreadsPublishesActiveThreadsFromSingleFetch() async throws {
        let service = makeService()
        service.isConnected = true
        service.isInitialized = true

        service.requestTransportOverride = { method, params in
            guard method == "thread/list" else {
                return RPCMessage(id: .string(UUID().uuidString), result: .object([:]), includeJSONRPC: false)
            }

            XCTAssertNil(params?.objectValue?["archived"])

            return RPCMessage(
                id: .string(UUID().uuidString),
                result: .object([
                    "threads": .array([
                        .object([
                            "id": .string("thread-active"),
                            "title": .string("Active thread"),
                        ]),
                    ]),
                ]),
                includeJSONRPC: false
            )
        }

        try await service.listThreads()
        XCTAssertEqual(service.threads.map(\.id), ["thread-active"])
        XCTAssertFalse(service.isLoadingThreads)
    }

    func testRealtimeSyncKeepsThreadListRequestsCapped() async {
        let service = makeService()
        service.isConnected = true
        service.isInitialized = true

        var activeRequestParams: RPCObject?
        var requestCount = 0

        service.requestTransportOverride = { method, params in
            guard method == "thread/list" else {
                return RPCMessage(id: .string(UUID().uuidString), result: .object([:]), includeJSONRPC: false)
            }

            requestCount += 1
            activeRequestParams = params?.objectValue

            return RPCMessage(
                id: .string(UUID().uuidString),
                result: .object(["threads": .array([])]),
                includeJSONRPC: false
            )
        }

        await service.syncThreadsList()

        XCTAssertEqual(activeRequestParams?["limit"]?.intValue, 70)
        XCTAssertNil(activeRequestParams?["archived"])
        XCTAssertEqual(requestCount, 1)
    }

    func testSortThreadsUsesUpdatedAtBeforeCreatedAtFallback() {
        let service = makeService()
        let laterByUpdatedAt = CodexThread(
            id: "later-by-updated-at",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 50)
        )
        let laterByCreatedAt = CodexThread(
            id: "later-by-created-at",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: nil
        )
        let oldestThread = CodexThread(
            id: "oldest-thread",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: nil
        )

        let sorted = service.sortThreads([oldestThread, laterByCreatedAt, laterByUpdatedAt])

        XCTAssertEqual(
            sorted.map(\.id),
            ["later-by-updated-at", "later-by-created-at", "oldest-thread"]
        )
    }

    func testUserRenameSurvivesStaleThreadListRefreshForPinnedThread() {
        let service = makeService()
        service.threads = [
            CodexThread(
                id: "pinned-thread",
                title: "Original server title",
                name: "Original server title",
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 20),
                cwd: "/Users/dev/project"
            ),
        ]
        service.pinThread("pinned-thread")

        service.renameThread("pinned-thread", name: "Renamed locally")
        service.reconcileLocalThreadsWithServer([
            CodexThread(
                id: "pinned-thread",
                title: "Original server title",
                name: "Original server title",
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 30),
                cwd: "/Users/dev/project"
            ),
        ])

        XCTAssertEqual(service.thread(for: "pinned-thread")?.displayTitle, "Renamed locally")
        XCTAssertEqual(service.pinnedThreadSnapshotsByRootID["pinned-thread"]?.first?.displayTitle, "Renamed locally")
    }

    private func makeService() -> CodexService {
        let suiteName = "CodexServiceThreadListTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let service = CodexService(defaults: defaults)
        Self.retainedServices.append(service)
        return service
    }
}
