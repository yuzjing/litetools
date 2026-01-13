<#
.SYNOPSIS
    AWS Video Downloader (Ordered Collection Version)
    Features: 
    1. Downloads from urls.txt sequentially.
    2. Adds "Vol-XX" prefix to distinguish between different playlists/parts.
    3. Standardizes subtitles to ISO (chi/eng).
    4. Cleans filenames (Removes "Udemy..." spam but keeps Volume and Index).
#>

param (
    [string]$FixTargetFile = ""
)

# ==============================
# MODE A: Post-Processing Mode
# (Called automatically by yt-dlp)
# ==============================
if ($FixTargetFile -ne "") {
    $File = Get-Item $FixTargetFile
    $TempFile = "$($File.FullName).temp.mkv"
    
    Write-Host "🔧 [Processing] $($File.Name)" -ForegroundColor Cyan

    # --- Step 1: Standardize Subtitles ---
    
    # Try Dual Subtitles first (Chinese/English)
    $process = Start-Process -FilePath "ffmpeg" -ArgumentList "-y -v error -i `"$($File.FullName)`" -map 0 -c copy -metadata:s:s:0 language=chi -metadata:s:s:0 title=`"Chinese`" -metadata:s:s:1 language=eng -metadata:s:s:1 title=`"English`" `"$TempFile`"" -PassThru -Wait -NoNewWindow
    
    # If failed, try Single Subtitle (Chinese only)
    if ($process.ExitCode -ne 0) {
        Write-Host "⚠️  [Info] Dual subs failed, trying single..." -ForegroundColor Yellow
        $process = Start-Process -FilePath "ffmpeg" -ArgumentList "-y -v error -i `"$($File.FullName)`" -map 0 -c copy -metadata:s:s:0 language=chi -metadata:s:s:0 title=`"Chinese`" `"$TempFile`"" -PassThru -Wait -NoNewWindow
    }

    if ($process.ExitCode -eq 0) {
        # Overwrite original file
        Move-Item -Path $TempFile -Destination $File.FullName -Force
        
        # --- Step 2: Clean Filename (Updated Regex) ---
        # Current Pattern: "Vol-01 - 001 - 01-09_Udemy..._p01_01-001_Intro.mkv"
        # Desired Pattern: "Vol-01 - 001 - 01-001_Intro.mkv"
        
        # Regex Explanation:
        # ^(Vol-\d+ - \d{3} - )  -> Capture Group 1: Matches "Vol-01 - 001 - "
        # .*?_p\d+_              -> Non-greedy match for the middle garbage until "_pXX_"
        # (.*)$                  -> Capture Group 2: Matches the clean title at the end
        
        if ($File.Name -match "^(Vol-\d+ - \d{3} - ).*?_p\d+_(.*)$") {
            $NewName = $matches[1] + $matches[2]
            
            try {
                Rename-Item -Path $File.FullName -NewName $NewName -ErrorAction Stop
                Write-Host "✨ [Renamed] -> $NewName" -ForegroundColor Green
            } catch {
                Write-Host "⚠️ [Rename Skipped] Target file might already exist." -ForegroundColor Yellow
            }
        } else {
            Write-Host "🔹 [Info] Filename pattern did not match regex or is already clean." -ForegroundColor DarkGray
        }

    } else {
        Write-Host "❌ [Error] FFmpeg failed." -ForegroundColor Red
        if (Test-Path $TempFile) { Remove-Item $TempFile }
    }
    exit
}

# ==============================
# MODE B: Main Download Loop
# ==============================

# 1. Check Prerequisites
if (-not (Get-Command "yt-dlp.exe" -ErrorAction SilentlyContinue)) { 
    if (-not (Test-Path ".\yt-dlp.exe")) { Write-Error "Error: yt-dlp.exe not found!"; exit }
}
if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue)) { 
    if (-not (Test-Path ".\ffmpeg.exe")) { Write-Error "Error: ffmpeg not found!"; exit }
}
if (-not (Test-Path ".\urls.txt")) { Write-Error "Error: urls.txt not found!"; exit }

# 2. Output Directory
$OutputDir = "AWS_SAA_Course"
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }

# 3. Get Script Path for Callback
$ScriptPath = $MyInvocation.MyCommand.Path

# 4. Initialize Volume Counter
$VolIndex = 1

# 5. Start Download Loop
Get-Content ".\urls.txt" | ForEach-Object {
    $url = $_.Trim()
    if ($url -ne "") {
        # Create Prefix: Vol-01, Vol-02, etc.
        $VolPrefix = "Vol-{0:D2}" -f $VolIndex
        
        Write-Host "`n⬇️  Start Downloading [$VolPrefix]: $url" -ForegroundColor Green
        
        # Command to call this script again in Mode A
        $ExecCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -FixTargetFile {}"

        # Note: Added $VolPrefix to the output template (-o)
        .\yt-dlp.exe `
            --cookies-from-browser firefox `
            --paths $OutputDir `
            -f "bv+ba/b" `
            --write-subs --write-auto-sub `
            --sub-lang "ai-zh,ai-en" `
            --convert-subs srt `
            --embed-subs `
            --merge-output-format mkv `
            -o "$VolPrefix - %(playlist_index)03d - %(title).100s.%(ext)s" `
            --restrict-filenames `
            --exec $ExecCmd `
            $url
            
        # Increment Counter for next URL
        $VolIndex++
    }
}

Write-Host "`n🎉 All tasks completed successfully!" -ForegroundColor Magenta
Pause
