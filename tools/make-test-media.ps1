# Generates the short clips used by "Tester ma TV" into TeleCast/Resources/TestMedia.
# Requires ffmpeg on PATH. Usage: powershell -ExecutionPolicy Bypass -File tools/make-test-media.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "TeleCast/Resources/TestMedia"
New-Item -ItemType Directory -Force -Path (Join-Path $out "hls"), (Join-Path $out "fmp4") | Out-Null
Get-ChildItem -Path $out -Recurse -File | Remove-Item -Force

$font = "C\:/Windows/Fonts/arialbd.ttf"

function Get-SourceArgs([string]$label, [string]$color) {
    return @(
        "-f", "lavfi", "-i", "color=c=$($color):s=1280x720:r=25:d=8",
        "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100:duration=8",
        "-vf", "drawtext=fontfile='$font':text='TeleCast - $label':fontcolor=white:fontsize=72:x=(w-text_w)/2:y=(h-text_h)/2"
    )
}

$encode = @(
    "-c:v", "libx264", "-profile:v", "main", "-level", "3.1", "-pix_fmt", "yuv420p", "-preset", "veryfast",
    "-b:v", "800k", "-g", "50", "-keyint_min", "50", "-sc_threshold", "0",
    "-c:a", "aac", "-b:a", "96k", "-ar", "44100", "-shortest"
)

& ffmpeg -hide_banner -loglevel error -y @(Get-SourceArgs "MP4 OK" "0x6D28D9") @encode -movflags +faststart (Join-Path $out "test.mp4")

& ffmpeg -hide_banner -loglevel error -y @(Get-SourceArgs "HLS OK" "0x0F766E") @encode `
    -f hls -hls_time 4 -hls_playlist_type vod `
    -hls_segment_filename (Join-Path $out "hls/seg%d.ts") (Join-Path $out "hls/index.m3u8")

# ffmpeg writes the fMP4 init section relative to the working directory: run it inside the folder.
Push-Location (Join-Path $out "fmp4")
try {
    & ffmpeg -hide_banner -loglevel error -y @(Get-SourceArgs "fMP4 OK" "0xB45309") @encode `
        -f hls -hls_time 4 -hls_playlist_type vod -hls_segment_type fmp4 -hls_fmp4_init_filename "init.mp4" `
        -hls_segment_filename "seg%d.m4s" "index.m3u8"
} finally {
    Pop-Location
}

Get-ChildItem -Path $out -Recurse -File | Select-Object @{ n = "Fichier"; e = { $_.FullName.Substring($out.Length + 1) } }, Length
