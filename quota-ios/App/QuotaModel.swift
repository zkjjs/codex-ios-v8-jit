import SwiftUI
import WidgetKit

@MainActor
final class QuotaModel: ObservableObject {
    @Published var snapshot = SharedStore.loadSnapshot()
    @Published var connection = SharedStore.loadConnection()
    @Published var error: String?
    @Published var loading = false
    private var generation = UUID()
    private let fetch: (ServerConnection) async throws -> QuotaSnapshot

    init(fetch: @escaping (ServerConnection) async throws -> QuotaSnapshot = QuotaClient.fetch) {
        self.fetch = fetch
    }

    func connect(server: String, code: String) async -> Bool {
        guard !loading else { return false }
        loading = true
        let requestGeneration = generation
        defer { if generation == requestGeneration { loading = false } }
        let candidate = ServerConnection(server: server, accessCode: code)
        do {
            let value = try await fetch(candidate)
            guard generation == requestGeneration else { return false }
            try SharedStore.saveConnection(candidate)
            connection = candidate
            accept(value)
            return true
        } catch {
            if generation == requestGeneration { self.error = error.localizedDescription }
            return false
        }
    }

    func refresh() async {
        guard let connection, !loading else { return }
        loading = true
        let requestGeneration = generation
        defer { if generation == requestGeneration { loading = false } }
        do {
            let value = try await fetch(connection)
            if generation == requestGeneration { accept(value) }
        }
        catch is CancellationError { }
        catch { if generation == requestGeneration { self.error = error.localizedDescription } }
    }

    private func accept(_ value: QuotaSnapshot) {
        snapshot = value
        error = nil
        SharedStore.saveSnapshot(value)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func disconnect() {
        generation = UUID()
        loading = false
        SharedStore.clear()
        connection = nil
        snapshot = nil
        error = nil
        WidgetCenter.shared.reloadAllTimelines()
    }
}
