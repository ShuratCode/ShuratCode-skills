#!/usr/bin/env bash

set -u

RUN_DIR="${1:?usage: fr-arch-gate.sh <RUN_DIR>}"
# shellcheck disable=SC1090
. "$RUN_DIR/state.env"

if [ "${ARCH_APPROVED:-0}" = 1 ]; then
  GATE=open; REASON=approved_at_invocation
else
  case "${ARCH_GATE:-}" in
    approved)   GATE=open;   REASON=approved ;;
    not_needed) GATE=open;   REASON=not_needed ;;
    failed)     GATE=open;   REASON=detector_failed ;;
    rejected)   GATE=closed; REASON=rejected ;;
    pending)    GATE=closed; REASON=pending ;;
    *)          GATE=closed; REASON=not_decided ;;
  esac
fi

printf '%s\n' "=== FRESH-REVIEW ARCH GATE ===" \
  "ARCH_GATE: $GATE" \
  "REASON: $REASON" \
  "=== END ==="
