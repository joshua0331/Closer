param(
    [Parameter(Mandatory = $true)][string]$ProjectId,
    [string]$Region = 'asia-southeast1'
)
$ErrorActionPreference = 'Stop'
if ($ProjectId -notmatch '^[a-z][a-z0-9-]{4,28}[a-z0-9]$' -or $Region -notmatch '^[a-z]+-[a-z]+[0-9]$') {
    throw 'Invalid project or region.'
}
if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    throw 'Run this on a computer with Google Cloud CLI installed and signed in to the Closer project.'
}
function Invoke-Cloud {
    param([string[]]$CloudArgs)
    & gcloud @CloudArgs
    if ($LASTEXITCODE -ne 0) { throw 'Cloud update failed. See the error above.' }
}
Push-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
try {
    # Require an existing service; this is an update, not initial provisioning.
    Invoke-Cloud -CloudArgs @('run', 'services', 'describe', 'closer-demo-backend', '--project', $ProjectId, '--region', $Region, '--format=value(status.url)')
    $releaseTag = 'memories-' + (Get-Date -Format 'yyyyMMddHHmmss')
    $imageName = "$Region-docker.pkg.dev/$ProjectId/closer-demo/backend:$releaseTag"
    Invoke-Cloud -CloudArgs @('builds', 'submit', '.', '--project', $ProjectId, '--config', 'server/cloudbuild.yaml', '--substitutions', "_IMAGE=$imageName")
    # Only replace the image. Retain environment variables, secrets, IAM,
    # runtime identity, scaling and other existing service settings.
    Invoke-Cloud -CloudArgs @('run', 'services', 'update', 'closer-demo-backend', '--project', $ProjectId, '--region', $Region, '--image', $imageName)
    Write-Host 'Backend image updated. Verify the new revision receives traffic, then test albums in Closer.'
} finally {
    Pop-Location
}
