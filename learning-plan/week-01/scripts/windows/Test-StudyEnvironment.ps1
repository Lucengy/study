[CmdletBinding()]
param(
    [string]$RepoRoot
)

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../../..")).Path
}

function Write-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    $status = if ($Passed) { "PASS" } else { "FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }
    Write-Host ("[{0}] {1}: {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Passed) { $script:Failures++ }
}

$script:Failures = 0
Write-Host "Ratis study environment check"
Write-Host "Repository: $RepoRoot"

$git = Get-Command git -ErrorAction SilentlyContinue
Write-Check "Git" ($null -ne $git) $(if ($git) { (git --version) } else { "not found in PATH" })

$java = Get-Command java -ErrorAction SilentlyContinue
if ($java) {
    # java -version writes to stderr; cmd.exe keeps it as ordinary captured text
    # under Windows PowerShell's Stop error preference.
    $javaOutput = (& cmd.exe /d /c "java -version 2>&1" | Out-String).Trim()
    $majorMatch = [regex]::Match($javaOutput, 'version "(?:1\.)?(\d+)')
    $major = if ($majorMatch.Success) { [int]$majorMatch.Groups[1].Value } else { 0 }
    Write-Check "Java 11" ($major -eq 11) (($javaOutput -split "`r?`n")[0])
} else {
    Write-Check "Java 11" $false "java not found in PATH"
}

$maven = Get-Command mvn -ErrorAction SilentlyContinue
if ($maven) {
    $mavenOutput = (& cmd.exe /d /c "mvn -version 2>&1" | Out-String).Trim()
    $mavenHeader = ($mavenOutput -split "`r?`n" | Where-Object { $_ -match '^Apache Maven ' } | Select-Object -First 1)
    if (-not $mavenHeader) { $mavenHeader = ($mavenOutput -split "`r?`n")[0] }
    Write-Check "Maven" ($LASTEXITCODE -eq 0) $mavenHeader
    $mavenJava = ($mavenOutput -split "`r?`n" | Where-Object { $_ -match '^Java version:' } | Select-Object -First 1)
    if ($mavenJava) { Write-Host "       $mavenJava" }
} else {
    Write-Host "[INFO] Maven: mvn not found; the repository Maven Wrapper can still be used." -ForegroundColor Yellow
}

Write-Check "Maven Wrapper" (Test-Path (Join-Path $RepoRoot "mvnw.cmd")) "mvnw.cmd"
Write-Check "Root POM" (Test-Path (Join-Path $RepoRoot "pom.xml")) "pom.xml"

if ($git) {
    $safePath = $RepoRoot.Replace('\', '/')
    $status = & git -c "safe.directory=$safePath" -C $RepoRoot status --short --branch 2>&1
    Write-Host "`nGit status (read-only):"
    $status | ForEach-Object { Write-Host $_ }
    if ($status -match "dubious ownership") {
        Write-Host "Git does not trust this directory. Review Day 1 before adding safe.directory." -ForegroundColor Yellow
    }
}

Write-Host "`nExpected baseline: Java 11 on Windows and all three CentOS nodes."
if ($script:Failures -gt 0) {
    Write-Host "Environment check found $script:Failures issue(s)." -ForegroundColor Yellow
    exit 1
}
