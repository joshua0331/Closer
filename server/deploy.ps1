param(
    [string]$ProjectId = 'iseeapp-ddf3a',
    [string]$Region = 'asia-southeast1',
    [int]$MetaSecretVersion = 1
)
$ErrorActionPreference = 'Stop'
if ($ProjectId -notmatch '^[a-z][a-z0-9-]{4,28}[a-z0-9]$' -or $Region -notmatch '^[a-z]+-[a-z]+[0-9]$' -or $MetaSecretVersion -lt 1) {
    throw 'Invalid project, region or secret version.'
}
if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) { throw 'Install Google Cloud CLI and sign in first.' }
function Invoke-Cloud {
    param([string[]]$CloudArgs)
    & gcloud @CloudArgs
    if ($LASTEXITCODE -ne 0) { throw "Cloud command failed. Review the error before retrying." }
}
$workspacePath = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $workspacePath
try {
    # Provisioning, secret creation and database initialization are separate,
    # explicit steps in hosted-demo.md. This script does not touch iSee apps/rules.
    $serviceAccount = "us-demo-runtime@$ProjectId.iam.gserviceaccount.com"
    $imageName = "$Region-docker.pkg.dev/$ProjectId/us-demo/backend:latest"
    Invoke-Cloud -CloudArgs @('builds','submit','.', '--project',$ProjectId,'--config','server/cloudbuild.yaml','--substitutions',"_IMAGE=$imageName")
    Invoke-Cloud -CloudArgs @('run','deploy','us-demo-backend','--project',$ProjectId,'--region',$Region,
      '--image',$imageName,'--service-account',$serviceAccount,
      '--allow-unauthenticated','--concurrency','4','--max-instances','2','--min-instances','0',
      '--timeout','240','--memory','512Mi','--cpu','1',
      '--set-env-vars',"BUDGET_STORE=firestore,GOOGLE_CLOUD_PROJECT=$ProjectId,FIRESTORE_DATABASE=us-demo-backend,BUDGET_COLLECTION=us_demo_security,META_JUDGE_MODEL=muse-spark-1.3",
      '--set-secrets',"MODEL_API_KEY=us-meta-api-key:$MetaSecretVersion")
} finally { Pop-Location }
