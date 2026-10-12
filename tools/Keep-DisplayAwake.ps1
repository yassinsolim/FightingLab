# Keeps the display and system awake while FightingLab work Studios render (stale frames otherwise). Stop the shell to release.
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Awake { [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags); }
"@
while ($true) {
	# ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED (0x80000003; PowerShell parses the hex literal as a negative Int32)
	[void][Awake]::SetThreadExecutionState([uint32]2147483651)
	Start-Sleep -Seconds 50
}
