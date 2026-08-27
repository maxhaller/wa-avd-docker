[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet(
        "up",
        "refresh",
        "down",
        "logs",
        "status",
        "wait",
        "setup",
        "install",
        "play-store",
        "launch",
        "reset",
        "reinstall",
        "shell",
        "entrypoint-debug",
        "emulator-debug",
        "help"
    )]
    [string]$Action = "help",

    [Parameter(Position = 1)]
    [string]$ApkPath = "whatsapp.apk"
)

$ErrorActionPreference = "Stop"

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    & docker compose @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed with exit code $LASTEXITCODE."
    }
}

function Wait-ForAndroid {
    Write-Host "Waiting for an Android device..."
    Invoke-Compose -Arguments @("exec", "-T", "vm", "adb", "wait-for-device")

    Write-Host "Waiting for Android to finish booting..."
    do {
        $bootCompleted = "$(& docker compose exec -T vm adb shell getprop sys.boot_completed 2>$null)".Trim()
        if ($LASTEXITCODE -ne 0) {
            throw "Could not query Android boot status."
        }

        if ($bootCompleted -ne "1") {
            Start-Sleep -Seconds 2
        }
    } while ($bootCompleted -ne "1")

    Write-Host "Android is ready."
}

function Install-WhatsApp {
    Wait-ForAndroid

    $resolvedApk = Resolve-Path -LiteralPath $ApkPath -ErrorAction Stop
    Write-Warning "Sideloading bypasses Google Play. Only continue with an untouched APK downloaded directly from whatsapp.com."
    Invoke-Compose -Arguments @("cp", $resolvedApk.Path, "vm:/tmp/whatsapp.apk")
    try {
        Invoke-Compose -Arguments @("exec", "-T", "vm", "adb", "install", "-r", "/tmp/whatsapp.apk")
    } finally {
        & docker compose exec -T vm rm -f /tmp/whatsapp.apk
    }
}

function Launch-WhatsApp {
    Invoke-Compose -Arguments @(
        "exec", "-T", "vm", "adb", "shell", "monkey",
        "-p", "com.whatsapp", "-c", "android.intent.category.LAUNCHER", "1"
    )
}

function Open-PlayStore {
    Wait-ForAndroid
    Invoke-Compose -Arguments @(
        "exec", "-T", "vm", "adb", "shell", "am", "start",
        "-a", "android.intent.action.VIEW",
        "-d", "market://details?id=com.whatsapp"
    )
}

function Show-Help {
    @"
Usage: wa-avd <action>

  up                 Build and start the VM in the background
  refresh            Re-download current SDK/image revisions and restart
  down               Stop and remove the VM container
  logs               Follow VM startup logs
  status             Show the container, ADB device, boot, and app status
  wait               Wait until Android has fully booted
  setup              Wait and launch WhatsApp, or open its Google Play page
  play-store         Open the official WhatsApp page in Google Play
  install [apk]      Sideload an explicitly supplied APK (not recommended)
  launch             Launch WhatsApp
  reset              Clear WhatsApp data and launch it again
  reinstall [apk]    Uninstall, sideload the supplied APK, and launch
  shell              Open a shell in the VM container
  entrypoint-debug   Run the complete startup script in the foreground
  emulator-debug     Run the emulator verbosely in the foreground
  help               Show this help
"@
}

switch ($Action) {
    "up" {
        Invoke-Compose -Arguments @("up", "--build", "-d")
        Write-Host "VM started. Follow startup with: wa-avd logs"
    }
    "refresh" {
        Invoke-Compose -Arguments @("build", "--pull", "--no-cache", "vm")
        Invoke-Compose -Arguments @("up", "-d", "vm")
        Write-Host "VM refreshed. Follow startup with: wa-avd logs"
    }
    "down" {
        Invoke-Compose -Arguments @("down")
    }
    "logs" {
        Invoke-Compose -Arguments @("logs", "--follow", "vm")
    }
    "status" {
        Invoke-Compose -Arguments @("ps")
        Invoke-Compose -Arguments @("exec", "-T", "vm", "adb", "devices")
        Invoke-Compose -Arguments @("exec", "-T", "vm", "adb", "shell", "getprop", "sys.boot_completed")
        Invoke-Compose -Arguments @("exec", "-T", "vm", "adb", "shell", "getprop", "ro.build.version.release")
        Invoke-Compose -Arguments @("exec", "-T", "vm", "adb", "shell", "getprop", "ro.build.version.sdk")
        Invoke-Compose -Arguments @("exec", "-T", "vm", "adb", "shell", "pm", "list", "packages", "com.android.vending")
        Invoke-Compose -Arguments @("exec", "-T", "vm", "adb", "shell", "pm", "list", "packages", "com.whatsapp")
    }
    "wait" {
        Wait-ForAndroid
    }
    "setup" {
        Wait-ForAndroid
        $installed = & docker compose exec -T vm adb shell pm list packages com.whatsapp
        if ($LASTEXITCODE -ne 0) {
            throw "Could not query installed Android packages."
        }

        if ($installed -match "package:com\.whatsapp") {
            Launch-WhatsApp
        } else {
            Open-PlayStore
        }
        Write-Host "Android is ready at http://localhost:6080"
    }
    "install" {
        Install-WhatsApp
    }
    "play-store" {
        Open-PlayStore
    }
    "launch" {
        Launch-WhatsApp
    }
    "reset" {
        Wait-ForAndroid
        Invoke-Compose -Arguments @("exec", "-T", "vm", "adb", "shell", "pm", "clear", "com.whatsapp")
        Launch-WhatsApp
    }
    "reinstall" {
        Wait-ForAndroid
        & docker compose exec -T vm adb uninstall com.whatsapp
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "WhatsApp was not installed; continuing with a clean install."
        }
        Install-WhatsApp
        Launch-WhatsApp
    }
    "shell" {
        Invoke-Compose -Arguments @("exec", "vm", "bash")
    }
    "entrypoint-debug" {
        Invoke-Compose -Arguments @("exec", "vm", "/app/entrypoint.sh")
    }
    "emulator-debug" {
        Invoke-Compose -Arguments @(
            "exec", "vm", "bash", "-lc",
            "export DISPLAY=:1.0; emulator -avd Pixel6_API36 -accel off -gpu swiftshader_indirect -no-boot-anim -no-snapshot-save -verbose"
        )
    }
    "help" {
        Show-Help
    }
}
