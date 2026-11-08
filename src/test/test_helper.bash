# SPDX-License-Identifier: MIT
# Copyright (c) 2025-2026 Kaptain contributors (Fred Cooke)
#
# Shared setup for the Slack provider tests. Each test gets its own config,
# secret and work dirs, plus a fake curl first on PATH that answers like Slack
# and records what it was asked.
#
# Fake curl records, per call:
#   calls  one line: <method> <JSON body or query pairs>
#   argv   one line: every argument curl was given
#   stdin  whatever came in on stdin, the -K config holding the token
#
# Fake curl behaviour can be steered per test with:
#   FAKE_SCOPES          x-oauth-scopes header for auth.test
#   FAKE_HISTORY_KEY     thread key on a message conversations.history returns
#   FAKE_ERROR_METHOD    method that answers ok:false with FAKE_ERROR

setup() {
  export NOTIFY_CONFIG_BASE="${BATS_TEST_TMPDIR}/config"
  export NOTIFY_SECRETS_BASE="${BATS_TEST_TMPDIR}/secrets"
  export NOTIFY_WORK_BASE="${BATS_TEST_TMPDIR}/work"
  mkdir -p "${NOTIFY_CONFIG_BASE}" "${NOTIFY_SECRETS_BASE}" "${NOTIFY_WORK_BASE}"

  echo "xoxb-test-token" > "${NOTIFY_SECRETS_BASE}/slackBotToken"
  echo "C0DEPLOY" > "${NOTIFY_CONFIG_BASE}/slackChannelId"
  echo "C0ALERT" > "${NOTIFY_CONFIG_BASE}/slackAlertChannelId"
  echo "deploy" > "${NOTIFY_CONFIG_BASE}/slackContext"

  unset NOTIFY_THREAD_KEY FAKE_SCOPES FAKE_HISTORY_KEY FAKE_ERROR_METHOD FAKE_ERROR

  export FAKE_DIR="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash
cat >> "${FAKE_DIR}/stdin"
echo "$*" >> "${FAKE_DIR}/argv"

data=""
headers_file=""
prev=""
for arg in "$@"; do
  case "${prev}" in
    --data-binary) data="${arg}" ;;
    --data-urlencode) data="${data:+${data} }${arg}" ;;
    -D) headers_file="${arg}" ;;
  esac
  prev="${arg}"
done
url="${*: -1}"
method="${url##*/}"
echo "${method} ${data}" >> "${FAKE_DIR}/calls"

if [[ -n "${headers_file}" && "${headers_file}" != /dev/null ]]; then
  printf 'HTTP/2 200\r\nx-oauth-scopes: %s\r\n\r\n' "${FAKE_SCOPES:-chat:write,reactions:write,channels:history,groups:history}" > "${headers_file}"
fi

if [[ "${method}" == "${FAKE_ERROR_METHOD:-}" ]]; then
  echo "{\"ok\":false,\"error\":\"${FAKE_ERROR}\"}"
  exit 0
fi

case "${method}" in
  chat.postMessage) echo '{"ok":true,"channel":"C0DEPLOY","ts":"1700000000.000100"}' ;;
  auth.test) echo '{"ok":true,"user":"run_test","team":"Test"}' ;;
  chat.getPermalink) echo '{"ok":true,"permalink":"https://test.slack.com/archives/C0DEPLOY/p1700000000000100"}' ;;
  conversations.history)
    if [[ -n "${FAKE_HISTORY_KEY:-}" ]]; then
      echo "{\"ok\":true,\"messages\":[{\"ts\":\"1600000000.000200\",\"text\":\"other\"},{\"ts\":\"1600000000.000100\",\"metadata\":{\"event_type\":\"kaptain_notify_thread\",\"event_payload\":{\"thread_key\":\"${FAKE_HISTORY_KEY}\"}}}],\"response_metadata\":{\"next_cursor\":\"\"}}"
    else
      echo '{"ok":true,"messages":[],"response_metadata":{"next_cursor":""}}'
    fi
    ;;
  *) echo '{"ok":true}' ;;
esac
EOF
  chmod 755 "${BATS_TEST_TMPDIR}/bin/curl"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

# Print the recorded calls, or those for one method
calls() {
  if [[ $# -eq 0 ]]; then
    cat "${FAKE_DIR}/calls"
  else
    grep "^$1 " "${FAKE_DIR}/calls" || true
  fi
}

# Print the number of calls to a method
call_count() {
  calls "$1" | wc -l | tr -d ' '
}

# Print the thread state recorded by the first post of the run
thread_ts() {
  cat "${NOTIFY_WORK_BASE}/notify/slack/ts"
}
