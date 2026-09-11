<#
    Screenshots a window belonging to a given process.

    By window rather than by screen, because the screen has other things on it and a
    capture of the whole desktop is not evidence of anything about this client.

        .\shot.ps1 -ProcessId 1234 -Out shot.png
        .\shot.ps1 -ProcessId 1234 -Title RuneLite -Out shot.png
#>
param(
    [Parameter(Mandatory)][int]$ProcessId,
    [string]$Title,
    [string]$Out = 'shot.png'
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class WinShot
{
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
    delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    // PW_RENDERFULLCONTENT. Asks the window to draw itself into a bitmap, which is the only
    // way to get the right one when something else is on top of it -- a screen copy would
    // return whatever is visually there, and has.
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);

    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }

    public static List<object[]> ForPid(uint target)
    {
        var res = new List<object[]>();
        EnumWindows((h, l) =>
        {
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            if (pid == target && IsWindowVisible(h))
            {
                var sb = new StringBuilder(256);
                GetWindowText(h, sb, 256);
                RECT r;
                GetWindowRect(h, out r);
                res.Add(new object[] { h, sb.ToString(), r.L, r.T, r.R - r.L, r.B - r.T });
            }
            return true;
        }, IntPtr.Zero);
        return res;
    }
}
'@

$windows = [WinShot]::ForPid([uint32]$ProcessId)
if (-not $windows) { throw "process $ProcessId has no visible windows" }

Write-Host 'windows:' -ForegroundColor Cyan
$windows | ForEach-Object { "  '{0}'  {1},{2}  {3}x{4}" -f $_[1], $_[2], $_[3], $_[4], $_[5] }

$target = if ($Title) {
    $windows | Where-Object { $_[1] -match $Title } | Select-Object -First 1
} else {
    # Largest, which is the one carrying the application rather than a dialog or a tooltip.
    $windows | Sort-Object { [int]$_[4] * [int]$_[5] } -Descending | Select-Object -First 1
}
if (-not $target) { throw "no window matching '$Title'" }

[WinShot]::SetForegroundWindow($target[0]) | Out-Null
Start-Sleep -Milliseconds 1500

Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap ([int]$target[4]), ([int]$target[5])
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $gfx.GetHdc()
$printed = [WinShot]::PrintWindow($target[0], $hdc, 2)
$gfx.ReleaseHdc($hdc)
if (-not $printed) {
    Write-Host 'PrintWindow refused; falling back to a screen copy' -ForegroundColor Yellow
    $gfx.CopyFromScreen(
        (New-Object System.Drawing.Point ([int]$target[2]), ([int]$target[3])),
        [System.Drawing.Point]::Empty,
        (New-Object System.Drawing.Size ([int]$target[4]), ([int]$target[5])))
}
$path = if ([IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $PWD $Out }
$bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
$gfx.Dispose()
$bmp.Dispose()

Write-Host "saved $path" -ForegroundColor Green
