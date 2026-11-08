#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Copyright (c) 2025-2026 Kaptain contributors (Fred Cooke)
#
# Outcomes: success and failure reply, react on the opening post, and failure
# also shows in the channel and DMs the people listed.

load test_helper

@test "a warning replies and marks the opening post, once however many there are" {
  notify-info-slack start
  run notify-warning-slack slow
  [[ "${status}" -eq 0 ]]
  [[ "$(calls chat.postMessage | tail -1)" == *'"text":":warning: slow","thread_ts":"1700000000.000100"'* ]]
  [[ "$(calls reactions.add)" == *'"timestamp":"1700000000.000100","name":"warning"'* ]]

  export FAKE_ERROR_METHOD=reactions.add FAKE_ERROR=already_reacted
  run notify-warning-slack slower
  [[ "${status}" -eq 0 ]]
}

@test "the warning reaction can be replaced or turned off" {
  echo ":eyes:" > "${NOTIFY_CONFIG_BASE}/slackWarningReaction"
  notify-warning-slack one
  [[ "$(calls reactions.add)" == *'"name":"eyes"'* ]]
  : > "${NOTIFY_CONFIG_BASE}/slackWarningReaction"
  notify-warning-slack two
  [[ "$(call_count reactions.add)" -eq 1 ]]
}

@test "success replies and reacts with a tick" {
  notify-info-slack start
  run notify-success-slack done
  [[ "${status}" -eq 0 ]]
  [[ "$(calls chat.postMessage | tail -1)" == *'"text":":white_check_mark: done"'* ]]
  [[ "$(calls reactions.add)" == *'"timestamp":"1700000000.000100","name":"white_check_mark"'* ]]
}

@test "failure replies into the channel too and reacts with a cross" {
  notify-info-slack start
  run notify-failure-slack broke
  [[ "${status}" -eq 0 ]]
  [[ "$(calls chat.postMessage | tail -1)" == *'"text":":x: broke","thread_ts":"1700000000.000100","reply_broadcast":true'* ]]
  [[ "$(calls reactions.add)" == *'"name":"x"'* ]]
}

@test "reactions can be replaced, with or without colons, or turned off" {
  echo ":tada:" > "${NOTIFY_CONFIG_BASE}/slackSuccessReaction"
  notify-success-slack done
  [[ "$(calls reactions.add)" == *'"name":"tada"'* ]]

  : > "${NOTIFY_CONFIG_BASE}/slackFailureReaction"
  notify-failure-slack broke
  [[ "$(call_count reactions.add)" -eq 1 ]]
}

@test "a reaction already on a rejoined thread is not an error" {
  notify-info-slack start
  export FAKE_ERROR_METHOD=reactions.add FAKE_ERROR=already_reacted
  run notify-failure-slack broke again
  [[ "${status}" -eq 0 ]]
}

@test "failure DMs each listed user with the deploy wording and thread link" {
  echo "U0ONE, U0TWO" > "${NOTIFY_CONFIG_BASE}/slackFailureUserIds"
  export ENVIRONMENT=run-stage VERSION=1.2.3
  notify-info-slack start
  run notify-failure-slack broke
  [[ "${status}" -eq 0 ]]
  [[ "$(calls chat.postMessage | grep -c '"channel":"U0')" -eq 2 ]]
  [[ "$(calls chat.postMessage | grep '"channel":"U0ONE"')" == *'"text":"Hi <@U0ONE>, a Kubernetes deployment has failed as shown below. A link to the thread is below that.\n\n:x: broke\n\nDeployment run-stage:1.2.3 thread: https://test.slack.com/archives/C0DEPLOY/p1700000000000100"'* ]]
}

@test "failure DM wording follows slackContext build" {
  echo "U0ONE" > "${NOTIFY_CONFIG_BASE}/slackFailureUserIds"
  echo "build" > "${NOTIFY_CONFIG_BASE}/slackContext"
  notify-failure-slack broke
  [[ "$(calls chat.postMessage | grep '"channel":"U0ONE"')" == *'"text":"Hi <@U0ONE>, a build has failed'*'Build thread: https://'* ]]
}

@test "DM templates expand set env vars, keep unset ones, and never expand the message" {
  echo "U0ONE" > "${NOTIFY_CONFIG_BASE}/slackFailureUserIds"
  echo 'PR {PR_NUMBER} {NOPE} thread:' > "${NOTIFY_CONFIG_BASE}/slackFailureLinkLabel"
  : > "${NOTIFY_CONFIG_BASE}/slackFailureDmLeader"
  export PR_NUMBER=47
  notify-failure-slack 'broke in {HOME}'
  [[ "$(calls chat.postMessage | grep '"channel":"U0ONE"')" == *'"text":":x: broke in {HOME}\n\nPR 47 {NOPE} thread: https://'* ]]
}
