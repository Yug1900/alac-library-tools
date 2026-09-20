# ALAC Library Tools

Two interactive PowerShell utilities for building and checking an Apple Lossless (ALAC) music library on Windows.

## Requirements

- PowerShell 5.1 or newer
- `ffmpeg.exe` and `ffprobe.exe` available on your `PATH`

## Convert FLAC to ALAC

Run `Convert-FLAC-to-ALAC.ps1` to convert an entire FLAC library to 16-bit, 44.1 kHz ALAC (`.m4a`). The script asks for input and output folders, mirrors the input folder structure, keeps metadata and embedded artwork, and never overwrites existing output files.

- 16-bit FLAC is resampled without dithering.
- 24-bit FLAC is reduced to 16-bit with triangular dithering.
- Other bit depths are skipped.
- A temporary file is used before each completed file is renamed into place.
- The output folder receives a conversion log plus lists of skipped and failed files.

The output folder must not be inside the source library, preventing recursive processing.

## Verify an ALAC library

Run `Verify-ALAC-Library.ps1` to inspect every `.m4a` file beneath a chosen library folder. It reports whether each file is ALAC, 16-bit (`s16p`), and 44.1 kHz, then prints pass/fail totals and details for any failures.

## Usage

From PowerShell, run either script and enter the requested folder path:

```powershell
.\Convert-FLAC-to-ALAC.ps1
.\Verify-ALAC-Library.ps1
```

If script execution is restricted on your machine, use an execution policy appropriate to your environment.
