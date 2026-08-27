#!/bin/bash
set -Eeuo pipefail

export HOME="${HOME:-/root}"
export ANDROID_HOME="${ANDROID_HOME:-/usr/local/android-sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME}}"
export ANDROID_AVD_HOME="${ANDROID_AVD_HOME:-${HOME}/.android/avd}"
export AVD_NAME="${AVD_NAME:-Pixel6_API36}"
export AVD_DEVICE="${AVD_DEVICE:-pixel_6}"
export ANDROID_SYSTEM_IMAGE="${ANDROID_SYSTEM_IMAGE:-system-images;android-36;google_apis_playstore;x86_64}"
export DISPLAY="${DISPLAY:-:1.0}"
export QTWEBENGINE_DISABLE_SANDBOX=1
export PATH="${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/emulator"

log() {
    printf '[wa-avd] %s\n' "$*"
}

cleanup() {
    if [ -n "${EMULATOR_PID:-}" ] && kill -0 "${EMULATOR_PID}" 2>/dev/null; then
        kill "${EMULATOR_PID}" 2>/dev/null || true
        wait "${EMULATOR_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

log "Waiting for the VNC desktop display ${DISPLAY}"
until xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; do
    sleep 1
done

mkdir -p "${ANDROID_AVD_HOME}"

host_cpu_count="$(nproc)"
host_memory_mb="$(awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo)"

if (( host_cpu_count < 2 || host_memory_mb < 3500 )); then
    log "At least 2 host CPUs and 3.5 GB host RAM are required"
    log "Detected ${host_cpu_count} CPUs and ${host_memory_mb} MB RAM"
    exit 1
fi

if (( host_cpu_count >= 4 )); then
    default_avd_cpu_cores=4
else
    default_avd_cpu_cores=2
fi

if (( host_memory_mb >= 7168 )); then
    default_avd_ram_mb=4096
else
    # Leave roughly half of a 4 GB host available for Linux, the desktop,
    # Docker, and the emulator's SwiftShader graphics process.
    default_avd_ram_mb=2048
fi

avd_cpu_cores="${AVD_CPU_CORES:-${default_avd_cpu_cores}}"
avd_ram_mb="${AVD_RAM_MB:-${default_avd_ram_mb}}"

if [[ ! "${avd_cpu_cores}" =~ ^[1-9][0-9]*$ ]] || (( avd_cpu_cores > host_cpu_count )); then
    log "AVD_CPU_CORES must be a positive integer no greater than the ${host_cpu_count} host CPUs"
    exit 1
fi

max_avd_ram_mb=$((host_memory_mb - 1536))
if [[ ! "${avd_ram_mb}" =~ ^[1-9][0-9]*$ ]] \
    || (( avd_ram_mb < 1536 || avd_ram_mb > max_avd_ram_mb )); then
    log "AVD_RAM_MB must be between 1536 and ${max_avd_ram_mb} on this host"
    exit 1
fi

log "Host resources: ${host_cpu_count} CPUs, ${host_memory_mb} MB RAM"
log "Android resources: ${avd_cpu_cores} CPUs, ${avd_ram_mb} MB RAM"

if ! emulator -list-avds | grep -Fxq "${AVD_NAME}"; then
    log "Creating ${AVD_NAME} from ${ANDROID_SYSTEM_IMAGE}"
    echo no | avdmanager create avd \
        --force \
        --name "${AVD_NAME}" \
        --package "${ANDROID_SYSTEM_IMAGE}" \
        --device "${AVD_DEVICE}"
fi

avd_config="${ANDROID_AVD_HOME}/${AVD_NAME}.avd/config.ini"
set_avd_config() {
    local key="$1"
    local value="$2"
    local escaped_key="${key//./\\.}"

    sed -i "/^${escaped_key}=.*/d" "${avd_config}"
    printf '%s=%s\n' "${key}" "${value}" >> "${avd_config}"
}

set_avd_config hw.keyboard yes
set_avd_config hw.ramSize "${avd_ram_mb}"
set_avd_config hw.cpu.ncore "${avd_cpu_cores}"
set_avd_config disk.dataPartition.size 8G
set_avd_config showDeviceFrame no

# Locks can remain after Docker Desktop or Windows terminates the container.
find "${ANDROID_AVD_HOME}/${AVD_NAME}.avd" -name '*.lock' -type f -delete 2>/dev/null || true
find "${ANDROID_AVD_HOME}/${AVD_NAME}.avd" -name '*.lock' -type d -exec rm -rf {} + 2>/dev/null || true

if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    log "KVM detected; hardware acceleration enabled"
    accel_args=(-accel on)
else
    log "KVM is unavailable; using slower software CPU emulation"
    accel_args=(-accel off)
fi

log "Starting Android emulator $(emulator -version | head -n 1)"
emulator \
    -avd "${AVD_NAME}" \
    "${accel_args[@]}" \
    -gpu swiftshader_indirect \
    -no-boot-anim \
    -no-metrics \
    -no-snapshot-save &
EMULATOR_PID=$!

log "Waiting for ADB"
until adb get-state >/dev/null 2>&1; do
    if ! kill -0 "${EMULATOR_PID}" 2>/dev/null; then
        log "Android emulator exited before ADB became available"
        wait "${EMULATOR_PID}"
        exit 1
    fi
    sleep 2
done

log "Waiting for Android to finish booting"
until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    if ! kill -0 "${EMULATOR_PID}" 2>/dev/null; then
        log "Android emulator exited during startup"
        wait "${EMULATOR_PID}"
        exit 1
    fi
    sleep 2
done

sleep 5
adb shell input keyevent 82 >/dev/null 2>&1 || true

if adb shell pm list packages 2>/dev/null | grep -Fxq 'package:com.whatsapp'; then
    log "WhatsApp is installed; launching it"
    adb shell monkey \
        -p com.whatsapp \
        -c android.intent.category.LAUNCHER \
        1 >/dev/null 2>&1 || true
else
    log "WhatsApp is not installed"
    log "Open http://localhost:6080 and install it from Google Play"
    adb shell monkey \
        -p com.android.vending \
        -c android.intent.category.LAUNCHER \
        1 >/dev/null 2>&1 || true
fi

log "Android is ready at http://localhost:6080"
wait "${EMULATOR_PID}"
