part of '../main.dart';

// ---------------------------------------------------------------------------
// SandboxPtyEvents — single shared broadcast stream for the PTY event channel.
//
// Flutter's [EventChannel] only supports ONE active platform listener at a
// time.  Each `receiveBroadcastStream()` call registers a new `StreamHandler`
// on the native side, replacing the previous one.  If two classes create their
// own `EventChannel('com.napaxi.flutter/sandbox_pty_events')` streams, the
// second call overwrites the native `sandboxPtyEventSink`, killing event
// delivery for the first stream permanently.
//
// To avoid this, all PTY event consumers must listen to [SandboxPtyEvents.shared]
// and use [SandboxPtyEvents.method] instead of creating their own channels.
// ---------------------------------------------------------------------------

/// Namespace for the shared sandbox PTY platform channels.
///
/// Do not instantiate — use the static [shared] stream and [method] channel.
final class SandboxPtyEvents {
  SandboxPtyEvents._();

  /// The single shared broadcast stream for
  /// `com.napaxi.flutter/sandbox_pty_events`.
  ///
  /// All PTY event consumers must listen to this stream (filtering by
  /// `sessionId` on the Dart side) rather than creating their own
  /// [EventChannel].
  static final Stream<dynamic> shared = const EventChannel(
    'com.napaxi.flutter/sandbox_pty_events',
  ).receiveBroadcastStream().asBroadcastStream();

  /// Shared method channel for `com.napaxi.flutter/sandbox_pty`.
  static const MethodChannel method = MethodChannel(
    'com.napaxi.flutter/sandbox_pty',
  );
}