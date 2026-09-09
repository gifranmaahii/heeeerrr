# ===========================================================================
# Hermes (Nous Research) + Free Cloud VPS (Ubuntu XFCE4 + noVNC) + 9Router
# Target deploy: Railway (free trial) — Hermes talks to 9Router over the
# Railway private network, and you manage the 9Router dashboard from the
# noVNC desktop inside this same container.
#
# Context:
#   - Hermes  : AI agent by Nous Research (Telegram gateway runs in the VPS)
#   - 9Router : runs as a SEPARATE compose service (service name "9router"),
#               reachable from here at http://9router:20128  (private network)
#               and from the desktop browser at http://localhost:20128
# ===========================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV DISPLAY=:0
ENV RESOLUTION=1280x720x24
ENV VNC_PORT=5900
ENV PORT=6080

# ---------------------------------------------------------------------------
# 1. Base packages + XFCE4 desktop (same as Lyvelia/free-vps-railway).
#    'curl' is required for the Hermes one-line installer (used later by
#    hermes_setup.sh). Everything else is already needed for the desktop.
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    sudo \
    bash \
    net-tools \
    procps \
    htop \
    neofetch \
    python3 \
    python3-pip \
    python3-venv \
    xvfb \
    x11vnc \
    xfce4 \
    xfce4-terminal \
    dbus-x11 \
    xauth \
    xterm \
    zip \
    unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 2. noVNC + websockify (in-browser remote desktop access)
# ---------------------------------------------------------------------------
RUN git clone https://github.com/novnc/noVNC.git /opt/novnc \
    && git clone https://github.com/novnc/websockify /opt/novnc/utils/websockify \
    && cp /opt/novnc/vnc.html /opt/novnc/index.html

# ---------------------------------------------------------------------------
# 3. Startup + Hermes setup scripts.
#    - startup.sh      always runs: Xvfb + XFCE + x11vnc + noVNC
#    - hermes_setup.sh runs ONLY when HERMES_AUTOSTART=true
# ---------------------------------------------------------------------------
WORKDIR /root

COPY startup.sh /startup.sh
RUN chmod +x /startup.sh

COPY hermes_setup.sh /opt/hermes_setup.sh
RUN chmod +x /opt/hermes_setup.sh

# Expose the noVNC web port (Railway overrides $PORT at runtime)
EXPOSE 6080

CMD ["/startup.sh"]

