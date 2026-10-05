#!/usr/bin/env bash

set -uo pipefail

for pass in U I B A K W F R X; do
  case "$pass" in
    U|I|B) model=opus ;;
    A|K|W|F) model=sonnet ;;
    X) model=haiku ;;
    R) model=inherit ;;
  esac
  override="FR_MODEL_$pass"
  case "${!override:-}" in
    opus|sonnet|haiku|fable|inherit) model="${!override}" ;;
    "") ;;
    *) echo "fr-models: ignoring $override=${!override}" >&2 ;;
  esac
  printf '%s=%s\n' "$pass" "$model"
done
