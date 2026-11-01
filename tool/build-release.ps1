param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
$previousGradleCache = $env:GRADLE_USER_HOME
try {
    $env:GRADLE_USER_HOME = Join-Path $projectRoot '.gradle-closer'
    & flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw 'Android release build failed. Review the Gradle output above.' }
} finally {
    $env:GRADLE_USER_HOME = $previousGradleCache
    Pop-Location
}
