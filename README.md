# WhatsApp Android AVD in Docker

This project runs a current Android virtual device in a browser-accessible Linux desktop. It is intended for manual Android/WhatsApp use, not messaging automation.

The current configuration uses:

- Android 16 / API 36
- a 64-bit x86_64 Pixel 6 profile
- Google's `google_apis_playstore` system image
- a release-signed, non-root Android system with Google Play Store
- persistent Android user data in a versioned Docker volume
- noVNC bound only to the host loopback interface
- generated credentials and a non-root desktop account

## Important limitation

An Android Virtual Device is still an emulator. Properties such as `ro.kernel.qemu=1` are expected and are not hidden by this project. A current Google Play image is substantially closer to a consumer Android installation than the old Android 8 `userdebug/dev-keys` image, but it does not make the VM equivalent to certified physical hardware and cannot guarantee that WhatsApp will accept registration.

This project deliberately does not spoof a device fingerprint, hide QEMU, root Android, patch WhatsApp, or bypass Play Integrity. Those changes would make the installation less trustworthy and could result in another account restriction.

## Requirements

- Docker Engine with the Compose plugin, or Docker Desktop using Linux containers
- working KVM access at `/dev/kvm`
- approximately 15 GB of free disk space for the image and AVD
- preferably 8 GB or more of free RAM
- a Google account if installing through Google Play
- access to the phone number's SMS or voice verification

The Compose configuration passes only `/dev/kvm` into the container, providing hardware acceleration without granting privileged container access. The service will not start when the host has no `/dev/kvm`; software emulation is not practical for this Android 16 configuration.

On Linux, verify acceleration before starting:

```bash
kvm-ok
```

The expected result is `KVM acceleration can be used`.

## Clone and configure

Clone the repository:

```bash
git clone https://github.com/maxhaller/wa-avd-docker.git
cd wa-avd-docker
```

Generate a non-root desktop username and random local credentials. The default username is `avd`; pass a different lowercase username as the first argument if desired:

```bash
./configure.sh
# or: ./configure.sh operator
```

On Windows PowerShell:

```powershell
./configure.ps1
# or: ./configure.ps1 operator
```

The Linux generator creates a mode-restricted `.env` file, and both generators refuse to overwrite an existing file. No default password exists, and Compose refuses to start if any required credential is missing. `.env`, private keys, APKs, Android data, logs, and local tooling files are excluded from Git; Docker also receives only the three files required to build the image.

To see the browser username and password locally:

```bash
grep -E '^(DESKTOP_USER|HTTP_PASSWORD)=' .env
```

Never commit or share `.env`.

## Start the new Android 16 device

From CMD in this directory:

```cmd
wa-avd up
wa-avd logs
```

From PowerShell:

```powershell
./wa-avd.ps1 up
./wa-avd.ps1 logs
```

