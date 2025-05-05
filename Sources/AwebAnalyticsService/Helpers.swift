import Foundation

func withTimeout<T>(
    seconds timeout: TimeInterval,
    operation: @escaping () async -> T
) async -> T? {
    let stream = AsyncStream<T?> { continuation in
        Task {
            let value = await operation()
            continuation.yield(value)
            continuation.finish()
        }

        Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            continuation.yield(nil)
            continuation.finish()
        }
    }

    for await value in stream {
        return value
    }

    return nil
}
