<#
.SYNOPSIS
    Bilibili Video Downloader 
    
#>

param (
    [string]$FixTargetFile = ""
)


if ($FixTargetFile -ne "") {
    $File = Get-Item $FixTargetFile
    $TempFile = "$($File.FullName).temp.mkv"
    
    Write-Host "🔧 [Processing] $($File.Name)" -ForegroundColor Cyan

    
    $process = Start-Process -FilePath "ffmpeg" -ArgumentList "-y -v error -i `"$($File.FullName)`" -map 0 -c copy -metadata:s:s:0 language=chi -metadata:s:s:0 title=`"Chinese`" -metadata:s:s:1 language=eng -metadata:s:s:1 title=`"English`" `"$TempFile`"" -PassThru -Wait -NoNewWindow
    
    
    if ($process.ExitCode -ne 0) {
        Write-Host "⚠️  [Info] Trying single subtitle..." -ForegroundColor Yellow
        $process = Start-Process -FilePath "ffmpeg" -ArgumentList "-y -v error -i `"$($File.FullName)`" -map 0 -c copy -metadata:s:s:0 language=chi -metadata:s:s:0 title=`"Chinese`" `"$TempFile`"" -PassThru -Wait -NoNewWindow
    }

    if ($process.ExitCode -eq 0) {
       
        Move-Item -Path $TempFile -Destination $File.FullName -Force
        
        
        $BaseNamePattern = [WildcardPattern]::Escape($File.BaseName)
        $RelatedSrts = Get-ChildItem -Path $File.DirectoryName -Filter "$BaseNamePattern*.srt"
        if ($RelatedSrts) {
            $RelatedSrts | Remove-Item -Force
            Write-Host "🗑️ [Cleanup] Deleted external SRT files." -ForegroundColor DarkGray
        }

        
        if ($File.Name -match "^(\d{3} - ).*?_p\d+_(.*)$") {
            $NewName = $matches[1] + $matches[2]
            try {
                Rename-Item -Path $File.FullName -NewName $NewName -ErrorAction Stop
                Write-Host "✨ [Renamed] -> $NewName" -ForegroundColor Green
            } catch {
                Write-Host "⚠️ [Rename Skipped] Target file exists." -ForegroundColor Yellow
            }
        } else {
            Write-Host "🔹 [Info] Filename format mismatch, keeping original." -ForegroundColor DarkGray
        }

    } else {
        Write-Host "❌ [Error] FFmpeg failed." -ForegroundColor Red
        if (Test-Path $TempFile) { Remove-Item $TempFile }
    }
    exit
}



if (-not (Get-Command "yt-dlp.exe" -ErrorAction SilentlyContinue)) { if (-not (Test-Path ".\yt-dlp.exe")) { Write-Error "yt-dlp.exe missing!"; exit } }
if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue)) { if (-not (Test-Path ".\ffmpeg.exe")) { Write-Error "ffmpeg missing!"; exit } }
if (-not (Test-Path ".\urls.txt")) { Write-Error "urls.txt missing!"; exit }

$OutputDir = "AWS_SAA_Course"
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
$ScriptPath = $MyInvocation.MyCommand.Path

Get-Content ".\urls.txt" | ForEach-Object {
    $url = $_.Trim()
    if ($url -ne "") {
        Write-Host "`n⬇️  Start Downloading: $url" -ForegroundColor Green
        
        $ExecCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -FixTargetFile {}"

        .\yt-dlp.exe `
            --cookies-from-browser firefox `
            --paths $OutputDir `
            -f "bv+ba/b" `
            --write-subs --write-auto-sub `
            --sub-lang "ai-zh,ai-en" `
            --convert-subs srt `
            --embed-subs `
            --merge-output-format mkv `
            -o '%(playlist_index)03d - %(title).100s.%(ext)s' `
            --restrict-filenames `
            --exec $ExecCmd `
            $url
    }
}

Write-Host "`n🎉 All tasks completed!" -ForegroundColor Magenta
Pause
