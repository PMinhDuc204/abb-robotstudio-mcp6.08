# Run: powershell -NoProfile -ExecutionPolicy Bypass -File test/install-addin.test.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$buildRoot = [IO.Path]::GetFullPath((Join-Path $repo 'addin\bin'))
$testRoot = Join-Path $buildRoot ('installer-selfcheck-' + [guid]::NewGuid())
$realSchema = 'D:\Program Files (x86)\ABB Industrial IT\Robotics IT\RobotStudio 6.08\Schemas\RobotStudioAddin.xsd'
if (-not (Test-Path -LiteralPath $realSchema)) { throw 'This check requires the local RobotStudio 6.08 XSD.' }

try {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'install-addin.ps1'), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    New-Item -ItemType Directory -Path "$testRoot\addin\bin", "$testRoot\sdk\Bin", "$testRoot\sdk\Schemas" -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'install-addin.ps1') -Destination $testRoot
    Copy-Item -LiteralPath (Join-Path $repo 'addin\ClaudeBridge.rsaddin') -Destination "$testRoot\addin"
    Copy-Item -LiteralPath $realSchema -Destination "$testRoot\sdk\Schemas"
    'bridge-fixture' | Set-Content "$testRoot\addin\bin\ClaudeBridge.dll"
    'json-fixture' | Set-Content "$testRoot\addin\bin\Newtonsoft.Json.dll"
    'sdk-fixture' | Set-Content "$testRoot\sdk\Bin\ABB.Robotics.RobotStudio.dll"
    @'
param([int]$BuildExitCode, [string]$Destination, [switch]$System)
function dotnet {
    @($args) | ConvertTo-Json | Set-Content "$PSScriptRoot\build-args.json"
    $global:LASTEXITCODE = $BuildExitCode
}
$options = @{
    RobotStudioDir = "$PSScriptRoot\sdk"
    NewtonsoftJsonPath = "$PSScriptRoot\addin\bin\Newtonsoft.Json.dll"
}
if ($Destination) { $options.Destination = $Destination }
if ($System) { $options.System = $true }
& "$PSScriptRoot\install-addin.ps1" @options
'@ | Set-Content "$testRoot\run.ps1"

    & powershell -NoProfile -ExecutionPolicy Bypass -File "$testRoot\run.ps1" -BuildExitCode 0
    if ($LASTEXITCODE -ne 0) { throw 'Default staging failed.' }
    $buildArgs = Get-Content "$testRoot\build-args.json" -Raw | ConvertFrom-Json
    if ($buildArgs -notcontains '-t:Rebuild' -or $buildArgs -notcontains "-p:RobotStudioDir=$testRoot\sdk") {
        throw 'Rebuild or SDK argument missing.'
    }
    foreach ($name in @('ClaudeBridge.dll', 'Newtonsoft.Json.dll', 'ClaudeBridge.rsaddin')) {
        $source = if ($name -eq 'ClaudeBridge.rsaddin') { "$testRoot\addin\$name" } else { "$testRoot\addin\bin\$name" }
        if ((Get-FileHash $source).Hash -ne (Get-FileHash "$testRoot\artifacts\ClaudeBridge\$name").Hash) {
            throw "Staging file differs: $name"
        }
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$testRoot\run.ps1" -BuildExitCode 0 -Destination "$testRoot\custom"
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$testRoot\custom\ClaudeBridge.rsaddin")) { throw 'Custom destination failed.' }
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$testRoot\run.ps1" -BuildExitCode 42 -Destination "$testRoot\failed"
    if ($LASTEXITCODE -eq 0 -or (Test-Path "$testRoot\failed")) { throw 'Failed build deployed files or returned success.' }
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$testRoot\run.ps1" -BuildExitCode 0 -System
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$testRoot\sdk\Bin\Addins\ClaudeBridge\ClaudeBridge.rsaddin")) { throw 'System destination failed.' }
    Write-Host 'PASS: schema, rebuild/SDK arguments, manifest/dependencies, staging/custom/system destinations, build failure.'
} finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    if (-not $resolvedTestRoot.StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove unexpected fixture path: $resolvedTestRoot"
    }
    if (Test-Path -LiteralPath $resolvedTestRoot) { Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force }
}
