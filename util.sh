#!/usr/bin/env bash
# Shared demo harness. Pattern originated in Christian Posta's
# scripted-solo-demos, adapted via platformfix/k8s-ai-demo.

TYPE_SPEED=25
if [ "${DEMO_RUN_FAST:-0}" = "1" ]; then
  TYPE_SPEED=1000
fi

desc() {
  echo
  echo "# $*"
}

run() {
  local cmd="$*"
  printf '%s' "$cmd" | pv -qL "$TYPE_SPEED"
  echo
  if [ "${DEMO_AUTO_RUN:-0}" != "1" ]; then
    read -rsn1 -p "[press any key to run]"
    echo
  fi
  eval "$cmd"
}

# Flags loudly only if the command unexpectedly succeeds - used for the one
# step that's supposed to fail (proving the 503-without-parking baseline is
# real).
run_expect_fail() {
  local cmd="$*"
  if run "$cmd"; then
    echo "!! Expected '$cmd' to fail, but it succeeded. !!"
    return 1
  fi
  return 0
}

pause_for_presenter() {
  if [ "${DEMO_AUTO_RUN:-0}" != "1" ]; then
    read -rsn1 -p "$1"
    echo
  fi
}
