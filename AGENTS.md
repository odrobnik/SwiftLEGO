# Agent Guidelines

- **Platform Target**: Ship features for iOS 26 and newer; avoid relying on deprecated APIs.
- **Concurrency**: Prefer modern Swift structured concurrency (`async`/`await`, `Task`, actors) over legacy completion handlers whenever possible.
- **Unit Testing**: Use Swift Testing exclusively. Do not introduce or reference XCTest-based tests.
- **Pluralization**: For any text that needs plural-aware output, rely on Swift's `(inflect: true)` syntax—never the manual `parts == 1 ? "part" : "parts"` pattern.  
  - Example: `Text("Missing ^[\(missingCount) part](inflect: true)")`
