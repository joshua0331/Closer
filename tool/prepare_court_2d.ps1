param(
  [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
  [string]$Courtroom = '',
  [string]$Judge = '',
  [string]$Girl = '',
  [string]$Boy = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$sourceDir = Join-Path $ProjectRoot 'assets\court\source'
if (-not $Courtroom) { $Courtroom = Join-Path $sourceDir 'courtroom_original.png' }
if (-not $Judge) { $Judge = Join-Path $sourceDir 'judge_original.png' }
if (-not $Girl) { $Girl = Join-Path $sourceDir 'girl_original.png' }
if (-not $Boy) { $Boy = Join-Path $sourceDir 'boy_original.png' }
$source = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Collections.Generic;
public static class CourtArt
{
    static Bitmap Read32(string path)
    {
        using (var src = new Bitmap(path))
        {
            var bmp = new Bitmap(src.Width, src.Height, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.Transparent);
                g.DrawImage(src, new Rectangle(0, 0, src.Width, src.Height));
            }
            return bmp;
        }
    }
    static byte[] Pixels(Bitmap bmp, out BitmapData data)
    {
        data = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height),
            ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        var bytes = new byte[bmp.Width * bmp.Height * 4];
        Marshal.Copy(data.Scan0, bytes, 0, bytes.Length);
        return bytes;
    }
    static void SavePixels(Bitmap bmp, BitmapData data, byte[] bytes, string path)
    {
        Marshal.Copy(bytes, 0, data.Scan0, bytes.Length);
        bmp.UnlockBits(data);
        bmp.Save(path, ImageFormat.Png);
    }
    static bool IsBoard(byte[] p, int i)
    {
        int b = p[i], g = p[i+1], r = p[i+2], a = p[i+3];
        int lo = Math.Min(r, Math.Min(g,b)), hi = Math.Max(r, Math.Max(g,b));
        return a > 0 && lo > 142 && hi - lo < 24;
    }
    public static void Clean(string input, string output)
    {
        using (var bmp = Read32(input))
        {
            BitmapData data; var p = Pixels(bmp, out data);
            int w=bmp.Width, h=bmp.Height, n=w*h;
            var candidate = new bool[n]; var seen = new bool[n];
            for (int i=0;i<n;i++) candidate[i]=IsBoard(p, i*4);
            var q = new Queue<int>();
            Action<int> push = i => { if (i>=0 && i<n && !seen[i] && candidate[i]) { seen[i]=true; q.Enqueue(i); } };
            for (int x=0;x<w;x++) { push(x); push((h-1)*w+x); }
            for (int y=0;y<h;y++) { push(y*w); push(y*w+w-1); }
            while(q.Count>0)
            {
                int i=q.Dequeue(); p[i*4+3]=0;
                int x=i%w, y=i/w;
                if(x>0) push(i-1); if(x+1<w) push(i+1);
                if(y>0) push(i-w); if(y+1<h) push(i+w);
            }
            SavePixels(bmp, data, p, output);
        }
    }
    static bool Inside(double x, double y, double[] poly)
    {
        bool inside=false;
        for(int i=0,j=poly.Length-2;i<poly.Length;i+=2)
        {
            double xi=poly[i], yi=poly[i+1], xj=poly[j], yj=poly[j+1];
            bool cross=((yi>y)!=(yj>y)) && (x < (xj-xi)*(y-yi)/(yj-yi)+xi);
            if(cross) inside=!inside;
            j=i;
        }
        return inside;
    }
    public static void Layer(string input, string output, double[][] masks, bool keepInside)
    {
        using (var bmp=Read32(input))
        {
            BitmapData data; var p=Pixels(bmp,out data);
            int w=bmp.Width,h=bmp.Height;
            for(int y=0;y<h;y++) for(int x=0;x<w;x++)
            {
                bool inside=false;
                for(int k=0;k<masks.Length && !inside;k++) inside=Inside(x+0.5,y+0.5,masks[k]);
                if(inside!=keepInside) p[(y*w+x)*4+3]=0;
            }
            SavePixels(bmp,data,p,output);
        }
    }
}
"@
Add-Type -TypeDefinition $source -ReferencedAssemblies System.Drawing
$outDir = Join-Path $ProjectRoot 'assets\court\2d'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$clean = Join-Path $outDir 'court_stage.png'
[CourtArt]::Clean($Courtroom, $clean)
$judgeClean = Join-Path $outDir 'judge_clean.png'
$girlClean = Join-Path $outDir 'girl_clean.png'
$boyClean = Join-Path $outDir 'boy_clean.png'
[CourtArt]::Clean($Judge, $judgeClean)
[CourtArt]::Clean($Girl, $girlClean)
[CourtArt]::Clean($Boy, $boyClean)
$girlLeft = @(60,380,500,380,500,505,68,505)
$girlRight = @(738,380,1172,380,1172,505,738,505)
$boyLeft = @(48,370,432,370,432,492,54,492)
$boyRight = @(798,370,1176,370,1176,492,798,492)
[double[][]]$girlMasks = [double[][]]::new(2)
$girlMasks[0] = [double[]]$girlLeft
$girlMasks[1] = [double[]]$girlRight
[double[][]]$boyMasks = [double[][]]::new(2)
$boyMasks[0] = [double[]]$boyLeft
$boyMasks[1] = [double[]]$boyRight
[double[][]]$girlLeftMask = [double[][]]::new(1)
$girlLeftMask[0] = [double[]]$girlLeft
[double[][]]$girlRightMask = [double[][]]::new(1)
$girlRightMask[0] = [double[]]$girlRight
[double[][]]$boyLeftMask = [double[][]]::new(1)
$boyLeftMask[0] = [double[]]$boyLeft
[double[][]]$boyRightMask = [double[][]]::new(1)
$boyRightMask[0] = [double[]]$boyRight
[CourtArt]::Layer($girlClean,(Join-Path $outDir 'girl_body.png'),$girlMasks,$false)
[CourtArt]::Layer($girlClean,(Join-Path $outDir 'girl_arm_left.png'),$girlLeftMask,$true)
[CourtArt]::Layer($girlClean,(Join-Path $outDir 'girl_arm_right.png'),$girlRightMask,$true)
[CourtArt]::Layer($boyClean,(Join-Path $outDir 'boy_body.png'),$boyMasks,$false)
[CourtArt]::Layer($boyClean,(Join-Path $outDir 'boy_arm_left.png'),$boyLeftMask,$true)
[CourtArt]::Layer($boyClean,(Join-Path $outDir 'boy_arm_right.png'),$boyRightMask,$true)
$gavel = @(0,260,205,260,205,603,0,603)
[double[][]]$gavelMask = [double[][]]::new(1)
$gavelMask[0] = [double[]]$gavel
[CourtArt]::Layer($judgeClean,(Join-Path $outDir 'judge_body.png'),$gavelMask,$false)
[CourtArt]::Layer($judgeClean,(Join-Path $outDir 'judge_gavel_hand.png'),$gavelMask,$true)
Remove-Item -LiteralPath $judgeClean,$girlClean,$boyClean
Write-Output "Prepared layered transparent 2D court art in $outDir"
Get-ChildItem -LiteralPath $outDir | Select-Object Name,Length
