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
    [switch]$Keep,
    # Reports what the host's overlay pass contributed to each frame. For when overlays
    # are expected and nothing appears, which has two causes that look the same.
    [switch]$VerifyOverlay,
    # Logs in as this account once the client reaches the login screen, so that the
    # in-game draw is exercised. Most of the contract is only reached from there: at
    # the login screen no overlay has a world to draw on and nothing asks the client
    # anything. Needs a server listening.
    [string]$User
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

$login = if ($User) { @("-Ddev.user=$User") } else { @() }
$verify = if ($VerifyOverlay) { @('-Dhost.overlay.verify','-Drunelite.overlay.probe') } else { @() }

$proc = Start-Process -FilePath $Java -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -ArgumentList (@(
    '-Drunelite.embeddedClient=com.runescape.Client',
    # The live cache the other worktrees use, version 6. The trailing separator is load
    # bearing: SignLink joins file names onto this by concatenation, so without it the
    # client reads and writes a sibling of the directory -- HatemLearning4main_file_cache.dat
    # -- finds nothing there, and reprovisions, which is what damages a cache it was
    # pointed at rather than reuses it.
    '-Delvarg.cache.directory=C:\Users\hatem.HATEMMAINPC\HatemLearning4\',
    # RuneLite keeps its configuration, profiles and cache under the home directory, so
    # moving the home moves all of it. Pointed here rather than left alone because this
    # is a fork being poked at, and the plugin settings it needs turned on are not
    # settings anyone would want applied to the RuneLite they actually play on.
    '-Duser.home=D:\runelite-fork-eval\.home'
) + $login + $verify + @(
    '-cp', $classpath,
    'net.runelite.client.RuneLite',
    '--debug', '--disable-telemetry'
))

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
