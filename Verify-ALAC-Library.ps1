# Verify-ALAC-Library.ps1
# Checks that every M4A is:
#   - ALAC
#   - 16-bit
#   - 44.1 kHz
#
# Requires ffprobe.exe to be available in PATH.

$Library = Read-Host "Enter the ALAC library folder"

if (-not (Test-Path -LiteralPath $Library -PathType Container)) {
    throw "Folder does not exist: $Library"
}

if (-not (Get-Command ffprobe.exe -ErrorAction SilentlyContinue)) {
    throw "ffprobe.exe was not found in your PATH."
}

$Files = Get-ChildItem -LiteralPath $Library -Filter "*.m4a" -File -Recurse

Write-Host ""
Write-Host "=============================================="
Write-Host " ALAC Library Verification"
Write-Host "=============================================="
Write-Host ""
Write-Host "Files found: $($Files.Count)"
Write-Host ""

$Passed = 0
$Failed = 0
$Failures = @()

foreach ($File in $Files) {

    $ProbeArgs = @(
        "-v", "error",
        "-select_streams", "a:0",
        "-show_entries", "stream=codec_name,sample_rate,bits_per_raw_sample,sample_fmt",
        "-of", "json",
        $File.FullName
    )

    try {
        $Json = & ffprobe.exe @ProbeArgs 2>$null | Out-String
        $Info = $Json | ConvertFrom-Json

        if (-not $Info.streams -or $Info.streams.Count -eq 0) {
            throw "No audio stream found"
        }

        $Stream = $Info.streams[0]

        $Codec       = [string]$Stream.codec_name
        $SampleRate  = [int]$Stream.sample_rate
        $BitDepth    = [int]$Stream.bits_per_raw_sample
        $SampleFmt   = [string]$Stream.sample_fmt

        $Reasons = @()

        if ($Codec -ne "alac") {
            $Reasons += "codec=$Codec"
        }

        if ($SampleRate -ne 44100) {
            $Reasons += "sample rate=$SampleRate Hz"
        }

        # ALAC normally reports 16-bit as bits_per_raw_sample=16.
        # sample_fmt=s16p is also expected for 16-bit ALAC.
        if ($BitDepth -ne 16 -or $SampleFmt -ne "s16p") {
            $Reasons += "bit depth/sample format=$BitDepth-bit/$SampleFmt"
        }

        if ($Reasons.Count -eq 0) {
            $Passed++
        }
        else {
            $Failed++

            $Failures += [PSCustomObject]@{
                File   = $File.FullName
                Reason = ($Reasons -join "; ")
            }
        }
    }
    catch {
        $Failed++

        $Failures += [PSCustomObject]@{
            File   = $File.FullName
            Reason = "Could not read file"
        }
    }
}

Write-Host "=============================================="
Write-Host " Results"
Write-Host "=============================================="
Write-Host ""

Write-Host "PASS: $Passed"
Write-Host "FAIL: $Failed"
Write-Host ""

if ($Failed -eq 0) {
    Write-Host "ALL FILES PASSED."
    Write-Host ""
    Write-Host "Every file is ALAC, 16-bit, and 44.1 kHz."
}
else {
    Write-Host "FILES THAT FAILED:"
    Write-Host ""

    foreach ($Failure in $Failures) {
        Write-Host "FAIL: $($Failure.File)"
        Write-Host "      $($Failure.Reason)"
        Write-Host ""
    }
}