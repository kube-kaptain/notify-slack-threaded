#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Copyright (c) 2025-2026 Kaptain contributors (Fred Cooke)
#
# The fields dir documents every ConfigMap and Secret entry the scripts read,
# so layers and other tooling never need to read the scripts. It must agree
# with itself and with the env templates.

FIELDS_DIR="/kd/fields"
TEMPLATES_DIR="/kd/templates"
KEY_PREFIX="slack"
TOKEN_PREFIX="NOTIFY_SLACK_THREADED"

# Print every field as <manifest>/<category>/<key>
fields() {
  (cd "${FIELDS_DIR}" && find . -type f | sed 's|^\./||' | sort)
}

@test "every field sits in a known manifest and category" {
  while IFS= read -r field; do
    [[ "${field}" =~ ^(configmap|secret\.template)/(required|optional|context)/${KEY_PREFIX}[A-Z][A-Za-z]*$ ]] || {
      echo "unexpected field: ${field}"
      return 1
    }
  done < <(fields)
}

@test "every token field holds the canonical token name for its key" {
  while IFS= read -r field; do
    [[ "${field}" == */context/* ]] && continue
    key="${field##*/}"
    name="${key#"${KEY_PREFIX}"}"
    expected="${TOKEN_PREFIX}/$(printf '%s' "${name}" | sed 's/\([a-z0-9]\)\([A-Z]\)/\1_\2/g' | tr '[:lower:]' '[:upper:]')"
    [[ "$(cat "${FIELDS_DIR}/${field}")" == "${expected}" ]] || {
      echo "${field} holds '$(cat "${FIELDS_DIR}/${field}")', expected '${expected}'"
      return 1
    }
  done < <(fields)
}

@test "fields and the env templates list the same entries" {
  for manifest in configmap secret.template; do
    case "${manifest}" in
      configmap) template="${TEMPLATES_DIR}/env-configmap/configmap.yaml" ;;
      secret.template) template="${TEMPLATES_DIR}/env-secret/secret.template.yaml" ;;
    esac
    from_fields=$(fields | grep "^${manifest}/" | sed 's|.*/||' | sort)
    from_template=$(grep -oE "^ *#? *${KEY_PREFIX}[A-Z][A-Za-z]*:" "${template}" | tr -d ' #:' | sort)
    [[ "${from_fields}" == "${from_template}" ]] || {
      echo "${manifest} fields and ${template} differ:"
      diff <(echo "${from_fields}") <(echo "${from_template}") || true
      return 1
    }
  done
}

@test "required entries are live in the templates, optional ones commented out" {
  while IFS= read -r field; do
    key="${field##*/}"
    case "${field}" in
      configmap/*) template="${TEMPLATES_DIR}/env-configmap/configmap.yaml" ;;
      *) template="${TEMPLATES_DIR}/env-secret/secret.template.yaml" ;;
    esac
    case "${field}" in
      */optional/*) grep -qE "^ *# ${key}:" "${template}" || { echo "${key} should be commented out in ${template}"; return 1; } ;;
      *) grep -qE "^ *${key}:" "${template}" || { echo "${key} should be live in ${template}"; return 1; } ;;
    esac
  done < <(fields)
}
