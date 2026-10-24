import SwiftUI
import WidgetKit

@MainActor
final class QuotaModel: ObservableObject {
    @Published var snapshot = SharedStore.loadSnapshot()
    @Published var connection = SharedStore.loadConnection()
    @Published var error: String?
    @Published var loading = false

    func connect(server: String, code: String) async -> Bool {
        guard !loading else { return false }
        loading = true
        defer { loading = false }
        let candidate = ServerConnection(server: server, accessCode: code)
        do {
            let value = try await QuotaClient.fetch(candidate)
            try SharedStore.saveConnection(candidate)
            connection = candidate
            accept(value)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func refresh() async {
        guard let connection, !loading else { return }
        loading = true
        defer { loading = false }
        do { accept(try await QuotaClient.fetch(connection)) }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }

    private func accept(_ value: QuotaSnapshot) {
        snapshot = value
        error = nil
        SharedStore.saveSnapshot(value)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func disconnect() {
        SharedStore.clear()
        connection = nil
        snapshot = nil
        error = nil
        WidgetCenter.shared.reloadAllTimelines()
    }
}
