# Build and stage ClaudeBridge against the installed RobotStudio 6.08 SDK.
[CmdletBinding()]
param(
    [string]$RobotStudioDir = 'D:\Program Files (x86)\ABB Industrial IT\Robotics IT\RobotStudio 6.08',
    [string]$NewtonsoftJsonPath,
    [string]$Destination,
    [switch]$System
)

$ErrorActionPreference = 'Stop'

try {
    if ($System -and $Destination) {
        throw 'Use either -System or -Destination.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $RobotStudioDir 'Bin\ABB.Robotics.RobotStudio.dll') -PathType Leaf)) {
        throw "RobotStudio SDK not found: $RobotStudioDir"
    }
    if (-not $NewtonsoftJsonPath) {
        $NewtonsoftJsonPath = Join-Path $RobotStudioDir 'Bin\Addins\ConveyorTrackingModuleAddin\Newtonsoft.Json.dll'
    }
    if (-not (Test-Path -LiteralPath $NewtonsoftJsonPath -PathType Leaf)) {
        throw "Newtonsoft.Json.dll not found. Supply -NewtonsoftJsonPath: $NewtonsoftJsonPath"
    }

    $manifest = Join-Path $PSScriptRoot 'addin\ClaudeBridge.rsaddin'
    $document = New-Object System.Xml.XmlDocument
    $document.Load($manifest)
    [void]$document.Schemas.Add('urn:abb-robotics-robotstudio-addin', (Join-Path $RobotStudioDir 'Schemas\RobotStudioAddin.xsd'))
    $document.Validate($null)

    # Rebuild even when a previous DLL exists, so it cannot target a different SDK.
    & dotnet build (Join-Path $PSScriptRoot 'addin\ClaudeBridge.csproj') -c Release '-t:Rebuild' "-p:RobotStudioDir=$RobotStudioDir" "-p:NewtonsoftJsonPath=$NewtonsoftJsonPath"
    if ($LASTEXITCODE -ne 0) {
        throw "Add-In build failed (exit code $LASTEXITCODE). No files deployed."
    }

    $source = Join-Path $PSScriptRoot 'addin\bin'
    $files = @((Join-Path $source 'ClaudeBridge.dll'), (Join-Path $source 'Newtonsoft.Json.dll'), $manifest)
    foreach ($file in $files) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Build output missing: $file. No files deployed."
        }
    }
    if ($System) {
        $Destination = Join-Path $RobotStudioDir 'Bin\Addins\ClaudeBridge'
    } elseif (-not $Destination) {
        $Destination = Join-Path $PSScriptRoot 'artifacts\ClaudeBridge'
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($file in $files) {
        Copy-Item -LiteralPath $file -Destination $Destination -Force
    }
    Write-Host "ClaudeBridge prepared at: $Destination"
    Write-Host 'Start RobotStudio with /addin:"<destination>\ClaudeBridge.rsaddin", then verify http://localhost:58080/ping (see README).'
} catch {
    Write-Error $_
    exit 1
}
