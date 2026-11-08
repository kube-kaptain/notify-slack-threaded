#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Copyright (c) 2025-2026 Kaptain contributors (Fred Cooke)
#
# Validation: configuration against what the token can do, blocking only when
# slackRequired is true.

load test_helper

@test "a complete configuration passes" {
  run validate-notify-slack
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"OK: Slack notify configuration"* ]]
}

@test "failures are reported but do not block by default" {
  rm "${NOTIFY_CONFIG_BASE}/slackChannelId"
  run validate-notify-slack
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"FAIL: slackChannelId not found"* ]]
}

@test "failures block when slackRequired is true" {
  rm "${NOTIFY_CONFIG_BASE}/slackChannelId"
  echo true > "${NOTIFY_CONFIG_BASE}/slackRequired"
  run validate-notify-slack
  [[ "${status}" -eq 1 ]]
}

@test "customisation without chat:write.customize fails" {
  echo "Run UAT" > "${NOTIFY_CONFIG_BASE}/slackUsername"
  run validate-notify-slack
  [[ "${output}" == *"lacks chat:write.customize"* ]]
}

@test "missing reactions:write fails" {
  export FAKE_SCOPES=chat:write
  run validate-notify-slack
  [[ "${output}" == *"lacks the reactions:write scope"* ]]
}

@test "a thread key without history access fails" {
  export NOTIFY_THREAD_KEY=run-stage-1.2.3
  export FAKE_ERROR_METHOD=conversations.history FAKE_ERROR=missing_scope
  run validate-notify-slack
  [[ "${output}" == *"cannot read slackChannelId history"* ]]
}

@test "bad values are each reported" {
  echo "#deploys" > "${NOTIFY_CONFIG_BASE}/slackChannelId"
  echo "bob" > "${NOTIFY_CONFIG_BASE}/slackFailureUserIds"
  echo "prod" > "${NOTIFY_CONFIG_BASE}/slackContext"
  echo "soon" > "${NOTIFY_CONFIG_BASE}/slackThreadLookbackDays"
  echo "fast" > "${NOTIFY_CONFIG_BASE}/slackCurlMaxTime"
  run validate-notify-slack
  [[ "${output}" == *"slackChannelId '#deploys' is not a channel ID"* ]]
  [[ "${output}" == *"slackFailureUserIds entry 'bob' is not a user ID"* ]]
  [[ "${output}" == *"slackContext must be 'deploy' or 'build'"* ]]
  [[ "${output}" == *"slackThreadLookbackDays 'soon'"* ]]
  [[ "${output}" == *"slackCurlMaxTime 'fast'"* ]]
}

@test "tooling validation finds curl and yq" {
  run validate-tooling-slack
  [[ "${status}" -eq 0 ]]
}
