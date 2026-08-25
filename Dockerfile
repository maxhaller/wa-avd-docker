# syntax=docker/dockerfile:1

FROM dorowu/ubuntu-desktop-lxde-vnc:focal

USER root

WORKDIR /app

ENV DEBIAN_FRONTEND=noninteractive

# Android configuration
ARG ANDROID_API=26
ARG CMDLINE_TOOLS_VERSION=9477386

ENV HOME=/root
ENV ANDROID_HOME=/usr/local/android-sdk
ENV ANDROID_SDK_ROOT=/usr/local/android-sdk
ENV ANDROID_AVD_HOME=/root/.android/avd

ENV PATH="${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/emulator"

# -------------------------------------------------------------------
# System dependencies
# -------------------------------------------------------------------

# dorowu:focal contains an obsolete Google Chrome APT repository.
# We do not need Chrome, so remove that repository before apt-get update.
RUN rm -f /etc/apt/sources.list.d/google-chrome.list* \
          /etc/apt/sources.list.d/google.list* \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        wget \
        unzip \
        ca-certificates \
        openjdk-11-jdk-headless \
        ffmpeg \
        libgl1-mesa-dev \
        libglu1-mesa \
        libvulkan1 \
        mesa-vulkan-drivers \
        libpng16-16 \
        libx11-6 \
        libx11-xcb1 \
        libxcb1 \
        libxcomposite1 \
        libxcursor1 \
        libxi6 \
        libxtst6 \
        libxrandr2 \
        libxkbcommon0 \
        libnss3 \
        libasound2 \
        libpulse0 \
        libfontconfig1 \
        libdbus-1-3 \
        libxdamage1 \
        libxfixes3 \
        x11-utils \
    && rm -rf /var/lib/apt/lists/*

# -------------------------------------------------------------------
# Android command-line tools
# -------------------------------------------------------------------

RUN mkdir -p "${ANDROID_HOME}/cmdline-tools" \
    && wget -q \
        "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip" \
        -O /tmp/cmdline-tools.zip \
    && mkdir -p /tmp/android-cmdline \
    && unzip -q /tmp/cmdline-tools.zip -d /tmp/android-cmdline \
    && mkdir -p "${ANDROID_HOME}/cmdline-tools/latest" \
    && mv /tmp/android-cmdline/cmdline-tools/* \
          "${ANDROID_HOME}/cmdline-tools/latest/" \
    && rm -rf /tmp/cmdline-tools.zip /tmp/android-cmdline

# Check Java + SDK tools during build
RUN java -version \
    && sdkmanager --version

# -------------------------------------------------------------------
# Android SDK, emulator and Android 8/API 26 image
# -------------------------------------------------------------------

RUN yes | sdkmanager --sdk_root="${ANDROID_HOME}" --licenses >/dev/null || true

RUN sdkmanager --sdk_root="${ANDROID_HOME}" \
        "platform-tools" \
        "emulator" \
        "platforms;android-${ANDROID_API}" \
        "system-images;android-${ANDROID_API};google_apis;x86"

# -------------------------------------------------------------------
# Create Android AVD
# -------------------------------------------------------------------

RUN mkdir -p "${ANDROID_AVD_HOME}" \
    && echo no | avdmanager create avd \
        --force \
        --name Pixel \
        --package "system-images;android-${ANDROID_API};google_apis;x86" \
    && echo "hw.keyboard=yes" >> "${ANDROID_AVD_HOME}/Pixel.avd/config.ini" \
    && echo "hw.ramSize=2048" >> "${ANDROID_AVD_HOME}/Pixel.avd/config.ini" \
    && echo "disk.dataPartition.size=4G" >> "${ANDROID_AVD_HOME}/Pixel.avd/config.ini"

# Verify that the AVD exists while building
RUN emulator -list-avds | grep -qx "Pixel"

# -------------------------------------------------------------------
# WhatsApp
# -------------------------------------------------------------------

COPY whatsapp.apk /app/whatsapp.apk

# -------------------------------------------------------------------
# Startup script
# -------------------------------------------------------------------

RUN cat > /app/entrypoint.sh <<'EOF'
#!/bin/bash
set -e

export HOME=/root
export ANDROID_HOME=/usr/local/android-sdk
export ANDROID_SDK_ROOT=/usr/local/android-sdk
export ANDROID_AVD_HOME=/root/.android/avd
export DISPLAY=:1.0
export QTWEBENGINE_DISABLE_SANDBOX=1

export PATH="${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/emulator"

echo "============================================================"
echo " WhatsApp Android VM"
echo "============================================================"

echo "Waiting for X11 display ${DISPLAY}..."

until xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; do
    sleep 1
done

echo "X11 is ready."

xhost +local:root >/dev/null 2>&1 || true

echo
echo "Android emulator version:"
emulator -version | head -n 1 || true

echo
echo "Available AVDs:"
emulator -list-avds

if ! emulator -list-avds | grep -qx "Pixel"; then
    echo "ERROR: Pixel AVD does not exist."
    exit 1
fi

# Remove stale locks after an unclean shutdown
find "${ANDROID_AVD_HOME}/Pixel.avd" \
    -name "*.lock" \
    -type f \
    -delete 2>/dev/null || true

find "${ANDROID_AVD_HOME}/Pixel.avd" \
    -name "*.lock" \
    -type d \
    -exec rm -rf {} + 2>/dev/null || true

# Docker Desktop on Windows normally does not provide /dev/kvm.
# If KVM exists, use it. Otherwise fall back to software emulation.
if [ -e /dev/kvm ]; then
    echo "KVM detected - hardware acceleration enabled."
    ACCEL_ARGS="-accel on"
else
    echo "WARNING: /dev/kvm not available."
    echo "Using software CPU emulation."
    ACCEL_ARGS="-accel off"
fi

echo
echo "Starting Android..."

emulator \
    -avd Pixel \
    ${ACCEL_ARGS} \
    -gpu swiftshader_indirect \
    -no-boot-anim \
    -no-snapshot-save &

EMULATOR_PID=$!

# -------------------------------------------------------------------
# Wait for ADB
# -------------------------------------------------------------------

echo "Waiting for ADB..."

while ! adb get-state >/dev/null 2>&1; do
    if ! kill -0 "${EMULATOR_PID}" 2>/dev/null; then
        echo "ERROR: Android emulator exited before ADB became available."
        wait "${EMULATOR_PID}"
        exit 1
    fi

    sleep 2
done

echo "ADB connected."

# -------------------------------------------------------------------
# Wait for Android boot
# -------------------------------------------------------------------

echo "Waiting for Android to finish booting..."

until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    if ! kill -0 "${EMULATOR_PID}" 2>/dev/null; then
        echo "ERROR: Android emulator exited during startup."
        wait "${EMULATOR_PID}"
        exit 1
    fi

    sleep 2
done

echo "Android boot completed."

# Give Android a few additional seconds to initialize PackageManager
sleep 5

# Unlock screen
adb shell input keyevent 82 >/dev/null 2>&1 || true

# -------------------------------------------------------------------
# Install WhatsApp
# -------------------------------------------------------------------

if [ ! -f /app/whatsapp.apk ]; then
    echo "ERROR: /app/whatsapp.apk does not exist."
    exit 1
fi

if adb shell pm list packages 2>/dev/null | grep -q '^package:com.whatsapp$'; then
    echo "WhatsApp is already installed."

    # Upgrade it with the APK included in the image.
    echo "Checking/installing supplied WhatsApp APK..."

    if ! adb install -r /app/whatsapp.apk; then
        echo "WARNING: WhatsApp APK update failed."
    fi
else
    echo "Installing WhatsApp..."

    if ! adb install -r /app/whatsapp.apk; then
        echo "ERROR: WhatsApp APK installation failed."
        echo
        echo "APK information:"
        ls -lh /app/whatsapp.apk
        exit 1
    fi
fi

echo
echo "Installed WhatsApp package:"
adb shell pm path com.whatsapp || true

# -------------------------------------------------------------------
# Open WhatsApp
# -------------------------------------------------------------------

echo "Launching WhatsApp..."

adb shell monkey \
    -p com.whatsapp \
    -c android.intent.category.LAUNCHER \
    1 >/dev/null 2>&1 || true

echo
echo "============================================================"
echo " Android is running."
echo " WhatsApp is installed and has been launched."
echo " Open the noVNC desktop to interact with it."
echo "============================================================"

wait "${EMULATOR_PID}"
EOF

RUN chmod +x /app/entrypoint.sh

# -------------------------------------------------------------------
# Start
# -------------------------------------------------------------------

CMD ["/app/entrypoint.sh"]
