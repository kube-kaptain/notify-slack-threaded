#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Copyright (c) 2025-2026 Kaptain contributors (Fred Cooke)
#
# Alerts: standalone posts to their own channel, with a mention, never part of
# the deploy thread, and DMs to their own list of people.

load test_helper

@test "alerts post to the alert channel with @here and leave the thread alone" {
  run alert-slack drift
  [[ "${status}" -eq 0 ]]
  [[ "$(calls chat.postMessage)" == 'chat.postMessage {"channel":"C0ALERT","text":"<!here> :rotating_light: drift"}' ]]
  [[ ! -e "${NOTIFY_WORK_BASE}/notify/slack/ts" ]]
}

@test "the alert mention can be replaced or turned off" {
  echo "<!channel>" > "${NOTIFY_CONFIG_BASE}/slackAlertMention"
  alert-slack one
  : > "${NOTIFY_CONFIG_BASE}/slackAlertMention"
  alert-slack two
  [[ "$(calls chat.postMessage | head -1)" == *'"text":"<!channel> :rotating_light: one"'* ]]
  [[ "$(calls chat.postMessage | tail -1)" == *'"text":":rotating_light: two"'* ]]
}

@test "alerts need their own channel" {
  rm "${NOTIFY_CONFIG_BASE}/slackAlertChannelId"
  run alert-slack drift
  [[ "${status}" -ne 0 ]]
  [[ "$(call_count chat.postMessage)" -eq 0 ]]
}

@test "alert DMs go to the alert list without the mention" {
  echo "U0ONE" > "${NOTIFY_CONFIG_BASE}/slackAlertUserIds"
  export ENVIRONMENT=run-stage VERSION=1.2.3
  alert-slack drift
  [[ "$(calls chat.postMessage | grep '"channel":"U0ONE"')" == *'"text":"Hi <@U0ONE>, an alert was raised in a Kubernetes deployment, shown below. A link to it is below that.\n\n:rotating_light: drift\n\nAlert in run-stage:1.2.3: https://'* ]]
}
