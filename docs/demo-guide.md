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

The iOS package is the Flutter demo itself; build and install it through the
Flutter iOS packaging flow instead of a separate iOS package.

Examples should depend on SDK adapters from `packages/` and should not contain
reusable SDK implementation code.
