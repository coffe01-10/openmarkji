param([switch]$DebugBuild)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$localProperties = Get-Content -LiteralPath (Join-Path $projectRoot 'android/local.properties')
$sdkLine = $localProperties | Where-Object { $_.StartsWith('flutter.sdk=') } | Select-Object -First 1
$flutterSdk = $sdkLine.Substring('flutter.sdk='.Length).Replace('\\', '\')
$aliasPath = Join-Path ([IO.Path]::GetTempPath()) ('OpenMarkjiBuild-' + $PID)
# The Windows AOT executable misreads non-ASCII paths. Build through an ASCII junction.
New-Item -ItemType Junction -Path $aliasPath -Target $projectRoot | Out-Null
try {
    Push-Location -LiteralPath $aliasPath
    try {
        $buildArgs = @((Join-Path $flutterSdk 'bin/cache/flutter_tools.snapshot'), 'build', 'apk', '--no-pub')
        if ($DebugBuild) { $buildArgs += '--debug' } else { $buildArgs += @('--release', '--split-per-abi') }
        & (Join-Path $flutterSdk 'bin/cache/dart-sdk/bin/dart.exe') @buildArgs
        $buildResult = $LASTEXITCODE
    } finally { Pop-Location }
} finally {
    $junction = Get-Item -LiteralPath $aliasPath -Force
    if ($junction.LinkType -eq 'Junction' -and $junction.Target -eq $projectRoot) {
        # Remove only the temporary junction, never recurse into the checkout.
        Remove-Item -LiteralPath $aliasPath -Force
    }
    # Native build hooks can flush caches just after Flutter exits, recreating
    # a real directory where the junction was. Remove only this owned temp path.
    for ($cleanupAttempt = 0; $cleanupAttempt -lt 4; $cleanupAttempt++) {
        Start-Sleep -Milliseconds 250
        if (Test-Path -LiteralPath $aliasPath) {
            $remaining = Get-Item -LiteralPath $aliasPath -Force
            $insideTemp = [IO.Path]::GetFullPath($remaining.FullName).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)
            if ($insideTemp -and -not ($remaining.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                Remove-Item -LiteralPath $remaining.FullName -Recurse -Force
            }
        }
    }
}
if ($buildResult -ne 0) { exit $buildResult }
