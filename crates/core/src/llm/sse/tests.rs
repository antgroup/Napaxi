use super::*;

#[test]
fn note_stream_retry_emits_reset_only_after_output_started() {
    let error = anyhow!("connection reset by peer");

    let mut events = Vec::new();
    let _ = note_stream_retry(0, false, &error, &mut |event| events.push(event));
    assert!(
        events.is_empty(),
        "no reset before output has started: nothing to discard"
    );

    let mut events = Vec::new();
    let _ = note_stream_retry(0, true, &error, &mut |event| events.push(event));
    assert_eq!(events.len(), 1);
    assert!(matches!(
        &events[0],
        LlmStreamEvent::StreamReset { reason } if reason.contains("connection reset")
    ));
}

#[test]
fn retry_after_header_overrides_backoff() {
    let error = anyhow::Error::new(RetryableHttpError {
        message: "LLM provider error (429): slow down".to_string(),
        retry_after: Some(Duration::from_secs(7)),
    });
    assert_eq!(
        stream_retry_delay_for(0, Some(&error)),
        Duration::from_secs(7)
    );
}

#[test]
fn retryable_http_error_carries_message() {
    let error = RetryableHttpError {
        message: "LLM provider error (503): down".to_string(),
        retry_after: None,
    };
    assert!(error.to_string().contains("503"));
}

#[test]
fn backoff_grows_and_is_bounded() {
    // Without a Retry-After hint, backoff is exponential but capped at ~8s
    // plus up to 25% jitter.
    let first = stream_retry_delay_for(0, None);
    let late = stream_retry_delay_for(5, None);
    assert!(first <= Duration::from_millis(250 + 64));
    assert!(late <= Duration::from_millis(8_000 + 2_000));
}

#[test]
fn guard_sse_buffer_accepts_buffer_within_limit() {
    let buffer = "data: {\"hello\":\"world\"}\n";
    assert!(guard_sse_buffer(buffer).is_ok());
    // Right at the limit is still allowed; only growth past it fails.
    let at_limit = "a".repeat(MAX_SSE_BUFFER);
    assert!(guard_sse_buffer(&at_limit).is_ok());
}

#[test]
fn guard_sse_buffer_rejects_buffer_over_limit() {
    // Simulates a provider that keeps sending bytes without a newline: the
    // buffer can never be drained, so the guard must reject it.
    let oversized = "a".repeat(MAX_SSE_BUFFER + 1);
    let error = guard_sse_buffer(&oversized).expect_err("oversized buffer must error");
    assert!(error.to_string().contains("maximum buffered size"));
}
