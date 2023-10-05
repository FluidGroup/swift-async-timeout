

```swift
try await withTimeout(nanoseconds: 500_000_000) {
  await myOperation()
}
```
