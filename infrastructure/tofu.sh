#!/usr/bin/env bash
# Unified OpenTofu wrapper for all infrastructure stacks.
#
# Usage: ./tofu.sh <stack> <command> [extra-args]
#   stack:   devbox | talos
#   command: init | plan | apply | destroy | validate | fmt
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_JSON="${SCRIPT_DIR}/infra.json"
STACKS_DIR="${SCRIPT_DIR}/stacks"

STACK="${1:?Usage: $0 <stack> <command> [extra-args]}"
COMMAND="${2:?Usage: $0 <stack> <command> [extra-args]}"
shift 2

if [[ ! -d "${STACKS_DIR}/${STACK}" ]]; then
  echo "Error: Unknown stack '${STACK}'. Available:" >&2
  ls -1 "${STACKS_DIR}" >&2
  exit 1
fi

if [[ ! "$COMMAND" =~ ^(init|plan|apply|destroy|validate|fmt)$ ]]; then
  echo "Error: Unknown command '${COMMAND}'. Must be: init, plan, apply, destroy, validate, fmt" >&2
  exit 1
fi

if [[ "$COMMAND" != "init" && "$COMMAND" != "fmt" && ! -f "${INFRA_JSON}" ]]; then
  echo "Error: ${INFRA_JSON} not found." >&2
  echo "  cp infra.json.example infra.json && edit infra.json" >&2
  exit 1
fi

cd "${STACKS_DIR}/${STACK}"

case "$COMMAND" in
  init)     tofu init "$@" ;;
  fmt)      tofu fmt "$@" ;;
  validate) tofu validate "$@" ;;
  *)        tofu "${COMMAND}" -var-file="${INFRA_JSON}" "$@" ;;
esac
