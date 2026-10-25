import BackgroundTasks
import Foundation

@MainActor
final class ContinuedDownloadRunner {
    private var registrations = Set<String>()
    private var active = Set<UUID>()
    private var pending: [UUID: (BGContinuedProcessingTask) -> Void] = [:]
    private var cancelled = Set<UUID>()

    private func identifier(_ id: UUID) -> String { "\(Bundle.main.bundleIdentifier!).download.\(id.uuidString)" }

    func submit(id: UUID, name: String, run: @escaping (BGContinuedProcessingTask) -> Void) throws {
        guard active.isEmpty, pending.isEmpty else { throw AppFailure(message: "请先暂停当前直连下载，再启动另一个任务。") }
        let identifier = identifier(id)
        if !registrations.contains(identifier) {
            let success = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
                guard let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
                MainActor.assumeIsolated {
                    guard let self, !self.cancelled.contains(id), let work = self.pending.removeValue(forKey: id) else {
                        task.setTaskCompleted(success: false)
                        return
                    }
                    self.active.insert(id)
                    work(task)
                }
            }
            guard success else { throw AppFailure(message: "系统未能注册后台下载任务。") }
            registrations.insert(identifier)
        }
        cancelled.remove(id)
        pending[id] = run
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "gdirect 下载", subtitle: name)
        request.strategy = .queue
        do { try BGTaskScheduler.shared.submit(request) }
        catch { pending.removeValue(forKey: id); throw AppFailure(message: "系统暂时无法接受后台直连任务，请稍后重试。") }
    }
    func cancelPending(_ id: UUID) {
        cancelled.insert(id)
        pending.removeValue(forKey: id)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier(id))
    }
    func finished(_ id: UUID) { active.remove(id) }
}
