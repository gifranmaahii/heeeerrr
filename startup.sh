#!/bin/bash
set -e

# Port configuration (Railway / Render injects PORT dynamically)
PORT=${PORT:-6080}
RESOLUTION=${RESOLUTION:-1280x720x24}
VNC_PASSWORD=${VNC_PASSWORD:-""}

echo "=================================================="
echo " Starting Free VPS (Ubuntu XFCE4 + noVNC)"
echo " Screen Resolution: $RESOLUTION"
echo " Web Port: $PORT"
echo "=================================================="

# Remove old lock files if container restarted
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0

# 1. Start Virtual Framebuffer (Xvfb)
echo "[1/5] Starting Xvfb on display :0 ..."
Xvfb :0 -screen 0 $RESOLUTION -ac +extension GLX +render -noreset &
XVFB_PID=$!
sleep 2

# 2. Start XFCE4 Desktop Session
echo "[2/5] Starting XFCE4 Desktop..."
export DISPLAY=:0
dbus-launch --exit-with-session startxfce4 &
sleep 2

# 3. Start x11vnc Server
echo "[3/5] Starting x11vnc server on port 5900..."
if [ -n "$VNC_PASSWORD" ]; then
    mkdir -p ~/.vnc
    x11vnc -storepasswd "$VNC_PASSWORD" ~/.vnc/passwd
    x11vnc -display :0 -rfbauth ~/.vnc/passwd -forever -shared -rfbport 5900 -bg -o /var/log/x11vnc.log
else
    x11vnc -display :0 -nopw -forever -shared -rfbport 5900 -bg -o /var/log/x11vnc.log
fi
sleep 1

# 4. Start noVNC Websockify
echo "[4/5] Starting noVNC Websockify on 0.0.0.0:$PORT..."
/opt/novnc/utils/novnc_proxy --vnc localhost:5900 --listen 0.0.0.0:$PORT --web /opt/novnc &
NOVNC_PID=$!

# 5. Optional: bootstrap Hermes Agent (installs and launches the Telegram
#    gateway inside this VPS). Only runs when HERMES_AUTOSTART=true.
if [ "$HERMES_AUTOSTART" = "true" ]; then
    echo "[5/5] HERMES_AUTOSTART=true -> launching Hermes bootstrap..."
    nohup /opt/hermes_setup.sh >> /var/log/hermes_setup.log 2>&1 &
    HERMES_PID=$!
    echo "Hermes bootstrap started (pid $HERMES_PID). Logs: /var/log/hermes_setup.log"
else
    echo "[5/5] Hermes autostart disabled (set HERMES_AUTOSTART=true to enable)."
fi

echo "Web VPS is ready to access via browser on port $PORT!"

# Keep the container alive and make sure a restart of the proxy is possible.
while true; do
    if ! kill -0 $NOVNC_PID 2>/dev/null; then
        echo "noVNC proxy exited, restarting..."
        /opt/novnc/utils/novnc_proxy --vnc localhost:5900 --listen 0.0.0.0:$PORT --web /opt/novnc &
        NOVNC_PID=$!
    fi
    sleep 10
done