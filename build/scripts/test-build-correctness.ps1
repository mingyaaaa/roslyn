<#
    This script drives the Jenkins verification that our build is correct.  In particular:

        - Our build has no double writes
        - Our project.json files are consistent
        - Our build files are well structured
        - Our solution states are consistent
        - Our generated files are consistent

#>

[CmdletBinding(PositionalBinding=$false)]
param(
    [string]$configuration = "Debug",
    [switch]$help)

Set-StrictMode -version 2.0
$ErrorActionPreference="Stop"

function Print-Usage() {
    Write-Host "Usage: test-build-correctness.ps1"
    Write-Host "  -configuration            Build configuration ('Debug' or 'Release')"
}

try {
    if ($help) {
        Print-Usage
        exit 0
    }

    $ci = $true

    . (Join-Path $PSScriptRoot "build-utils.ps1")
    Push-Location $RepoRoot

    Write-Host "Building Roslyn"
    Exec-Block { & (Join-Path $PSScriptRoot "build.ps1") -restore -build -ci:$ci -configuration:$configuration -pack -binaryLog -useGlobalNuGetCache:$false }


    # Verify the state of our various build artifacts
    Write-Host "Running BuildBoss"
    $buildBossPath = Join-Path $BinariesConfigDir "Exes\BuildBoss\BuildBoss.exe"
    $releaseArg = if ($configuration -eq "Release") { "-release" } else { "" }
    Exec-Console $buildBossPath "Roslyn.sln Compilers.sln SourceBuild.sln -r $RepoRoot $releaseArg"
    Write-Host ""

    # Verify the state of our generated syntax files
    Write-Host "Checking generated compiler files"
    Exec-Block { & (Join-Path $PSScriptRoot "generate-compiler-code.ps1") -test }
    Write-Host ""
    
    # Verfiy the state of creating run settings for optprof
    Write-Host "Checking run generation for optprof"

    # set environment variables
    if (-not (Test-Path env:SYSTEM_TEAMPROJECT)) { $env:SYSTEM_TEAMPROJECT = "DevDiv" }
    if (-not (Test-Path env:BUILD_REPOSITORY_NAME)) { $env:BUILD_REPOSITORY_NAME = "dotnet/roslyn" }
    if (-not (Test-Path env:BUILD_SOURCEBRANCHNAME)) { $env:BUILD_SOURCEBRANCHNAME = "test" }
    if (-not (Test-Path env:BUILD_BUILDID)) { $env:BUILD_BUILDID = "42.42.42.42" }
    if (-not (Test-Path env:BUILD_SOURCESDIRECTORY)) { $env:BUILD_SOURCESDIRECTORY = $RepoRoot }
    if (-not (Test-Path env:BUILD_STAGINGDIRECTORY)) { $env:BUILD_STAGINGDIRECTORY = $BinariesConfigDir }

    # create a fake BootstrapperInfo.json file
    $bootstrapperInfoFolder = Join-Path $BinariesConfigDir "MicroBuild\Output"
    Create-Directory $bootstrapperInfoFolder
    
    $bootstrapperInfoPath = Join-Path $bootstrapperInfoFolder "BootstrapperInfo.json"
    $bootstrapperInfoContent = "[{""VSBuildVersion"":  ""42.42.42424.42""}]"
    $bootstrapperInfoContent >> $bootstrapperInfoPath

    # generate run settings
    Exec-Block { & (Join-Path $PSScriptRoot "createrunsettings.ps1") }
    
    exit 0
}
catch [exception] {
    Write-Host $_
    Write-Host $_.Exception
    exit 1
}
finally {
    Pop-Location
}
