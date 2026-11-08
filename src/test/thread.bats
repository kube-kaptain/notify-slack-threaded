#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Copyright (c) 2025-2026 Kaptain contributors (Fred Cooke)
#
# Threading: the first post opens the thread, later posts reply into it, and a
# NOTIFY_THREAD_KEY rejoins a thread an earlier run opened.

load test_helper

@test "providers need a message" {
  run notify-info-slack
  [[ "${status}" -eq 42 ]]
}

@test "first post opens the thread and records it" {
  run notify-info-slack "*Starting* deploy"
  [[ "${status}" -eq 0 ]]
  [[ "$(calls chat.postMessage)" == 'chat.postMessage {"channel":"C0DEPLOY","text":"*Starting* deploy"}' ]]
  [[ "$(thread_ts)" == "1700000000.000100" ]]
}

@test "later posts reply into the thread" {
  notify-info-slack first
  run notify-info-slack second
  [[ "${status}" -eq 0 ]]
  [[ "$(calls chat.postMessage | tail -1)" == *'"thread_ts":"1700000000.000100"'* ]]
}

@test "quotes and newlines survive into the JSON body" {
  notify-info-slack 'say "hi"
line two'
  [[ "$(calls chat.postMessage)" == *'"text":"say \"hi\"\nline two"'* ]]
}

@test "level prefixes default, can be replaced, and can be turned off" {
  notify-warning-slack w
  notify-error-slack e
  [[ "$(calls chat.postMessage | head -1)" == *'"text":":warning: w"'* ]]
  [[ "$(calls chat.postMessage | tail -1)" == *'"text":":rotating_light: e"'* ]]

  echo ":fire:" > "${NOTIFY_CONFIG_BASE}/slackWarningPrefix"
  : > "${NOTIFY_CONFIG_BASE}/slackErrorPrefix"
  notify-warning-slack w2
  notify-error-slack e2
  [[ "$(calls chat.postMessage | tail -2 | head -1)" == *'"text":":fire: w2"'* ]]
  [[ "$(calls chat.postMessage | tail -1)" == *'"text":"e2"'* ]]
}

@test "with a thread key and no earlier thread, the opening post carries the key" {
  export NOTIFY_THREAD_KEY=run-stage-1.2.3
  run notify-info-slack start
  [[ "${status}" -eq 0 ]]
  [[ "$(call_count conversations.history)" -eq 1 ]]
  [[ "$(calls chat.postMessage)" == *'"metadata":{"event_type":"kaptain_notify_thread","event_payload":{"thread_key":"run-stage-1.2.3"}}'* ]]
}

@test "with a thread key, a thread an earlier run opened is joined" {
  export NOTIFY_THREAD_KEY=run-stage-1.2.3
  export FAKE_HISTORY_KEY=run-stage-1.2.3
  run notify-info-slack start
  [[ "${status}" -eq 0 ]]
  [[ "$(calls chat.postMessage)" == *'"thread_ts":"1600000000.000100"'* ]]
  [[ "$(calls chat.postMessage)" != *metadata* ]]
  [[ "$(thread_ts)" == "1600000000.000100" ]]
}

@test "without a thread key, history is never read" {
  notify-info-slack start
  [[ "$(call_count conversations.history)" -eq 0 ]]
}

@test "the token is passed on stdin, never as an argument" {
  notify-info-slack start
  ! grep -q xoxb "${FAKE_DIR}/argv"
  grep -q 'header = "Authorization: Bearer xoxb-test-token"' "${FAKE_DIR}/stdin"
}

@test "a Slack error fails the provider with the reason" {
  export FAKE_ERROR_METHOD=chat.postMessage FAKE_ERROR=channel_not_found
  run notify-info-slack start
  [[ "${status}" -ne 0 ]]
  [[ "${output}" == *"chat.postMessage failed: channel_not_found"* ]]
}
