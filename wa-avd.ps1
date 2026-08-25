[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet(
        "up",
        "down",
        "logs",
        "status",
        "wait",
        "setup",
        "install",
        "launch",
        "reset",
        "reinstall",
        "shell",
        "entrypoint-debug",
        "emulator-debug",
        "help"
    )]
    [string]$Action = "help"
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
        $bootCompleted = (& docker compose exec -T vm adb shell getprop sys.boot_completed 2>$null).Trim()
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
    Invoke-Compose -Arguments @("exec", "-T", "vm", "adb", "install", "-r", "/app/whatsapp.apk")
}

function Launch-WhatsApp {
    Invoke-Compose -Arguments @(
        "exec", "-T", "vm", "adb", "shell", "monkey",
        "-p", "com.whatsapp", "-c", "android.intent.category.LAUNCHER", "1"
    )
}

function Show-Help {
    @"
Usage: wa-avd <action>

  up                 Build and start the VM in the background
  down               Stop and remove the VM container
  logs               Follow VM startup logs
  status             Show the container, ADB device, boot, and app status
  wait               Wait until Android has fully booted
  setup              Wait, install/update WhatsApp, and launch it
  install            Install/update /app/whatsapp.apk
  launch             Launch WhatsApp
  reset              Clear WhatsApp data and launch it again
  reinstall          Uninstall, reinstall, and launch WhatsApp
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
        Invoke-Compose -Arguments @("exec", "-T", "vm", "adb", "shell", "pm", "list", "packages", "com.whatsapp")
    }
    "wait" {
        Wait-ForAndroid
    }
    "setup" {
        Install-WhatsApp
        Launch-WhatsApp
        Write-Host "WhatsApp is ready at http://localhost:6080"
    }
    "install" {
        Install-WhatsApp
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
        Invoke-Compose -Arguments @("exec", "-T", "vm", "adb", "install", "/app/whatsapp.apk")
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
            "export DISPLAY=:1.0; emulator -avd Pixel -accel off -gpu swiftshader_indirect -no-boot-anim -no-snapshot-save -verbose"
        )
    }
    "help" {
        Show-Help
    }
}
