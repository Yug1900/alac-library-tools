
# ============================================================
# FLAC -> 16-bit ALAC batch converter for Windows
#
# 16-bit FLAC: no dithering
# 24-bit FLAC: triangular dithering to 16-bit
#
# Preserves folder structure, metadata, and embedded artwork.
# ============================================================

$ErrorActionPreference = "Stop"

# ---- FFmpeg LOCATION ----
# FFmpeg and FFprobe are expected to be available through PATH.
$FFmpeg = "ffmpeg.exe"
$FFprobe = "ffprobe.exe"

# ---- ASK FOR FOLDERS ----

Write-Host ""
Write-Host "=============================================="
Write-Host " FLAC -> 16-bit ALAC Batch Converter"
Write-Host "=============================================="
Write-Host ""

$InputRoot = Read-Host "Enter the INPUT folder containing your FLAC library"
$OutputRoot = Read-Host "Enter the OUTPUT folder for your ALAC library"

$InputRoot = [System.IO.Path]::GetFullPath($InputRoot.Trim().Trim('"'))
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot.Trim().Trim('"'))

if (-not (Test-Path -LiteralPath $InputRoot -PathType Container)) {
    throw "Input folder does not exist: $InputRoot"
}

if (-not (Test-Path -LiteralPath $OutputRoot)) {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
}

if (-not (Get-Command $FFmpeg -ErrorAction SilentlyContinue)) {
    throw "FFmpeg was not found in your PATH. Run 'ffmpeg -version' in PowerShell to verify."
}

if (-not (Get-Command $FFprobe -ErrorAction SilentlyContinue)) {
    throw "FFprobe was not found in your PATH. Run 'ffprobe -version' in PowerShell to verify."
}

Write-Host ""
Write-Host "Using FFmpeg:  " -NoNewline
(Get-Command $FFmpeg).Source

Write-Host "Using FFprobe: " -NoNewline
(Get-Command $FFprobe).Source

Write-Host ""

