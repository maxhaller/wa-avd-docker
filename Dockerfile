# syntax=docker/dockerfile:1

# Kept for compatibility with the existing web-desktop startup contract.
# Android itself is installed independently at current versions below.
FROM dorowu/ubuntu-desktop-lxde-vnc:focal@sha256:07e51eafb6e0923759105eeb8cfc8f0d19be77a212b19f116313153f1272ff1b

USER root
WORKDIR /app
ENV DEBIAN_FRONTEND=noninteractive

ARG ANDROID_API=36
ARG ANDROID_ARCH=x86_64
ARG ANDROID_IMAGE_FLAVOR=google_apis_playstore
ARG CMDLINE_TOOLS_VERSION=15859902
ARG CMDLINE_TOOLS_SHA256=4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583

ENV HOME=/root \
    ANDROID_HOME=/usr/local/android-sdk \
    ANDROID_SDK_ROOT=/usr/local/android-sdk \
    ANDROID_AVD_HOME=/root/.android/avd \
    AVD_NAME=Pixel6_API36 \
    AVD_DEVICE=pixel_6 \
    ANDROID_SYSTEM_IMAGE=system-images\;android-${ANDROID_API}\;${ANDROID_IMAGE_FLAVOR}\;${ANDROID_ARCH}

ENV PATH="${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/emulator"

RUN rm -f /etc/apt/sources.list.d/google-chrome.list* \
          /etc/apt/sources.list.d/google.list* \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        ffmpeg \
        libasound2 \
        libdbus-1-3 \
        libfontconfig1 \
        libgl1-mesa-dev \
        libglu1-mesa \
        libnss3 \
        libpulse0 \
        libvulkan1 \
        libx11-6 \
        libx11-xcb1 \
        libxcb1 \
        libxcomposite1 \
        libxcursor1 \
        libxdamage1 \
        libxfixes3 \
        libxi6 \
        libxkbcommon0 \
        libxrandr2 \
        libxtst6 \
        mesa-vulkan-drivers \
        openjdk-17-jre-headless \
        unzip \
        wget \
        x11-utils \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p "${ANDROID_HOME}/cmdline-tools" \
    && wget -q \
        "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip" \
        -O /tmp/cmdline-tools.zip \
    && echo "${CMDLINE_TOOLS_SHA256}  /tmp/cmdline-tools.zip" | sha256sum -c - \
    && mkdir -p /tmp/android-cmdline \
    && unzip -q /tmp/cmdline-tools.zip -d /tmp/android-cmdline \
    && mkdir -p "${ANDROID_HOME}/cmdline-tools/latest" \
    && mv /tmp/android-cmdline/cmdline-tools/* "${ANDROID_HOME}/cmdline-tools/latest/" \
    && rm -rf /tmp/cmdline-tools.zip /tmp/android-cmdline

RUN yes | sdkmanager --sdk_root="${ANDROID_HOME}" --licenses >/dev/null || true

RUN sdkmanager --sdk_root="${ANDROID_HOME}" \
        "platform-tools" \
        "emulator" \
        "platforms;android-${ANDROID_API}" \
        "${ANDROID_SYSTEM_IMAGE}"

# The AVD lives in a Docker volume and is created at runtime. This avoids an
# image-layer AVD being hidden by that volume and enables clean versioned AVDs.
RUN mkdir -p "${ANDROID_AVD_HOME}" \
    && java -version \
    && sdkmanager --version

COPY entrypoint.sh /app/entrypoint.sh
COPY android-avd.conf /etc/supervisor/conf.d/android-avd.conf
RUN chmod +x /app/entrypoint.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=5m --retries=3 \
    CMD adb get-state >/dev/null 2>&1 \
        && test "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" \
        || exit 1
