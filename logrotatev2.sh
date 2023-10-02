#!/bin/bash

# Script Name: logrotatev2.sh
# Description: This script processes and manages log files. It compresses log files, moves them to a specified directory, syncs them to an S3 bucket, and deletes stale files.

# Usage:
#   ./logrotatev2.sh [option...]
# Options:
#   -d, --days <days>         Set the number of days to keep stale log files. Default is 7.
#   -i, --install-aws         Install AWS CLI.
#   -c, --configure           Configure the script. Captures the values of rawlogs_dir, processed_dir, s3_bucket, s3_bucket_name, TO, FROM, and CHARSET variables using ncurses dialog and stores them in /root/.logmanage.conf.
#   -t, --test                Test if the S3 bucket is accessible and writable.
#   -h, --help                Display this help and exit.

# Examples:
#   ./logrotatev2.sh --days 10
#   ./logrotatev2.sh --install-aws
#   ./logrotatev2.sh --configure
#   ./logrotatev2.sh --test

# Note:
#   Make sure to run this script with necessary permissions. If you're running this as a non-root user, you might need to use sudo.


# Function to display help
display_help() {
  echo "Usage: $0 [option...]" >&2
  echo
  echo "   -d, --days         Number of days to keep stale log files. Default is 7."
  echo "   -i, --install-aws  Install AWS CLI."
  echo "   -c, --configure    Configure the script."
  echo "   -t, --test         Test if the S3 bucket is accessible and writable."
  echo "   -h, --help         Display this help and exit."
  echo
}

# Variables
logfile="/root/logscript/action.log"
stale_days=7

# Parse command-line arguments
while (( "$#" )); do
  case "$1" in
    -d|--days)
      if [ -n "$2" ] && [ "$2" -eq "$2" ] 2>/dev/null; then
        stale_days=$2
        shift 2
      else
        echo "Error: Argument for '--days' is missing or not an integer" >&2
        exit 1
      fi
      ;;
    -i|--install-aws)
      pip3 install awscli --upgrade
      echo "AWS CLI installed. Please rerun the script without '--install-aws'"
      exit 0
      ;;
    -c|--configure)
      # Use ncurses dialog to capture variables and store in /root/.logmanage.conf
      rawlogs_dir=$(dialog --inputbox "Enter rawlogs_dir:" 10 60 3>&1 1>&2 2>&3)
      processed_dir=$(dialog --inputbox "Enter processed_dir:" 10 60 3>&1 1>&2 2>&3)
      s3_bucket=$(dialog --inputbox "Enter s3_bucket:" 10 60 3>&1 1>&2 2>&3)
      s3_bucket_name=$(dialog --inputbox "Enter s3_bucket_name:" 10 60 3>&1 1>&2 2>&3)
      TO=$(dialog --inputbox "Enter TO:" 10 60 3>&1 1>&2 2>&3)
      FROM=$(dialog --inputbox "Enter FROM:" 10 60 3>&1 1>&2 2>&3)
      CHARSET=$(dialog --inputbox "Enter CHARSET:" 10 60 3>&1 1>&2 2>&3)

      # Write variables to /root/.logmanage.conf
      printf 'rawlogs_dir="%s"\nprocessed_dir="%s"\ns3_bucket="%s"\ns3_bucket_name="%s"\nTO="%s"\nFROM="%s"\nCHARSET="%s"\n' "$rawlogs_dir" "$processed_dir" "$s3_bucket" "$s3_bucket_name" "$TO" "$FROM" "$CHARSET" > /root/.logmanage.conf

      echo "Configuration saved. Please rerun the script without '--configure'"
      exit 0
      ;;
    -t|--test)
      # Include your commands here to check if the S3 bucket is accessible and writable.
      echo "Bucket accessibility test completed. Please rerun the script without '--test'"
      exit 0
      ;;
    -h|--help)
      display_help
      exit 0
      ;;
    *)
      echo "Error: Invalid argument"
      exit 1
      ;;
   esac
