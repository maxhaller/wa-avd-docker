# Docker Android AVD with WhatsApp

This project runs an Android 8 (API 26) virtual device with WhatsApp in an Ubuntu desktop container. The desktop is available through VNC and noVNC.

The image now uses Ubuntu 20.04, Android's command-line tools, OpenJDK 11, and software emulation when `/dev/kvm` is unavailable (the normal case with Docker Desktop on Windows).

## Prerequisites

- Docker Desktop, running Linux containers
- A compatible WhatsApp APK supplied separately

## Add the WhatsApp APK

The APK is intentionally not stored in Git. Before building, place your APK in the repository root with this exact name:

```text
wa-avd-docker/
└── whatsapp.apk
```

The resulting path must be `wa-avd-docker/whatsapp.apk`, next to `Dockerfile` and `docker-compose.yaml`. The Docker build copies that file to `/app/whatsapp.apk` inside the image. If the file is absent or has a different name, the build will fail at the `COPY whatsapp.apk` step.

## Quick start on Windows

From CMD in the project directory:

```cmd
wa-avd up
wa-avd logs
```

From PowerShell, use `./wa-avd.ps1 up` and `./wa-avd.ps1 logs` instead.

Wait until the log says Android has booted and WhatsApp has launched, then open [http://localhost:6080](http://localhost:6080).

- Default username: `root`
- Default password: `secret`

The first build downloads the Android SDK and system image. Startup can also take several minutes because Docker Desktop usually has to use software CPU emulation.

## Quick actions

Run `wa-avd help` for the full list. The most useful actions are:

| Command | Purpose |
| --- | --- |
| `wa-avd up` | Build and start the VM in the background |
| `wa-avd logs` | Follow the startup output |
| `wa-avd status` | Show the container, ADB, Android boot, and WhatsApp status |
| `wa-avd setup` | Wait for Android, install/update WhatsApp, and launch it |
| `wa-avd launch` | Launch WhatsApp if it is already installed |
| `wa-avd reset` | Clear all WhatsApp data and start with the existing APK |
| `wa-avd reinstall` | Uninstall WhatsApp, reinstall the bundled APK, and launch it |
| `wa-avd shell` | Open a shell inside the VM container |
| `wa-avd down` | Stop and remove the VM container |

PowerShell users can also call the script directly, for example `./wa-avd.ps1 status`.

## Manual ADB commands

The helper commands above wrap these commands, which are useful when diagnosing a problem.

Check whether the emulator is connected:

```cmd
docker compose exec vm adb devices
```

Check whether Android has finished booting (the expected result is `1`):

```cmd
docker compose exec vm adb shell getprop sys.boot_completed
```

Install or update the bundled APK and launch WhatsApp:

```cmd
docker compose exec vm adb install -r /app/whatsapp.apk
docker compose exec vm adb shell monkey -p com.whatsapp -c android.intent.category.LAUNCHER 1
```

Clear WhatsApp data without reinstalling it:

```cmd
docker compose exec vm adb shell pm clear com.whatsapp
```

Completely uninstall and reinstall WhatsApp:

```cmd
docker compose exec vm adb uninstall com.whatsapp
docker compose exec vm adb install /app/whatsapp.apk
docker compose exec vm adb shell monkey -p com.whatsapp -c android.intent.category.LAUNCHER 1
```

## Troubleshooting startup

Follow the normal startup output first:

```cmd
wa-avd logs
```

If the automatic emulator has stopped, run the complete entrypoint or the emulator itself in the foreground:

```cmd
wa-avd entrypoint-debug
wa-avd emulator-debug
```

Only run one emulator instance at a time. `emulator-debug` uses software acceleration, SwiftShader graphics, and verbose logging so the actual emulator error remains visible.

## Data and rebuilding

The Android AVD is kept in the Docker volume `avd`; container recreation does not normally erase it. `wa-avd reset` only clears WhatsApp's application data. To remove the AVD itself, explicitly remove the Docker volume after stopping the project.

The bundled `whatsapp.apk` is copied into the image during the build. After replacing it, run `wa-avd up` so Docker rebuilds the image, or use `wa-avd install` when the updated APK is already present at `/app/whatsapp.apk` in the running container.

## Further development

The repository also contains the original experimental camera scripts for feeding a VNC desktop through `v4l2loopback` to the Android AVD.

For Matrix bridging details, see the [mautrix-whatsapp documentation](https://docs.mau.fi/bridges/go/whatsapp/).

## Acknowledgements

- [tracer0tong/android-emulator](https://github.com/tracer0tong/android-emulator)
- [fcwu/docker-ubuntu-vnc-desktop](https://github.com/fcwu/docker-ubuntu-vnc-desktop)
- [butomo1989/docker-android](https://github.com/butomo1989/docker-android)
