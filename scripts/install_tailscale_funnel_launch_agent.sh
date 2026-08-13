#!/bin/zsh

set -euo pipefail

TAILSCALED="${TAILSCALED:-/opt/homebrew/opt/tailscale/bin/tailscaled}"
TAILSCALE="${TAILSCALE:-/opt/homebrew/opt/tailscale/bin/tailscale}"
LABEL="com.bodymode.tailscaled"
RUNTIME_DIR="${HOME}/Library/Application Support/BodyMode/tailscale"
SOCKET_PATH="${RUNTIME_DIR}/tailscaled.socket"
STATE_PATH="${RUNTIME_DIR}/tailscaled.state"
PLIST_PATH="${HOME}/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="${HOME}/Library/Logs/BodyMode"
DOMAIN="gui/${UID}"

if [[ ! -x "${TAILSCALED}" || ! -x "${TAILSCALE}" ]]; then
  print -u2 "Install the open-source Tailscale CLI first: brew install tailscale"
  exit 1
fi

mkdir -p "${RUNTIME_DIR}" "${HOME}/Library/LaunchAgents" "${LOG_DIR}"
chmod 700 "${RUNTIME_DIR}"
launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true
rm -f "${PLIST_PATH}"

plutil -create xml1 "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :Label string ${LABEL}" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string ${TAILSCALED}" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:1 string --tun=userspace-networking" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:2 string --state=${STATE_PATH}" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:3 string --socket=${SOCKET_PATH}" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :RunAtLoad bool true" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :KeepAlive bool true" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :ThrottleInterval integer 10" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :StandardOutPath string ${LOG_DIR}/tailscaled.log" "${PLIST_PATH}"
/usr/libexec/PlistBuddy -c "Add :StandardErrorPath string ${LOG_DIR}/tailscaled.error.log" "${PLIST_PATH}"
chmod 600 "${PLIST_PATH}"

launchctl bootstrap "${DOMAIN}" "${PLIST_PATH}"
launchctl kickstart -k "${DOMAIN}/${LABEL}"

print "Installed ${LABEL}"
print "Authenticate: ${TAILSCALE} --socket=${SOCKET_PATH} up"
print "Enable Funnel: ${TAILSCALE} --socket=${SOCKET_PATH} funnel --bg --yes 8765"
