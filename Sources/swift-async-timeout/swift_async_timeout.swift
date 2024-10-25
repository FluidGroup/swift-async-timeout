
public enum TimeoutHandlerError: Error {
  case timeoutOccured
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func withTimeout<Return: Sendable>(
  isolation: isolated (any Actor)? = #isolation,
  for duration: ContinuousClock.Instant.Duration,
  @_inheritActorContext _ operation: @escaping @Sendable () async throws -> Return
) async throws -> Return {
  return try await withTimeout(
    isolation: isolation,
    sleep: { try await Task.sleep(for: duration) },
    operation
  )
}

public func withTimeout<Return: Sendable>(
  isolation: isolated (any Actor)? = #isolation,
  nanoseconds: UInt64,
  @_inheritActorContext _ operation: @escaping @Sendable () async throws -> Return
) async throws -> Return {
  return try await withTimeout(
    isolation: isolation,
    sleep: { try await Task.sleep(nanoseconds: nanoseconds) },
    operation
  )
}

private func withTimeout<Return: Sendable>(
  isolation: isolated (any Actor)? = #isolation,
  sleep: @escaping () async throws -> Void,
  @_inheritActorContext _ operation: @escaping @Sendable () async throws -> Return
) async throws -> Return {

  let task = Ref<Task<(), Never>>(value: nil)
  let timeoutTask = Ref<Task<(), any Error>>(value: nil)

  let flag = Flag()

  return try await withTaskCancellationHandler {

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Return, Error>) in

      do {
        try Task.checkCancellation()
      } catch {
        continuation.resume(throwing: error)
        return
      }

      let _task = Task {
        do {
          let taskResult = try await operation()

          await flag.performIf(expected: false) {
            continuation.resume(returning: taskResult)
            return true
          }
        } catch {
          await flag.performIf(expected: false) {
            continuation.resume(throwing: error)
            return true
          }
        }
      }

      task.value = _task

      let _timeoutTask = Task {
        try await sleep()
        _task.cancel()

        await flag.performIf(expected: false) {
          continuation.resume(throwing: TimeoutHandlerError.timeoutOccured)
          return true
        }

      }

      timeoutTask.value = _timeoutTask
    }
  } onCancel: {
    task.value?.cancel()
    timeoutTask.value?.cancel()
  }
}


private final class Ref<T>: @unchecked Sendable {
  var value: T?

  init(value: T?) {
    self.value = value
  }
}

private actor Flag {
  var value: Bool = false

  func set(value: Bool) {
    self.value = value
  }

  func performIf(expected: Bool, perform: @Sendable () -> Bool) {
    if value == expected {
      value = perform()
    }
  }
}