Wait for `Android is ready`, then open [http://localhost:6080](http://localhost:6080). Sign in to Google Play and install WhatsApp from its official store page.

The browser endpoint listens only on `127.0.0.1`. The direct VNC port is not published. On a remote server, keep port 6080 closed in both the host and cloud firewalls and create an SSH tunnel from your computer:

```powershell
ssh -N -L 6080:127.0.0.1:6080 YOUR_SSH_USER@YOUR_SERVER_IP
```

Then open [http://localhost:6080](http://localhost:6080) locally. Only SSH should be exposed publicly, preferably restricted to your source IP and authenticated with an SSH key.

## DigitalOcean deployment

Use an Ubuntu 24.04 Droplet with at least 4 vCPUs and 8 GB RAM. Confirm `kvm-ok` succeeds before installing the project. Install Docker Engine and the Compose plugin from Docker's official Ubuntu repository, then run:

```bash
install -d -m 0755 /opt/wa-avd
git clone https://github.com/maxhaller/wa-avd-docker.git /opt/wa-avd
cd /opt/wa-avd
./configure.sh
docker compose up --build --detach
docker compose logs --follow vm
```

Apply a DigitalOcean Cloud Firewall that permits inbound TCP 22 only from your IP. Do not add rules for 6080, 5900, or ADB. Enable monitoring and backups, and remember that the persistent Android state is stored in the Docker volume `wa-avd-docker_android_api36`.

## Migration from the old Android 8 AVD

The new Compose configuration uses the volume `wa-avd-docker_android_api36`. It persists both the AVD and its ADB authorization keys. The previous `wa-avd-docker_avd` volume is left untouched, so this upgrade does not destroy the old Android 8 installation.

Android user data cannot be upgraded safely from API 26/x86 to API 36/x86_64. The Android 16 AVD therefore starts clean. Do not copy WhatsApp's private app data between these devices.

After confirming that the new AVD works and that nothing from the old device is needed, the old volume can be removed manually. Its removal is intentionally not automated.

## Quick actions

Run `wa-avd help` for the full list.

| Command | Purpose |
| --- | --- |
| `wa-avd up` | Build and start the VM |
| `wa-avd refresh` | Re-download the latest revisions of the configured SDK and Android image |
| `wa-avd logs` | Follow Android startup output |
| `wa-avd status` | Show container, Android, Play Store, and WhatsApp status |
| `wa-avd setup` | Launch WhatsApp, or open its Play Store page when absent |
| `wa-avd play-store` | Open the official WhatsApp page in Google Play |
| `wa-avd launch` | Launch an installed WhatsApp app |
| `wa-avd wait` | Wait for Android to finish booting |
| `wa-avd shell` | Open a container shell |
| `wa-avd down` | Stop and remove the VM container; user data remains |

## Optional APK sideloading

Google Play is the recommended installation source. If Play is unavailable, download an untouched APK directly from [WhatsApp](https://www.whatsapp.com/android), save it outside Git, and pass its path explicitly:

```powershell
./wa-avd.ps1 install C:\path\to\whatsapp.apk
```

Or from CMD:

```cmd
wa-avd install C:\path\to\whatsapp.apk
```

For compatibility with the earlier workflow, an APK named `whatsapp.apk` in the repository root is still ignored by Git and is used when no path is supplied. The APK is no longer copied into the Docker image or automatically installed at every boot.

An APK that merely has the package name `com.whatsapp` is not necessarily official. Do not use repackaged, patched, cloned, or third-party WhatsApp APKs.

## Updating later

Use:

```cmd
wa-avd refresh
```

This rebuilds without Docker's package cache and downloads current revisions of the Android emulator, platform tools, and Android 16 Play Store image. Normal `wa-avd up` builds reuse cached SDK layers for faster startup.

Android system-image updates apply to newly created AVD data. If a future Android API upgrade is made in this repository, use another versioned AVD name and volume rather than modifying the existing device in place.

## Diagnostics

```cmd
docker compose exec vm adb shell getprop ro.product.model
docker compose exec vm adb shell getprop ro.build.fingerprint
docker compose exec vm adb shell getprop ro.build.version.release
docker compose exec vm adb shell getprop ro.build.version.sdk
docker compose exec vm adb shell pm list packages com.android.vending
docker compose exec vm adb shell dumpsys package com.whatsapp | findstr version
```

`ro.kernel.qemu=1` remains expected. Changing it would only conceal the environment; it would not turn the AVD into a real phone.

## Security and account safety

- Browser access requires a generated non-root username and random HTTP password.
- The Linux desktop password and internal VNC password are separate generated values.
- noVNC is loopback-only, direct VNC and ADB are not published, and remote access uses an SSH tunnel.
- The container is not privileged, receives only `/dev/kvm`, and prevents processes from gaining additional privileges.
- Docker logs are size-limited to prevent unbounded host-disk growth.
- Use WhatsApp manually and avoid bulk messaging, scraping, or repeated group operations.
- Resolve an account ban through the official in-app review before trying to register again.
- Do not reconnect unofficial bridge clients immediately after an account is restored.
- No emulator configuration can guarantee acceptance by WhatsApp or prevent account enforcement.

## Acknowledgements

- [Android Emulator documentation](https://developer.android.com/studio/run/emulator)
- [fcwu/docker-ubuntu-vnc-desktop](https://github.com/fcwu/docker-ubuntu-vnc-desktop)
- [Original open-wa/wa-avd-docker project](https://github.com/open-wa/wa-avd-docker)
