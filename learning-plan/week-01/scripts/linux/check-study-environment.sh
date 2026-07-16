#!/usr/bin/env bash
set -u

failures=0

check_command() {
  local command_name="$1"
  if command -v "${command_name}" >/dev/null 2>&1; then
    echo "[PASS] ${command_name}: $(command -v "${command_name}")"
  else
    echo "[FAIL] ${command_name}: not found"
    failures=$((failures + 1))
  fi
}

check_command git
check_command java
check_command javac
check_command curl
check_command ssh

if command -v java >/dev/null 2>&1; then
  java_line="$(java -version 2>&1 | head -n 1)"
  echo "[INFO] ${java_line}"
  if [[ ! "${java_line}" =~ version\ \"11[\.] ]]; then
    echo "[FAIL] Expected Java 11"
    failures=$((failures + 1))
  fi
fi

echo "[INFO] host=$(hostname -f 2>/dev/null || hostname) ip=$(hostname -I 2>/dev/null || true)"
echo "[INFO] time=$(date --iso-8601=seconds)"

if command -v ss >/dev/null 2>&1 && ss -lnt | awk '{print $4}' | grep -Eq '(^|:)6000$'; then
  echo "[FAIL] TCP port 6000 is already in use"
  failures=$((failures + 1))
else
  echo "[PASS] TCP port 6000 is available"
fi

if [[ ${failures} -ne 0 ]]; then
  echo "Environment check failed: ${failures} issue(s)." >&2
  exit 1
fi

echo "Environment check passed."

