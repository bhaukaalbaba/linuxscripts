#!/bin/bash

#
# Script to process and manage log files
#

# Variables
rawlogs_dir="/natdrive/rawlogs/natlogs/"
processed_dir="/natdrive/processed/natlogs/"
s3_bucket="s3://natlogb1/"
s3_bucket_name="natlogb1"
logfile="/root/logscript/logfile_$(date +'%Y_%m_%d').log"
stale_days=7

# Email variables
TO="person1@domain.com,person2@domain.com"
FROM="alerts@domain.com"

# Log the start of the script
echo "$(date) - Script started." >> "$logfile"

# Get the current hour
current_hour=$(date +'%Y/%m/%d %H')

# Function to compress and move files
compress_and_move() {
  # Compresses the given file and moves it to the target directory.

  local file="$1"
  local target_dir="$2"

  gzip -9 "$file"
  mkdir -p "$target_dir" && mv "${file}.gz" "$target_dir" && echo "$(date) - Compressed and moved: $file" >> "$logfile" || echo "$(date) - Compression or move failed: $file" >> "$logfile"
}

# Find all files older than the current hour in rawlogs_dir and compress and move them to processed_dir
filelist=$(find "$rawlogs_dir" -type f -name '*.log' ! -newermt "$current_hour")

# If no files are found, exit the script
if [ -z "$filelist" ]; then
  echo "$(date) - No files found for processing." >> "$logfile"
  exit 1
fi

# Compress and move each file
for file in $filelist; do
  compress_and_move "$file" "$processed_dir$(dirname "${file#$rawlogs_dir}")"
done

# Sync all .gz files from processed_dir to S3
aws s3 sync --include "*.gz" --storage-class INTELLIGENT_TIERING --size-only "$processed_dir" "$s3_bucket" && echo "$(date) - Synced .gz files: $filelist" >> "$logfile" || (echo "$(date) - Sync to S3 failed: $filelist" >> "$logfile" && aws ses send-email --from "$FROM" --to "$TO" --subject "[Log file failed to sync to S3 bucket]" --text "Sync to S3 failed for: $filelist")

# Check for stale files in processed_dir
for file in $(find "$processed_dir" -type f); do
  # Get the Content-MD5 from S3
  s3_md5=$(aws s3api head-object --bucket "$s3_bucket_name" --key "${file#$processed_dir}" --query ContentMD5 --output text)

  # Calculate the MD5 checksum of the local file
  local_checksum=$(md5sum "$file" | awk '{ print $1 }' | base64)

  if [[ "$s3_md5" == "$local_checksum" ]] && [[ $(find "$file" -mtime +$stale_days) ]]; then
    # The file exists in both local and S3 and is older than 7 days, so delete it from local storage.
    rm "$file" && echo "$(date) - Deleted stale file: $file" >> "$logfile"
  elif [[ "$s3_md5" != "$local_checksum" ]]; then
    # The checksums don't match, so send an email alert.
    echo "$(date) - Checksum mismatch, not deleting: $file" >> "$logfile"
    aws ses send-email --from "$FROM" --to "$TO" --subject "[Remnant log file upload to s3 failed]" --text "Checksum mismatch for: $file"
  fi
done

# Delete empty folders in processed_dir and rawlogs_dir
find "$processed_dir" "$rawlogs_dir" -type d -empty -exec rm -d {} \;

# Log the end of the script
echo "$(date) - Script execution completed." >> "$logfile"
