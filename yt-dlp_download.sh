#!/bin/bash

# ==========================================
# AWS Video Downloader (WSL2/Linux Version)
# Features: 
# 1. Downloads from urls.txt
# 2. Standardizes subtitles to ISO (chi/eng)
# 3. Cleans filenames (Removes "Udemy..." spam)
# ==========================================

OUTPUT_DIR="AWS_SAA_Course"
URLS_FILE="urls.txt"
HELPER_SCRIPT="process_helper.sh"

# 1. Check Prerequisites
if ! command -v yt-dlp &> /dev/null; then
    echo "❌ Error: 'yt-dlp' not found. Please install it in WSL."
    exit 1
fi
if ! command -v ffmpeg &> /dev/null; then
    echo "❌ Error: 'ffmpeg' not found. Please install it (sudo apt install ffmpeg)."
    exit 1
fi
if [ ! -f "$URLS_FILE" ]; then
    echo "❌ Error: '$URLS_FILE' not found. Please create it with your links."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# 2. Generate the temporary helper script
# This script handles the post-processing (FFmpeg + Rename) for each file
cat << 'EOF' > "$HELPER_SCRIPT"
#!/bin/bash

FILE="$1"
DIR=$(dirname "$FILE")
FILENAME=$(basename "$FILE")
TEMP_FILE="${FILE%.*}.temp.mkv"

echo "🔧 [Processing] $FILENAME"

# --- Step A: Standardize Subtitles (ISO Metadata) ---

# Try Dual Subtitles (Track 0=Chinese, Track 1=English)
ffmpeg -y -v error -nostdin -i "$FILE" -map 0 -c copy \
-metadata:s:s:0 language=chi -metadata:s:s:0 title="Chinese" \
-metadata:s:s:1 language=eng -metadata:s:s:1 title="English" \
"$TEMP_FILE"

if [ $? -eq 0 ]; then
    mv -f "$TEMP_FILE" "$FILE"
    echo "✅ [Subtitles] Dual language fixed."
else
    # Fallback: Single Subtitle (Track 0=Chinese)
    echo "⚠️  [Info] Dual subs failed, trying single..."
    ffmpeg -y -v error -nostdin -i "$FILE" -map 0 -c copy \
    -metadata:s:s:0 language=chi -metadata:s:s:0 title="Chinese" \
    "$TEMP_FILE"
    
    if [ $? -eq 0 ]; then
        mv -f "$TEMP_FILE" "$FILE"
        echo "✅ [Subtitles] Single language fixed."
    else
        echo "❌ [Error] Subtitle processing failed."
        rm -f "$TEMP_FILE"
    fi
fi

# --- Step B: Clean Filename (Regex Rename) ---
# Goal: Change "001 - 01-09_Udemy_..._p01_01-001_Title.mkv" 
# To:   "001 - 01-001_Title.mkv"

# Regex logic:
# ^([0-9]{3} - )  -> Matches "001 - " (Group 1)
# .*_p[0-9]+_     -> Matches everything in middle including "_p01_" (Discarded)
# (.*)$           -> Matches the rest "01-001_Title.mkv" (Group 2)

if [[ "$FILENAME" =~ ^([0-9]{3}\ -\ ).*_p[0-9]+_(.*)$ ]]; then
    NEW_NAME="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    mv "$FILE" "$DIR/$NEW_NAME"
    echo "✨ [Renamed] -> $NEW_NAME"
else
    echo "🔹 [Info] Filename pattern did not match, keeping original."
fi

echo "---------------------------------------------------"
EOF

# Make helper executable
chmod +x "$HELPER_SCRIPT"

# 3. Start Download Loop
echo "🚀 Starting Download..."

while IFS= read -r url || [ -n "$url" ]; do
    # Skip empty lines
    if [[ -z "$url" ]]; then continue; fi
    
    echo "⬇️  Downloading Playlist: $url"

    # Run yt-dlp
    # Note: --exec passes the filepath to our helper script
    yt-dlp \
    --cookies-from-browser firefox \
    --paths "$OUTPUT_DIR" \
    -f "bv+ba/b" \
    --write-subs --write-auto-sub \
    --sub-lang "ai-zh,ai-en" \
    --convert-subs srt \
    --embed-subs \
    --merge-output-format mkv \
    -o "%(playlist_index)03d - %(title).100s.%(ext)s" \
    --restrict-filenames \
    --exec "./$HELPER_SCRIPT {}" \
    "$url"

done < "$URLS_FILE"

# 4. Cleanup
rm -f "$HELPER_SCRIPT"
echo "🎉 All tasks completed successfully!"
