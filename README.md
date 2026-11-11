# Notify Slack Threaded

The Slack notify plugin for Kaptain Deploy and Kaptain Build.

Each deploy from a particular environment version posts into the same thread in
a Slack channel. The thread is identified by the value of `NOTIFY_THREAD_KEY`
which is the version appended to the name and stored in metadata of the first
post of each thread for later relookup. That means that a restarted deploy of
the same version carries on where it left off instead of spamming the channel
with a new thread. Only failures are also posted to the channel itself and DMed
to the people listed. The thread's first post gets a ⚠️  for warnings and a ✅
for success and a ❌ for failure. Alerts go to a channel of their own with an
`@here`, and are DMed to the people listed for alerts.


## Slack Setup

`templates/slack-app/` holds two Slack app manifests:

| Manifest                       | Posts as                                                         |
|--------------------------------|------------------------------------------------------------------|
| `run-replaceme.yaml`           | The app's own name and icon, one app per environment             |
| `run-replaceme-customize.yaml` | Any name and icon set per message, one app for many environments |

1. At https://api.slack.com/apps choose **Create New App**, then **From a
   manifest**, and paste one in, with `Replaceme` changed to your environment.
2. Under **Install App**, install it and copy the **Bot User OAuth Token**,
   which looks like `xoxb-10791099618-12524441365685-I0bgtihTbEOViTPJScfJ0tDi`.
3. `/invite` the app to the deploy channel and the alert channel, and note each
   channel's ID (`C0...`) from its **About** tab.
4. For DMs, note each person's member ID (`U0...`) from their profile, **⋮**
   then **Copy member ID**.


## Configuration

### Environment

| Variable              | Purpose                                         |
|-----------------------|-------------------------------------------------|
| `NOTIFY_CONFIG_BASE`  | Directory of config entries, one file per entry |
| `NOTIFY_SECRETS_BASE` | Directory of secret entries, one file per entry |
| `NOTIFY_WORK_BASE`    | Writable directory for per-run state            |
| `NOTIFY_THREAD_KEY`   | Optional, runs with the same key share a thread |

The Kaptain deploy base images set the first three. The `deploy` script entry
point sets `NOTIFY_THREAD_KEY` to `<environment>-<version>`.

### Secret

| Entry                       | Purpose                                    |
|-----------------------------|--------------------------------------------|
| `slackAppBotUserOAuthToken` | The app's Bot User OAuth Token, `xoxb-...` |

### Required Config

| Entry                 | Purpose                                                  |
|-----------------------|----------------------------------------------------------|
| `slackContext`        | `deploy` or `build`, picks the default DM wording        |
| `slackChannelId`      | Deploy thread channel, `C0...`                           |
| `slackAlertChannelId` | Alert channel, `C0...`, separate from the deploy channel |

### Optional Config

Absent gives the default, present but empty turns it off, anything else
replaces it.

| Entry                                             | Default                                                                          |
|---------------------------------------------------|----------------------------------------------------------------------------------|
| `slackFailureUserIds`                             | none, user IDs to DM on failure, comma and/or space separated                    |
| `slackAlertUserIds`                               | none, user IDs to DM on alert                                                    |
| `slackRequired`                                   | `false`, `true` makes validation failures stop the deploy                        |
| `slackUsername`, `slackIconEmoji`, `slackIconUrl` | the app's own, setting any needs `chat:write.customize`                          |
| `slackThreadLookbackDays`                         | `30`, history searched to rejoin a thread                                        |
| `slackAlertMention`                               | `<!here>`                                                                        |
| `slackInfoPrefix`                                 | none                                                                             |
| `slackWarningPrefix`                              | `:warning:`                                                                      |
| `slackErrorPrefix`                                | `:rotating_light:`                                                               |
| `slackSuccessPrefix`                              | `:white_check_mark:`                                                             |
| `slackFailurePrefix`                              | `:x:`                                                                            |
| `slackAlertPrefix`                                | `:rotating_light:`                                                               |
| `slackWarningReaction`                            | `warning`                                                                        |
| `slackSuccessReaction`                            | `white_check_mark`                                                               |
| `slackFailureReaction`                            | `x`                                                                              |
| `slackFailureDmLeader`, `slackAlertDmLeader`      | a sentence per `slackContext`                                                    |
| `slackFailureLinkLabel`, `slackAlertLinkLabel`    | a label per `slackContext`, such as `Deployment {ENVIRONMENT}:{VERSION} thread:` |
| `slackCurlRetry`                                  | `3`                                                                              |
| `slackCurlRetryDelay`                             | `2`                                                                              |
| `slackCurlConnectTimeout`                         | `10`                                                                             |
| `slackCurlMaxTime`                                | `20`                                                                             |
| `slackCurlRetryMaxTime`                           | `70`                                                                             |

In the DM leaders and link labels, `{user}` mentions the person and `{ENV_VAR}`
inserts that variable's value. An unset variable is left as written so the
mistake shows.

The curl defaults favour every message arriving, in order, over speed.

See [MessageFormatting.md](MessageFormatting.md) for the markup Slack renders
in messages, prefixes, the alert mention and the DM wording.

Every entry is listed in `src/fields/` with its canonical token name, and every
default in `src/defaults/`, shipped as the image's `/fields` and the
`notify-slack-threaded-fields.zip` release file.


## Messages

| Command                       | In Slack                                                           |
|-------------------------------|--------------------------------------------------------------------|
| `notify-info`, `notify-error` | A reply in the thread, the first message of a run opens it         |
| `notify-warning`              | A reply, and a ⚠️  on the thread's first post                       |
| `notify-success`              | A reply, and a ✅ on the thread's first post                       |
| `notify-failure`              | A reply also shown in the channel, a ❌ on the first post, and DMs |
| `alert`                       | A post of its own in the alert channel, and DMs                    |

`validate-notify-slack` checks the configuration against what the token can
do. `validate-tooling-slack` checks `curl` and `yq` are present.


## Use

### Kaptain Deploy

Add [layer-notify-slack-threaded](https://github.com/kube-kaptain/layer-notify-slack-threaded)
to your environment project KaptainPM.yaml. It puts the scripts in the deploy
image and the entries in the environment's ConfigMap and Secret, as tokens for
your run-platform to supply.

To build the plugin into your own image instead, copy the scripts in beside the
deploy scripts:

```dockerfile
COPY --from=ghcr.io/kube-kaptain/notify/notify-slack-threaded:<version> /scripts /kd/bin
```

Then supply your own ConfigMap and Secret, starting from
`templates/env-configmap/` or a subset thereof and `templates/env-secret/`.

<todo ### Kaptain Build>

<todo some setting in early build that pulls in and wires up to logging system>
