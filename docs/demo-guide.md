# Demo Guide

The Flutter app is the project-level demo. Smaller platform apps can live under
`examples/` when they validate adapter integration from a real host app.

Project demo:

```text
examples/flutter/
```

Android SDK integration check:

```text
examples/integration/android/
```

iOS SDK integration check:

```text
examples/integration/ios/host/
examples/integration/ios/app/
```

Examples should depend on SDK adapters from `packages/` and should not contain
reusable SDK implementation code.
