#!/bin/sh
# c-airplayd-boot.sh — started by the LaunchDaemon at boot. Waits for SpringBoard to
# come up, then launches airplayd (which self-backgrounds via the .apd-boot marker so
# the AirPlay receiver is discoverable after a reboot without the user opening the app).

# Wait for SpringBoard (the UI session) to be running — uiopen needs it.
i=0
while [ $i -lt 60 ]; do
    if /usr/bin/killall -0 SpringBoard 2>/dev/null; then break; fi
    sleep 2
    i=$((i + 1))
done
# A little extra settle time after SpringBoard appears.
sleep 5

# Marker tells the app it was boot-launched → background itself once the server is up.
touch /var/mobile/.apd-boot
chown mobile:mobile /var/mobile/.apd-boot 2>/dev/null || true

/usr/bin/uiopen -b com.wawtor.airplayd 2>/dev/null || true
exit 0
