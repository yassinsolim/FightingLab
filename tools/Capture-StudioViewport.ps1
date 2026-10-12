param(
	[Parameter(Mandatory = $true)][string]$OutPath,
	[string]$PlacePath = 'C:\Users\solim\.copilot\session-state\e3751321-5f48-4183-b62a-9577765df8cf\files\FightingLab.rbxlx',
	[string]$CalibrationFile = 'C:\Users\solim\.copilot\session-state\e3751321-5f48-4183-b62a-9577765df8cf\files\overhaul2\gallery\viewport-rect.json',
	[switch]$Calibrate,
	[int]$Burst = 1,
	[int]$IntervalMs = 250
)
# Captures the Roblox Studio game viewport at full resolution with PrintWindow (no focus change).
# -Calibrate: a full-viewport magenta (255,0,255) GUI must be visible; records the viewport rectangle.
# Normal mode: crops the window capture to the recorded viewport and saves a PNG.
# Prints one JSON line with the output path, size and luminance statistics (meanLuma < 6 => black frame).
$ErrorActionPreference = 'Stop'
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class StudioShot {
	[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
	[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
	[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
	[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
	[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
	[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int cmd);
	public static Bitmap Capture(IntPtr h) {
		SetProcessDPIAware();
		RECT r;
		if (!GetWindowRect(h, out r)) throw new Exception("GetWindowRect failed");
		int w = r.Right - r.Left, ht = r.Bottom - r.Top;
		var bmp = new Bitmap(w, ht, PixelFormat.Format32bppArgb);
		using (var g = Graphics.FromImage(bmp)) {
			IntPtr hdc = g.GetHdc();
			bool ok = PrintWindow(h, hdc, 2);
			g.ReleaseHdc(hdc);
			if (!ok) throw new Exception("PrintWindow failed");
		}
		return bmp;
	}
	static byte[] Bytes(Bitmap bmp, out int stride) {
		var data = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
		stride = data.Stride;
		var buf = new byte[stride * bmp.Height];
		Marshal.Copy(data.Scan0, buf, 0, buf.Length);
		bmp.UnlockBits(data);
		return buf;
	}
	public static int[] FindColorBounds(Bitmap bmp, int r, int g, int b, int tol) {
		int stride; var buf = Bytes(bmp, out stride);
		int minX = int.MaxValue, minY = int.MaxValue, maxX = -1, maxY = -1; long count = 0;
		for (int y = 0; y < bmp.Height; y++) {
			int row = y * stride;
			for (int x = 0; x < bmp.Width; x++) {
				int i = row + x * 4;
				if (Math.Abs(buf[i + 2] - r) <= tol && Math.Abs(buf[i + 1] - g) <= tol && Math.Abs(buf[i] - b) <= tol) {
					count++;
					if (x < minX) minX = x; if (x > maxX) maxX = x;
					if (y < minY) minY = y; if (y > maxY) maxY = y;
				}
			}
		}
		if (maxX < 0) return null;
		return new int[] { minX, minY, maxX - minX + 1, maxY - minY + 1, (int)Math.Min(count, int.MaxValue) };
	}
	public static double[] LumaStats(Bitmap bmp) {
		int stride; var buf = Bytes(bmp, out stride);
		double sum = 0, sum2 = 0; long n = 0;
		for (int y = 0; y < bmp.Height; y += 2) {
			int row = y * stride;
			for (int x = 0; x < bmp.Width; x += 2) {
				int i = row + x * 4;
				double l = 0.2126 * buf[i + 2] + 0.7152 * buf[i + 1] + 0.0722 * buf[i];
				sum += l; sum2 += l * l; n++;
			}
		}
		double mean = sum / n;
		return new double[] { mean, Math.Sqrt(Math.Max(0, sum2 / n - mean * mean)) };
	}
}
'@

$full = [System.IO.Path]::GetFullPath($PlacePath)
$studio = Get-Process | Where-Object { $_.ProcessName -eq 'RobloxStudioBeta' -and $_.MainWindowTitle -eq "$full - Roblox Studio" } | Select-Object -First 1
if (-not $studio) { throw "No Studio window titled '$full - Roblox Studio'" }
$hwnd = $studio.MainWindowHandle
if ([StudioShot]::IsIconic($hwnd)) {
	[void][StudioShot]::ShowWindowAsync($hwnd, 4)
	Start-Sleep -Milliseconds 800
}
$bmp = [StudioShot]::Capture($hwnd)
try {
	if ($Calibrate) {
		$b = [StudioShot]::FindColorBounds($bmp, 255, 0, 255, 24)
		if ($null -eq $b -or $b[4] -lt 100000) { throw 'Calibration failed: no large magenta region found (is the full-viewport magenta frame visible?)' }
		$rect = [ordered]@{ x = $b[0]; y = $b[1]; w = $b[2]; h = $b[3]; windowW = $bmp.Width; windowH = $bmp.Height; magentaPixels = $b[4] }
		New-Item -ItemType Directory -Path (Split-Path -Parent $CalibrationFile) -Force | Out-Null
		$rect | ConvertTo-Json -Compress | Set-Content -LiteralPath $CalibrationFile -Encoding UTF8
		$bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
		$rect | ConvertTo-Json -Compress
		exit 0
	}
	if (-not (Test-Path -LiteralPath $CalibrationFile)) { throw "Missing calibration file $CalibrationFile; run with -Calibrate first" }
	$cal = Get-Content -LiteralPath $CalibrationFile -Raw | ConvertFrom-Json
	New-Item -ItemType Directory -Path (Split-Path -Parent $OutPath) -Force | Out-Null
	$frames = [Math]::Max(1, $Burst)
	for ($i = 1; $i -le $frames; $i++) {
		if ($i -gt 1) {
			Start-Sleep -Milliseconds $IntervalMs
			$bmp.Dispose()
			$bmp = [StudioShot]::Capture($hwnd)
		}
		if ($cal.windowW -ne $bmp.Width -or $cal.windowH -ne $bmp.Height) { throw "Studio window size changed ($($bmp.Width)x$($bmp.Height) vs calibrated $($cal.windowW)x$($cal.windowH)); recalibrate" }
		# Burst mode writes name-01.png, name-02.png, ... next to OutPath.
		$path = if ($frames -gt 1) { [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($OutPath), ('{0}-{1:00}{2}' -f [System.IO.Path]::GetFileNameWithoutExtension($OutPath), $i, [System.IO.Path]::GetExtension($OutPath))) } else { $OutPath }
		$crop = $bmp.Clone((New-Object System.Drawing.Rectangle($cal.x, $cal.y, $cal.w, $cal.h)), $bmp.PixelFormat)
		try {
			$crop.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
			$stats = [StudioShot]::LumaStats($crop)
			[ordered]@{ out = $path; width = $crop.Width; height = $crop.Height; meanLuma = [math]::Round($stats[0], 1); stdLuma = [math]::Round($stats[1], 1); blackFrame = ($stats[0] -lt 6) } | ConvertTo-Json -Compress
		} finally { $crop.Dispose() }
	}
} finally { $bmp.Dispose() }
