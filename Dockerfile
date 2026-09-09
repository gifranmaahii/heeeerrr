# Hermes + Free Cloud VPS (Ubuntu 22.04 XFCE4 desktop + noVNC) for Railway
# Based on Lyvelia/free-vps-railway, extended with an optional Hermes Agent setup.
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
# 1. Base packages + XFCE4 desktop (same as the original free-vps-railway repo)
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
# 3. Copy the VPS startup script and the optional Hermes autostart script.
#    hermes_setup.sh is a no-op unless the HERMES_AUTOSTART env var is 'true'.
# ---------------------------------------------------------------------------
WORKDIR /root

COPY startup.sh /startup.sh
RUN chmod +x /startup.sh

COPY hermes_setup.sh /opt/hermes_setup.sh
RUN chmod +x /opt/hermes_setup.sh

# Expose the noVNC web port
EXPOSE 6080

CMD ["/startup.sh"]
