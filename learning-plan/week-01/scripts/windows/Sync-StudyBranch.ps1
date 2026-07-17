[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$RemoteName = "study",
    [string]$RepoRoot,
    [switch]$SkipPush
)

$ErrorActionPreference = "Stop"
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $PSScriptRoot "../../config/nodes.local.json"
}
if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../../..")).Path
}
$safePath = $RepoRoot.Replace('\', '/')

if (-not (Test-Path $ConfigPath)) {
    throw "Missing $ConfigPath. Copy nodes.example.json to nodes.local.json and fill it first."
}

$branch = (& git -c "safe.directory=$safePath" -C $RepoRoot branch --show-current).Trim()
if (-not $branch) { throw "Detached HEAD is not supported by this study sync script." }
if ($branch -notlike "study/*") { throw "Current branch '$branch' is not a study/* branch." }

& git -c "safe.directory=$safePath" -C $RepoRoot diff --quiet
if ($LASTEXITCODE -ne 0) { throw "Working tree has unstaged changes. Commit or stash them before syncing." }
& git -c "safe.directory=$safePath" -C $RepoRoot diff --cached --quiet
if ($LASTEXITCODE -ne 0) { throw "Index has staged but uncommitted changes. Commit them before syncing." }
$untracked = & git -c "safe.directory=$safePath" -C $RepoRoot ls-files --others --exclude-standard
if ($untracked) { throw "Working tree has untracked files. Commit, ignore, or remove them before syncing." }

if (-not $SkipPush) {
    Write-Host "Pushing $branch to $RemoteName..."
    & git -c "safe.directory=$safePath" -C $RepoRoot push $RemoteName "HEAD:$branch"
    if ($LASTEXITCODE -ne 0) { throw "git push failed; Linux nodes were not changed." }
}

$nodes = Get-Content -Raw -Encoding UTF8 $ConfigPath | ConvertFrom-Json
foreach ($node in $nodes) {
    if (-not $node.host -or -not $node.user -or -not $node.repoPath) {
        throw "Each node must define host, user, and repoPath."
    }

    $target = "$($node.user)@$($node.host)"
    $repoPath = $node.repoPath
    if ($repoPath -notmatch '^/[A-Za-z0-9._/-]+$') {
        throw "Unsafe repoPath '$repoPath' for $($node.name). Use an absolute path containing letters, digits, dot, underscore, slash, or dash."
    }
    if ($branch -notmatch '^[A-Za-z0-9._/-]+$') { throw "Unsafe branch name '$branch'." }
    if ($RemoteName -notmatch '^[A-Za-z0-9._-]+$') { throw "Unsafe remote name '$RemoteName'." }

    Write-Host "Updating $($node.name) ($target)..."
    $remoteCommand = @(
        "set -e"
        "cd '$repoPath'"
        "test -d .git"
        'test -z "$(git status --porcelain)"'
        "git fetch '$RemoteName' '$branch'"
        "git checkout '$branch'"
        "git merge --ff-only '$RemoteName/$branch'"
        "git rev-parse --short HEAD"
    ) -join "; "
    & ssh $target $remoteCommand
    if ($LASTEXITCODE -ne 0) { throw "Update failed on $($node.name). Remaining nodes were not processed." }
}

Write-Host "All nodes now match committed branch $branch." -ForegroundColor Green
