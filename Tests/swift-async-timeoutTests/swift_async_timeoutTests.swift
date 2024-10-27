import XCTest

@testable import swift_async_timeout

@MainActor
func runUI() {}

final class swift_async_timeoutTests: XCTestCase {
  
  @MainActor
  func test_execution() async throws {
    try await withTimeout(nanoseconds: 2_000_000_000) {
      runUI()
    }    
  }

  func test_succeeded_on_time() async throws {

    try await withTimeout(nanoseconds: 2_000_000_000) {
      await delay(timeinterval: 1, onCancel: {})
    }

    // no error occurs

  }

  func test_timeout_occured() async throws {

    let exp = expectation(description: "cancel inside")
    let timeoutErrorExp = expectation(description: "timeout error")

    do {
      try await withTimeout(nanoseconds: 500_000_000) {
        await delay(
          timeinterval: 10000000,
          onCancel: {
            exp.fulfill()
          }
        )
      }
    } catch {
      switch error {
      case TimeoutHandlerError.timeoutOccured:
        timeoutErrorExp.fulfill()
      default:
        XCTFail()
      }
    }

    await fulfillment(of: [exp, timeoutErrorExp])
  }

  func test_cancelled_before_timeout() async throws {

    let exp = expectation(description: "cancel inside")

    let nextExp = expectation(description: "next")

    let unstructuredTask = Task {
      do {
        try await withTimeout(nanoseconds: 500_000_000) {
          await delay(
            timeinterval: 1,
            onCancel: {
              exp.fulfill()
            }
          )
        }
      } catch {
        switch error {
        case TimeoutHandlerError.timeoutOccured:
          XCTFail()
        case is CancellationError:
          break
        default:
          XCTFail(error.localizedDescription)
        }
      }
      nextExp.fulfill()
    }

    try? await Task.sleep(nanoseconds: 1_000_000)

    unstructuredTask.cancel()

    await fulfillment(of: [nextExp, exp])

  }
}

private func delay(timeinterval: TimeInterval, onCancel: @escaping @Sendable () -> Void) async {

  await withTaskCancellationHandler {

    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) -> Void in
      DispatchQueue.main.asyncAfter(deadline: .now() + timeinterval) {
        c.resume()
      }
    }
  } onCancel: {
    onCancel()
  }

}
