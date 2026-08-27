[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidatePattern('^[a-z_][a-z0-9_-]{0,31}$')]
    [ValidateScript({ $_ -ne 'root' })]
    [string]$DesktopUser = 'avd'
)

$ErrorActionPreference = 'Stop'
$envFile = Join-Path $PSScriptRoot '.env'

if (Test-Path -LiteralPath $envFile) {
    throw "Refusing to overwrite $envFile. Remove it explicitly to rotate credentials."
}

function New-RandomHex {
    param([Parameter(Mandatory = $true)][int]$ByteCount)

    $bytes = [byte[]]::new($ByteCount)
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
    } finally {
        $generator.Dispose()
    }
    return ([System.BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
}

$lines = @(
    "DESKTOP_USER=$DesktopUser"
    "DESKTOP_PASSWORD=$(New-RandomHex -ByteCount 24)"
    "HTTP_PASSWORD=$(New-RandomHex -ByteCount 24)"
    # The VNC protocol accepts at most eight characters. It is also protected
    # by HTTP authentication and the loopback-only SSH tunnel.
    "VNC_PASSWORD=$(New-RandomHex -ByteCount 4)"
)

$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($envFile, (($lines -join "`n") + "`n"), $utf8WithoutBom)

Write-Host "Created $envFile with a non-root desktop user and random credentials."
Write-Host 'The file is ignored by Git. Keep it private and back it up securely.'
