<#
    Runs RuneLite with the Elvarg client inside it.

    From runelite-client/target/classes and a resolved classpath rather than the shaded
    jar, so that rebuilding the game client is enough to pick it up -- the jar would have
    to be re-shaded for every change to it, and the loop here is mostly changes to it.

    Output goes to files because the interesting part is what the client refuses: each
    UnsupportedOperationException names a method of the contract that something wanted,
    and that list is the work queue.

        .\run-elvarg.ps1              launch, wait 45s, report
        .\run-elvarg.ps1 -Seconds 90  wait longer, for things that happen after login
        .\run-elvarg.ps1 -Keep        leave it running instead of killing it
#>
param(
    [int]$Seconds = 45,
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'

$Java   = 'C:\Users\hatem.HATEMMAINPC\.jdks\ms-17.0.17\bin\java.exe'
$Client = Join-Path $PSScriptRoot 'runelite-client'
$Cp     = Join-Path $Client 'target\cp.txt'

if (-not (Test-Path $Cp)) {
    throw "no classpath at $Cp. Run: mvn dependency:build-classpath -Dmdep.outputFile=target\cp.txt -Dmdep.includeScope=runtime"
}

$classpath = (Join-Path $Client 'target\classes') + ';' + (Get-Content $Cp -Raw).Trim()
$out = Join-Path $PSScriptRoot 'boot_out.txt'
$err = Join-Path $PSScriptRoot 'boot_err.txt'
Remove-Item $out, $err -ErrorAction SilentlyContinue

$proc = Start-Process -FilePath $Java -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -ArgumentList @(
    '-Drunelite.embeddedClient=com.runescape.Client',
    # Its own, not the one the other worktrees share. The provisioner reinstalls over any
    # directory it does not recognise as a current install, so pointing it at a populated
    # cache it did not create is how you damage that cache rather than reuse it.
    '-Delvarg.cache.directory=D:\runelite-fork-eval\.cache',
    '-cp', $classpath,
    'net.runelite.client.RuneLite',
    '--debug', '--disable-telemetry'
)

Write-Host "pid $($proc.Id), waiting ${Seconds}s..." -ForegroundColor Cyan
Start-Sleep -Seconds $Seconds

$alive = $null -ne (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)
Write-Host ("alive: {0}" -f $alive) -ForegroundColor $(if ($alive) { 'Green' } else { 'Red' })

Write-Host "`nrefused contract methods, by demand:" -ForegroundColor Cyan
$refused = Select-String -Path $out -Pattern 'UnsupportedOperationException: (\w+)' |
    ForEach-Object { $_.Matches[0].Groups[1].Value }
if ($refused) {
    $refused | Group-Object | Sort-Object Count -Descending |
        ForEach-Object { "  {0,4}x {1}" -f $_.Count, $_.Name }
} else {
    Write-Host '  none' -ForegroundColor Green
}

Write-Host "`nfatal:" -ForegroundColor Cyan
$fatal = Select-String -Path $out -Pattern 'Failure during startup'
if ($fatal) { $fatal | ForEach-Object { "  $($_.Line.Trim())" } } else { Write-Host '  none' -ForegroundColor Green }

if (-not $Keep) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Write-Host "`nstopped $($proc.Id)" -ForegroundColor DarkGray
} else {
    $proc.Id | Set-Content (Join-Path $PSScriptRoot 'boot_pid.txt')
    Write-Host "`nleft running as $($proc.Id)" -ForegroundColor DarkGray
}