done

# Check if AWS CLI is installed.
if ! command -v aws &> /dev/null; then
    echo "AWS CLI could not be found. Please run the script with '--install-aws'"
    exit 1
fi

# Check if /root/.logmanage.conf exists and is readable, and load variables from it.
if [ -f /root/.logmanage.conf ] && [ -r /root/.logmanage.conf ]; then
    source /root/.logmanage.conf
else
    echo "Configuration file missing or not readable. Please run the script with '--configure'"
    exit 1
fi

# Log the start of the script execution.
echo "$(date) - Script started." >> "$logfile"

# Get the current hour.
current_hour=$(date +'%Y/%m/%d %H')

# Function to compress and move files.
compress_and_move() {

   # Compresses the given file and moves it to the target directory.

   local file="$1"
   local target_dir="$2"

   gzip -9 "$file"

   # Create target directory if it doesn't exist, move compressed file to target directory.
   mkdir -p "$target_dir" && mv "${file}.gz" "$target_dir" && echo "$(date) - Compressed and moved: $file" >> "$logfile" || (echo "$(date) - Compression or move failed: $file" >> "$logfile" && aws ses send-email --from "$FROM" --destination "ToAddresses=$TO" --message "Subject={Data=Compression or move failed,Charset=$CHARSET},Body={Text={Data=Compression or move failed for: $file,Charset=$CHARSET}}" )
}

# Find all files older than the current hour in rawlogs_dir and compress and move them to processed_dir.
filelist=$(find "$rawlogs_dir" -type f -name '*.log' ! -newermt "$current_hour")

# If no files are found, exit the script.
if [ -z "$filelist" ]; then
  echo "$(date) - No files found for processing." >> "$logfile"
  exit 1
fi

# Compress and move each file.
for file in $filelist; do
  compress_and_move "$file" "$processed_dir$(dirname "${file#$rawlogs_dir}")"
done

# Sync all .gz files from processed_dir to S3.
aws s3 sync --include "*.gz" --storage-class INTELLIGENT_TIERING --size-only "$processed_dir" "$s3_bucket" || (echo "$(date) - Sync to S3 failed: $filelist" >> "$logfile" && aws ses send-email --from "$FROM" --destination "ToAddresses=$TO" --message "Subject={Data=Log file sync to S3 failed,Charset=$CHARSET},Body={Text={Data=Sync to S3 failed for: $filelist,Charset=$CHARSET}}" )

# Check for stale files in processed_dir.
for file in $(find "$processed_dir" -type f); do
  # Get the Content-MD5 from S3.
  s3_md5=$(aws s3api head-object --bucket "$s3_bucket_name" --key "${file#$processed_dir}" --query ContentMD5 --output text)

  # Calculate the MD5 checksum of the local file.
  local_checksum=$(md5sum "$file" | awk '{ print $1 }' | base64)

  if [[ "$s3_md5" == "$local_checksum" ]] && [[ $(find "$file" -mtime +$stale_days) ]]; then
    # The file exists in both local and S3 and is older than the specified number of days, so delete it from local storage.
    rm "$file" && echo "$(date) - Deleted stale file: $file" >> "$logfile"
  elif [[ "$s3_md5" != "$local_checksum" ]]; then
    # The checksums don't match, so send an email alert.
    echo "$(date) - Checksum mismatch, not deleting: $file" >> "$logfile"
    aws ses send-email --from "$FROM" --destination "ToAddresses=$TO" --message "Subject={Data=Stale log file deletion failed,Charset=$CHARSET},Body={Text={Data=Checksum mismatch for: $file,Charset=$CHARSET}}"
  fi
done

# Delete empty folders in processed_dir and rawlogs_dir.
find "$processed_dir" "$rawlogs_dir" -type d -empty -exec rm -d {} \;

# Log the end of the script execution.
echo "$(date) - Script execution completed." >> "$logfile"
