param(
  [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
  [string]$SourceImage = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$sourceDir = Join-Path $ProjectRoot 'assets\court\source'
$outputDir = Join-Path $ProjectRoot 'assets\court\seated'
New-Item -ItemType Directory -Force -Path $sourceDir,$outputDir | Out-Null
$keptSource = Join-Path $sourceDir 'courtroom_seated_original.png'
if (-not $SourceImage) { $SourceImage = $keptSource }
if (-not (Test-Path -LiteralPath $SourceImage)) { throw "Courtroom source image was not found: $SourceImage" }
if ([IO.Path]::GetFullPath($SourceImage) -ne [IO.Path]::GetFullPath($keptSource)) {
  Copy-Item -LiteralPath $SourceImage -Destination $keptSource -Force
}
Copy-Item -LiteralPath $keptSource -Destination (Join-Path $outputDir 'courtroom.png') -Force

$code = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class SeatedCourtParts
{
    static bool Inside(int x, int y, double[] poly)
    {
        bool inside = false;
        for (int i = 0, j = poly.Length - 2; i < poly.Length; i += 2)
        {
            double xi = poly[i], yi = poly[i + 1];
            double xj = poly[j], yj = poly[j + 1];
            if (((yi > y) != (yj > y)) &&
                (x < (xj - xi) * (y - yi) / (yj - yi) + xi))
                inside = !inside;
            j = i;
        }
        return inside;
    }
    public static void Extract(string input, string output, double[] poly)
    {
        using (var source = new Bitmap(input))
        using (var result = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb))
        {
            var srcData = source.LockBits(new Rectangle(0,0,source.Width,source.Height),
                ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            var dstData = result.LockBits(new Rectangle(0,0,result.Width,result.Height),
                ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            int length = source.Width * source.Height * 4;
            var src = new byte[length];
            var dst = new byte[length];
            Marshal.Copy(srcData.Scan0, src, 0, length);
            for (int y=0; y<source.Height; y++)
            for (int x=0; x<source.Width; x++)
            {
                if (!Inside(x, y, poly)) continue;
                int p = (y * source.Width + x) * 4;
                dst[p] = src[p]; dst[p+1] = src[p+1];
                dst[p+2] = src[p+2]; dst[p+3] = src[p+3];
            }
            Marshal.Copy(dst, 0, dstData.Scan0, length);
            source.UnlockBits(srcData);
            result.UnlockBits(dstData);
            result.Save(output, ImageFormat.Png);
        }
    }
}
"@
Add-Type -TypeDefinition $code -ReferencedAssemblies System.Drawing

$parts = @{
  girl_gesture_hand = [double[]]@(396,466, 402,460, 410,462, 415,467, 418,461, 423,463, 423,469, 429,468, 434,473, 431,480, 423,486, 414,491, 405,489, 398,483)
  girl_rest_hand = [double[]]@(246,532, 251,527, 259,527, 267,531, 276,535, 281,541, 278,550, 270,557, 260,560, 251,556, 246,549)
  boy_gesture_hand = [double[]]@(1245,479, 1252,476, 1260,479, 1264,484, 1269,481, 1273,484, 1272,490, 1281,489, 1285,495, 1282,501, 1275,507, 1266,511, 1257,509, 1250,504, 1245,496)
  boy_rest_hand = [double[]]@(1464,528, 1470,522, 1478,520, 1485,525, 1491,520, 1497,524, 1503,520, 1509,524, 1516,530, 1517,538, 1511,545, 1500,551, 1489,557, 1478,556, 1468,550, 1463,540)
  judge_gavel_hand = [double[]]@(644,251, 672,255, 692,264, 718,278, 711,297, 699,302, 697,323, 689,336, 676,332, 666,324, 653,322, 648,315, 657,301, 660,288, 647,281)
  judge_rest_hand = [double[]]@(871,326, 875,317, 881,312, 889,312, 895,316, 902,312, 909,315, 914,321, 921,323, 923,330, 917,337, 906,342, 893,343, 881,340, 875,335)
}
foreach ($name in $parts.Keys) {
  [SeatedCourtParts]::Extract((Join-Path $outputDir 'courtroom.png'), (Join-Path $outputDir "$name.png"), $parts[$name])
}
Write-Output "Prepared full-scene seated courtroom and hand overlays in $outputDir"
Get-ChildItem -LiteralPath $outputDir | Select-Object Name,Length
