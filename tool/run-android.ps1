param([string]$DeviceId)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
$previousGradleCache = $env:GRADLE_USER_HOME
try {
    $env:GRADLE_USER_HOME = Join-Path $projectRoot '.gradle-closer'
    if (-not $DeviceId) {
        $devices = (& flutter devices --machine | Out-String) | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) { throw 'Could not list Flutter devices.' }
        $androidDevices = @($devices | Where-Object { $_.targetPlatform -like 'android-*' -and $_.isSupported })
        if ($androidDevices.Count -eq 0) { throw 'Start an Android emulator in Android Studio, or connect a phone with USB debugging, then run this script again.' }
        $DeviceId = $androidDevices[0].id
        Write-Host ('Starting Closer on ' + $androidDevices[0].name)
    }
    & flutter run -d $DeviceId
    if ($LASTEXITCODE -ne 0) { throw 'Flutter could not start. Review the output above.' }
} finally {
    $env:GRADLE_USER_HOME = $previousGradleCache
    Pop-Location
}