# Do not allow output inside input.
# This prevents accidental recursive processing.
$InputRootWithSlash = $InputRoot.TrimEnd('\') + '\'
$OutputRootWithSlash = $OutputRoot.TrimEnd('\') + '\'

if ($OutputRootWithSlash.StartsWith(
    $InputRootWithSlash,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "Output folder must not be inside the input folder."
}

New-Item -ItemType Directory -Force `
    -Path $OutputRoot | Out-Null

# ---- LOG FILES ----

$LogFile = Join-Path $OutputRoot "conversion-log.txt"
$FailedFile = Join-Path $OutputRoot "failed-files.txt"
$SkippedFile = Join-Path $OutputRoot "skipped-files.txt"

"Conversion started: $(Get-Date)" |
    Out-File -FilePath $LogFile -Encoding utf8

# ---- FIND FLAC FILES ----

$Files = Get-ChildItem `
    -LiteralPath $InputRoot `
    -File `
    -Recurse |
    Where-Object { $_.Extension -ieq ".flac" }

if ($Files.Count -eq 0) {
    Write-Host "No FLAC files found."
    exit
}

Write-Host ""
Write-Host "Input:  $InputRoot"
Write-Host "Output: $OutputRoot"
Write-Host "Files found: $($Files.Count)"
Write-Host ""

$Converted = 0
$Skipped = 0
$Failed = 0

# ---- PROCESS FILES ----

foreach ($File in $Files) {

    # Calculate relative path.
    $RelativePath = $File.FullName.Substring(
        $InputRoot.Length
    ).TrimStart('\')

    $RelativeDirectory = Split-Path `
        -Path $RelativePath `
        -Parent

    if ([string]::IsNullOrWhiteSpace($RelativeDirectory)) {
        $DestinationDirectory = $OutputRoot
    } else {
        $DestinationDirectory = Join-Path `
            $OutputRoot `
            $RelativeDirectory
    }

    # Recreate original directory structure.
    New-Item -ItemType Directory `
        -Force `
        -Path $DestinationDirectory |
        Out-Null

    $OutputFile = Join-Path `
        $DestinationDirectory `
        ($File.BaseName + ".m4a")

    Write-Host ""
    Write-Host "----------------------------------------------"
    Write-Host "File: $RelativePath"

    # ---- DETECT ORIGINAL BIT DEPTH ----

    try {
        $ProbeJson = & $FFprobe `
            -v error `
            -select_streams a:0 `
            -show_entries stream=bits_per_raw_sample,sample_fmt,sample_rate,channels `
            -of json `
            -- "$($File.FullName)" 2>$null

        if ($LASTEXITCODE -ne 0 -or -not $ProbeJson) {
            throw "FFprobe failed."
        }

        $Probe = $ProbeJson | ConvertFrom-Json
        $Stream = $Probe.streams[0]

        $BitDepth = $Stream.bits_per_raw_sample

        if (-not $BitDepth) {
            throw "Could not determine original bit depth."
        }

        $BitDepth = [int]$BitDepth

    } catch {
        Write-Warning "Could not inspect file: $($_.Exception.Message)"

        Add-Content $FailedFile $RelativePath
        $Failed++
        continue
    }

    Write-Host "Original bit depth: $BitDepth-bit"

    # ---- AVOID OVERWRITING ----

    if (Test-Path -LiteralPath $OutputFile) {
        Write-Host "Already exists. Skipping."
        Add-Content $SkippedFile $RelativePath
        $Skipped++
        continue
    }

    # Temporary output to avoid incomplete final files.
    $TempFile = $OutputFile + ".partial.m4a"

    if (Test-Path -LiteralPath $TempFile) {
        Remove-Item -LiteralPath $TempFile -Force
    }

# ---- CONVERT ----

$InputFile = $File

if ($BitDepth -eq 16) {

    Write-Host "16-bit input -> 16-bit / 44.1 kHz ALAC"
    Write-Host "Dithering: NONE"

    $FfmpegArgs = @(
        "-hide_banner",
        "-loglevel", "error",
        "-i", $InputFile.FullName,

        # Audio
        "-map", "0:a:0",
        "-af", "aresample=44100:osf=s16:dither_method=none",
        "-c:a", "alac",
        "-sample_fmt", "s16p",

        # Preserve metadata
        "-map_metadata", "0",

        # Preserve embedded artwork
        "-map", "0:v?",
        "-c:v", "mjpeg",
        "-q:v", "2",
        "-disposition:v", "attached_pic",

        # M4A / iPod-compatible container
        "-f", "ipod",

        # Write temporary file.
        "-y",
        $TempFile
    )

} elseif ($BitDepth -eq 24) {

    Write-Host "24-bit input -> 16-bit / 44.1 kHz ALAC"
    Write-Host "Dithering: TRIANGULAR"

    $FfmpegArgs = @(
        "-hide_banner",
        "-loglevel", "error",
        "-i", $InputFile.FullName,

        # Audio
        "-map", "0:a:0",
        "-af", "aresample=44100:osf=s16:dither_method=triangular",
        "-c:a", "alac",
        "-sample_fmt", "s16p",

        # Preserve metadata
        "-map_metadata", "0",

        # Preserve embedded artwork
        "-map", "0:v?",
        "-c:v", "mjpeg",
        "-q:v", "2",
        "-disposition:v", "attached_pic",

        # M4A / iPod-compatible container
        "-f", "ipod",

        # Write temporary file.
        "-y",
        $TempFile
    )

} else {

    Write-Host "WARNING: Unsupported bit depth: $BitDepth-bit"
    Write-Host "Skipping: $($InputFile.FullName)"

    Add-Content $SkippedFile $RelativePath
    $Skipped++
    continue
}

try {

    $ProcessResult = & $FFmpeg @FfmpegArgs 2>&1
    $ExitCode = $LASTEXITCODE

    if ($ExitCode -ne 0) {
        throw "FFmpeg returned error code $ExitCode`n$ProcessResult"
    }

    if (-not (Test-Path -LiteralPath $TempFile)) {
        throw "Output file was not created."
    }

    # Rename only after successful conversion.
    Move-Item `
        -LiteralPath $TempFile `
        -Destination $OutputFile

    Write-Host "SUCCESS: $OutputFile"

    Add-Content $LogFile `
        "$RelativePath | $BitDepth-bit -> 16-bit ALAC"

    $Converted++

} catch {

    Write-Warning "Conversion failed: $($_.Exception.Message)"

    if (Test-Path -LiteralPath $TempFile) {
        Remove-Item -LiteralPath $TempFile -Force
    }

    Add-Content $FailedFile $RelativePath
    $Failed++
}

}

# ---- SUMMARY ----

Write-Host ""
Write-Host "=============================================="
Write-Host " CONVERSION COMPLETE"
Write-Host "=============================================="
Write-Host "Converted: $Converted"
Write-Host "Skipped:   $Skipped"
Write-Host "Failed:    $Failed"
Write-Host ""
Write-Host "Log:     $LogFile"
Write-Host "Failed:  $FailedFile"
Write-Host "Skipped: $SkippedFile"
Write-Host ""