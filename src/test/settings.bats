#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Copyright (c) 2025-2026 Kaptain contributors (Fred Cooke)
#
# curl retry and timeout settings, and the name and icon customisation.

load test_helper

@test "curl gets the reliable defaults" {
  notify-info-slack start
  grep -q -- '--retry 3 --retry-delay 2 --connect-timeout 10 --max-time 20 --retry-max-time 70' "${FAKE_DIR}/argv"
}

@test "curl settings can be overridden, invalid values fall back" {
  echo 0 > "${NOTIFY_CONFIG_BASE}/slackCurlRetry"
  echo 5 > "${NOTIFY_CONFIG_BASE}/slackCurlMaxTime"
  echo junk > "${NOTIFY_CONFIG_BASE}/slackCurlRetryDelay"
  notify-info-slack start
  grep -q -- '--retry 0 --retry-delay 2 --connect-timeout 10 --max-time 5 --retry-max-time 70' "${FAKE_DIR}/argv"
}

@test "username and icon go on every post when set" {
  echo "Run UAT" > "${NOTIFY_CONFIG_BASE}/slackUsername"
  echo ":test_tube:" > "${NOTIFY_CONFIG_BASE}/slackIconEmoji"
  notify-info-slack start
  notify-info-slack next
  [[ "$(calls chat.postMessage | grep -c '"username":"Run UAT","icon_emoji":":test_tube:"')" -eq 2 ]]
}
