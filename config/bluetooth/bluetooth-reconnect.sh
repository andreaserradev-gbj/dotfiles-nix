# Reconnect trusted Bluetooth audio devices at login. Runs as the
# bluetooth-reconnect user unit (modules/nixos/desktop.nix).
#
# End state this run guarantees: every trusted audio device connected, with
# its A2DP transport negotiated against THIS session's PipeWire.

# The session's PipeWire registers its A2DP endpoints with bluetoothd a moment
# AFTER graphical-session.target is reached (observed ~1 s). A connect landing
# in that window negotiates no audio, and devices that auto-stream then drop
# themselves. Only this session can register endpoints, so their presence is
# the readiness signal; if the audio stack never comes up, fall through and
# try anyway rather than hang.
for _ in $(seq 1 15); do
  if busctl call org.bluez / org.freedesktop.DBus.ObjectManager \
      GetManagedObjects 2>/dev/null | grep -q MediaEndpoint; then
    break
  fi
  sleep 2
done

# A link that predates this session (established at the login screen) is
# indistinguishable from a healthy one over bluetoothctl, but its A2DP
# transport binds to the greeter's PipeWire, which dies at login: the device
# looks connected, streams nothing, and drops later on its own. Only audio
# devices bind to session endpoints, so only they are forced through one
# clean cycle; HID links (keyboards, mice) are session-independent and must
# not be interrupted. `handled` marks devices this run reconnected, so the
# verification passes of later attempts don't cycle a link we just made.
handled=" "
for attempt in 1 2 3; do
  pending=0
  # A wedged bluetoothd makes these calls block indefinitely, and a killed
  # call must look PENDING (retry), never like "nothing to do": an empty
  # device list or an unreadable device would otherwise turn the whole run
  # into a silent no-op.
  devs="$(timeout -k 5 10 bluetoothctl devices Paired)" || {
    echo "attempt $attempt: devices query failed"
    pending=1
    sleep 5
    continue
  }
  macs="$(echo "$devs" | cut -d ' ' -f 2)"
  for mac in $macs; do
    rc=0
    info="$(timeout -k 5 10 bluetoothctl info "$mac" 2>&1)" || rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "attempt $attempt: info $mac failed (rc=$rc)"
      pending=1
      continue
    fi
    echo "$info" | grep -q 'Trusted: yes' || continue
    if echo "$info" | grep -q 'Connected: yes'; then
      if ! echo "$info" | grep -qE 'UUID: Audio (Sink|Source)'; then
        continue
      fi
      case "$handled" in
        *" $mac "*) continue ;;
      esac
      echo "attempt $attempt: cycling pre-session link $mac"
      timeout -k 5 10 bluetoothctl disconnect "$mac" 2>&1 || true
    fi
    handled="$handled$mac "
    pending=1
    echo "attempt $attempt: connecting $mac"
    timeout -k 5 20 bluetoothctl connect "$mac" 2>&1 || true
  done
  [ "$pending" -eq 0 ] && exit 0
  sleep 5
done
exit 0
