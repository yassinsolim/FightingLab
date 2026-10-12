param([Parameter(Mandatory = $true)][int]$ProcessId, [int]$Width = 1920, [int]$Height = 1040)
# Restores a Studio window without activating it and parks it at the bottom of the z-order (never covers the user's windows).
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class WinPark {
	[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int cmd);
	[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
	[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
	[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[void][WinPark]::SetProcessDPIAware()
$p = Get-Process -Id $ProcessId -ErrorAction Stop
$h = $p.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { throw "process $ProcessId has no main window" }
if ([WinPark]::IsIconic($h)) { [void][WinPark]::ShowWindowAsync($h, 4); Start-Sleep -Milliseconds 400 }
# HWND_BOTTOM = 1, SWP_NOACTIVATE = 0x0010
[void][WinPark]::SetWindowPos($h, [IntPtr]1, 0, 0, $Width, $Height, 0x0010)
"parked pid $ProcessId at bottom, ${Width}x${Height}"
