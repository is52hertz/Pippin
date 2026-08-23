import Foundation
import PippinCore
import PippinServer
import Testing

@testable import PippinApp

@MainActor
@Suite("Pippin presentation model")
struct PippinPresentationModelTests {
    private struct TestPermissionProvider: PermissionProviding {
        let value: PermissionSnapshot

        func currentPermissions() async -> PermissionSnapshot { value }
    }

    private actor TestRuntime: ServerRuntimeServing {
        var value: AppRuntimeSnapshot
        var updateError: PippinError?
        var updates: [Config] = []

        init(value: AppRuntimeSnapshot, updateError: PippinError? = nil) {
            self.value = value
            self.updateError = updateError
        }

        func start() async throws -> AppRuntimeSnapshot { value }

        func snapshot() async -> AppRuntimeSnapshot { value }

        func updateConfig(_ config: Config) async throws -> AppRuntimeSnapshot {
            updates.append(config)
            if let updateError { throw updateError }
            let previous = value.server!
            value = AppRuntimeSnapshot(
                state: value.state,
                detail: value.detail,
                server: ServerSnapshot(
                    host: previous.host,
                    port: previous.port,
                    sessionCount: previous.sessionCount,
                    config: config,
                    permissions: previous.permissions
                )
            )
            return value
        }

        func stop() async {}
    }

    @Test("successful module update advances the mirror")
    func successfulUpdate() async {
        let runtime = TestRuntime(value: snapshot())
        let model = PippinPresentationModel(runtime: runtime)
        await model.refresh()

        await model.setModuleWrites(true, module: "reminders")

        #expect(model.config.modules["reminders"]?.writes == true)
        #expect(model.errorMessage == nil)
        #expect(await runtime.updates.count == 1)
    }

    @Test("failed module update leaves the mirror unchanged and surfaces the error")
    func failedUpdate() async {
        let runtime = TestRuntime(
            value: snapshot(),
            updateError: PippinError(
                .backendUnavailable,
                detail: "config.json",
                hint: "Could not save settings."
            )
        )
        let model = PippinPresentationModel(runtime: runtime)
        await model.refresh()

        await model.setModuleEnabled(false, module: "reminders")

        #expect(model.config.modules["reminders"]?.enabled == true)
        #expect(model.errorMessage == "Could not save settings.")
        #expect(await runtime.updates.count == 1)
    }

    @Test("runtime saves config before applying it to the host")
    func runtimePersistsThenApplies() async throws {
        let url = temporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let provider = TestPermissionProvider(value: permissions())
        let host = makeHost(permissionProvider: provider)
        let runtime = ServerRuntime(
            configURL: url,
            permissionProvider: provider,
            runningHost: host
        )
        var updated = Config()
        updated.modules["mail"]?.enabled = false

        let result = try await runtime.updateConfig(updated)

        #expect(try Config.load(from: url) == updated)
        #expect(await host.currentConfig == updated)
        #expect(result.server?.config == updated)
    }

    @Test("runtime does not update the host when atomic persistence fails")
    func runtimeSaveFailureDoesNotApply() async throws {
        let url = temporaryConfigURL()
        // A directory at the destination makes the atomic file write fail.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let provider = TestPermissionProvider(value: permissions())
        let host = makeHost(permissionProvider: provider)
        let runtime = ServerRuntime(
            configURL: url,
            permissionProvider: provider,
            runningHost: host
        )
        let original = await host.currentConfig
        var updated = original
        updated.modules["mail"]?.enabled = false

        do {
            _ = try await runtime.updateConfig(updated)
            Issue.record("Expected persistence to fail")
        } catch {
            // The concrete Foundation error is platform-owned; the ordering is
            // what this regression verifies.
        }

        #expect(await host.currentConfig == original)
    }

    private func snapshot() -> AppRuntimeSnapshot {
        AppRuntimeSnapshot(
            state: .running,
            detail: nil,
            server: ServerSnapshot(
                host: "127.0.0.1",
                port: 8_080,
                sessionCount: 3,
                config: Config(),
                permissions: permissions()
            )
        )
    }

    private func permissions() -> PermissionSnapshot {
        PermissionSnapshot(
            reminders: .granted,
            mailAutomation: .notDetermined,
            fullDiskAccess: .denied
        )
    }

    private func makeHost(
        permissionProvider: some PermissionProviding
    ) -> ServerHost {
        ServerHost(
            config: Config(),
            tokenStore: .local(token: "app-runtime-test"),
            registry: ProductionToolCatalogue.registry,
            permissionProvider: permissionProvider
        )
    }

    private func temporaryConfigURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "pippin-runtime-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "config.json")
    }
}
