import Foundation

final class NativeCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

private final class NativeProgressContext {
    let cancellation: NativeCancellation
    let update: (Int64, Int64) -> Void
    init(_ cancellation: NativeCancellation, update: @escaping (Int64, Int64) -> Void) {
        self.cancellation = cancellation
        self.update = update
    }
}

private let nativeProgress: @convention(c) (Int64, Int64, Int32, Int32, UnsafeMutableRawPointer?) -> Int32 = { done, total, _, _, pointer in
    guard let pointer else { return 1 }
    let context = Unmanaged<NativeProgressContext>.fromOpaque(pointer).takeUnretainedValue()
    if context.cancellation.isCancelled { return 1 }
    context.update(done, total)
    return 0
}

enum NativeCore {
    /// Runs blocking Rust/C++ off the main thread. The context is retained until native code returns.
    static func call(_ request: [String: Any], cancellation: NativeCancellation = NativeCancellation(), progress: @escaping (Int64, Int64) -> Void = { _, _ in }) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: request)
        let json = String(decoding: data, as: UTF8.self)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let context = NativeProgressContext(cancellation, update: progress)
                let pointer = Unmanaged.passRetained(context).toOpaque()
                defer { Unmanaged<NativeProgressContext>.fromOpaque(pointer).release() }
                let result = json.withCString { gd_execute($0, nativeProgress, pointer) }
                guard let result else {
                    continuation.resume(throwing: AppFailure(message: "下载核心未返回结果。"))
                    return
                }
                defer { gd_free(result) }
                do {
                    let output = Data(String(cString: result).utf8)
                    guard let envelope = try JSONSerialization.jsonObject(with: output) as? [String: Any] else { throw AppFailure(message: "下载核心返回无效数据。") }
                    if let message = envelope["error"] as? String { throw AppFailure(message: message) }
                    guard let value = envelope["ok"] as? [String: Any] else { throw AppFailure(message: "下载核心缺少结果。") }
                    continuation.resume(returning: value)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
