# Draws the app icon (concept C: car inside a cycle arrow) as a 1024x1024 PNG without alpha channel.
# Run: powershell -ExecutionPolicy Bypass -File scripts/render-icon.ps1
# Output: App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png and Design/AppIcon-preview-180.png
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$iconPath = Join-Path $root "App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
$previewDir = Join-Path $root "Design"
New-Item -ItemType Directory -Force $previewDir | Out-Null

# Drawing is described on a 120x120 grid and scaled to 1024.
$S = 1024 / 120.0
$DY = -4   # moves the whole drawing up so the circle is optically centered

function P([double]$x, [double]$y) {
    New-Object System.Drawing.PointF ([float]($x * $S)), ([float](($y + $DY) * $S))
}
function RoundRect([double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $X = [float]($x * $S); $Y = [float](($y + $DY) * $S); $W = [float]($w * $S); $H = [float]($h * $S); $D = [float]($r * $S * 2)
    $p.AddArc($X, $Y, $D, $D, 180, 90)
    $p.AddArc($X + $W - $D, $Y, $D, $D, 270, 90)
    $p.AddArc($X + $W - $D, $Y + $H - $D, $D, $D, 0, 90)
    $p.AddArc($X, $Y + $H - $D, $D, $D, 90, 90)
    $p.CloseFigure()
    $p
}

$bmp = New-Object System.Drawing.Bitmap 1024, 1024, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

# Background: teal, slightly lighter at the top.
$rect = New-Object System.Drawing.Rectangle 0, 0, 1024, 1024
$top = [System.Drawing.Color]::FromArgb(255, 22, 178, 156)
$bottom = [System.Drawing.Color]::FromArgb(255, 11, 128, 112)
$g.FillRectangle((New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $top, $bottom, 90), $rect)
$white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$cut = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 14, 150, 132))

# Cycle arrow: arc drawn clockwise from 0 degrees, arrowhead at its end pointing along the motion.
$cx = 60; $cy = 64; $r = 44; $sweep = 292
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), ([float](7 * $S))
$pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Flat
$g.DrawArc($pen, [float](($cx - $r) * $S), [float](($cy - $r + $DY) * $S), [float](2 * $r * $S), [float](2 * $r * $S), 0, $sweep)
$t = $sweep * [Math]::PI / 180
$ex = $cx + $r * [Math]::Cos($t); $ey = $cy + $r * [Math]::Sin($t)
$tx = -[Math]::Sin($t); $ty = [Math]::Cos($t)   # direction of motion
$nx = [Math]::Cos($t); $ny = [Math]::Sin($t)     # outward normal
$L = 13; $W = 10
$head = [System.Drawing.PointF[]]@(
    (P ($ex + $tx * $L) ($ey + $ty * $L)),
    (P ($ex + $nx * $W) ($ey + $ny * $W)),
    (P ($ex - $nx * $W) ($ey - $ny * $W)))
$g.FillPolygon($white, $head)

# Car, front view.
$g.FillPolygon($white, [System.Drawing.PointF[]]@((P 38 61), (P 46 44), (P 74 44), (P 82 61)))
$g.FillPath($white, (RoundRect 30 59 60 25 7))
$g.FillPolygon($cut, [System.Drawing.PointF[]]@((P 45.5 59), (P 50.5 48.5), (P 69.5 48.5), (P 74.5 59)))
$g.FillEllipse($cut, [float](35.5 * $S), [float]((67 + $DY) * $S), [float](9 * $S), [float](9 * $S))
$g.FillEllipse($cut, [float](75.5 * $S), [float]((67 + $DY) * $S), [float](9 * $S), [float](9 * $S))
$g.FillPath($white, (RoundRect 35 82 11 10 2.5))
$g.FillPath($white, (RoundRect 74 82 11 10 2.5))
$g.Dispose()

$bmp.Save($iconPath, [System.Drawing.Imaging.ImageFormat]::Png)
$small = New-Object System.Drawing.Bitmap 180, 180
$g2 = [System.Drawing.Graphics]::FromImage($small)
$g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g2.DrawImage($bmp, 0, 0, 180, 180)
$g2.Dispose()
$small.Save((Join-Path $previewDir "AppIcon-preview-180.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$small.Dispose(); $bmp.Dispose()
Write-Output "Wrote $iconPath"
