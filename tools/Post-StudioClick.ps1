param(
	[Parameter(Mandatory = $true)][int]$ProcessId,
	[Parameter(Mandatory = $true)][int]$X,
	[Parameter(Mandatory = $true)][int]$Y
)
# Clicks a point of a Roblox Studio window (window/screen pixel coordinates, window at its current position) by
# posting mouse messages to the deepest child window under that point. The window is never activated or raised.
$ErrorActionPreference = 'Stop'
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public static class QuietClick {
	[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
	[DllImport("user32.dll")] static extern bool SetProcessDPIAware();
	[DllImport("user32.dll")] static extern IntPtr ChildWindowFromPointEx(IntPtr parent, POINT pt, uint flags);
	[DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr h, ref POINT p);
	[DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
	public static string Click(IntPtr top, int screenX, int screenY) {
		SetProcessDPIAware();
		IntPtr target = top; int depth = 0;
		while (true) {
			var p = new POINT { X = screenX, Y = screenY }; ScreenToClient(target, ref p);
			IntPtr child = ChildWindowFromPointEx(target, p, 1 | 4); // CWP_SKIPINVISIBLE | CWP_SKIPTRANSPARENT
			if (child == IntPtr.Zero || child == target) break;
			target = child; depth++;
		}
		var c = new POINT { X = screenX, Y = screenY }; ScreenToClient(target, ref c);
		IntPtr l = (IntPtr)((c.Y << 16) | (c.X & 0xFFFF));
		PostMessage(target, 0x0200, IntPtr.Zero, l);       // WM_MOUSEMOVE
		PostMessage(target, 0x0201, (IntPtr)1, l);         // WM_LBUTTONDOWN (MK_LBUTTON)
		PostMessage(target, 0x0202, IntPtr.Zero, l);       // WM_LBUTTONUP
		return "posted click at depth " + depth + " client=(" + c.X + "," + c.Y + ")";
	}
}
"@
$h = (Get-Process -Id $ProcessId).MainWindowHandle
if ($h -eq [IntPtr]::Zero) { throw "process $ProcessId has no main window" }
[QuietClick]::Click($h, $X, $Y)
