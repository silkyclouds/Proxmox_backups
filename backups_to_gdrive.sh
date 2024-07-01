#!/bin/bash

# Configurations
LOCAL_DIR="/path/to/local/backup/directory"
REMOTE_DIR="remote:Backups/proxmox/"
BACKUP_LIMIT_DAYS=30  # Number of days to keep
WEBHOOK_URL="https://discord.com/api/webhooks/your-webhook-id/your-webhook-token"

# Start time
START_TIME=$(date +%s)
TODAY=$(date +%d-%m-%Y)
REMOTE_SUBDIR="${REMOTE_DIR}${TODAY}/"

# Send start notification to Discord
START_MESSAGE="Backup process started for $TODAY"
curl -H "Content-Type: application/json" -X POST -d "{\"content\": \"$START_MESSAGE\"}" $WEBHOOK_URL

# Create today's directory on Google Drive
rclone mkdir "$REMOTE_SUBDIR"

# Find files created today and ending with .zst
FILES=$(find "$LOCAL_DIR" -type f -name "*.zst" -mtime -1)

# Initialize variables for the notification
UPLOAD_COUNT=0
UPLOAD_SIZE=0

# Upload files to Google Drive
for FILE in $FILES; do
  FILE_NAME=$(basename "$FILE")
  LOCAL_FILE_SIZE=$(stat -c%s "$FILE")
  REMOTE_FILE_SIZE=$(rclone lsjson "$REMOTE_SUBDIR$FILE_NAME" 2>/dev/null | jq -r '.[0].Size' 2>/dev/null)
  
  if [[ "$LOCAL_FILE_SIZE" -eq "$REMOTE_FILE_SIZE" ]]; then
    echo "Skipping upload for $FILE_NAME, already exists with same size."
  else
    echo "Uploading $FILE_NAME to $REMOTE_SUBDIR..."
    rclone copy "$FILE" "$REMOTE_SUBDIR" --progress
    if [ $? -eq 0 ]; then
      UPLOAD_SIZE=$((UPLOAD_SIZE + LOCAL_FILE_SIZE))
      UPLOAD_COUNT=$((UPLOAD_COUNT + 1))
      UPLOAD_SIZE_HR=$(numfmt --to=iec --suffix=B $LOCAL_FILE_SIZE)
      DURATION=$((($(date +%s) - START_TIME) / 60))
      
      # Send notification to Discord for each file uploaded
      FILE_MESSAGE="Uploaded $FILE_NAME - Size: $UPLOAD_SIZE_HR - Duration: $DURATION minutes"
      curl -H "Content-Type: application/json" -X POST -d "{\"content\": \"$FILE_MESSAGE\"}" $WEBHOOK_URL
    fi
  fi
done

# Convert total upload size to human-readable format
UPLOAD_SIZE_HR=$(numfmt --to=iec --suffix=B $UPLOAD_SIZE)

# List directories on Google Drive and delete those older than BACKUP_LIMIT_DAYS
OLD_DIRS=$(rclone lsf "$REMOTE_DIR" --dirs-only --format "p" | while read -r dir; do
  DIR_DATE=$(date -d "$(basename "$dir")" +%s 2>/dev/null || echo "")
  if [[ -n "$DIR_DATE" && $((($(date +%s) - DIR_DATE) / 86400)) -gt "$BACKUP_LIMIT_DAYS" ]]; then
    echo "$dir"
  fi
done)

for DIR in $OLD_DIRS; do
  echo "Deleting old directory $DIR..."
  rclone purge "$REMOTE_DIR$DIR"
done

# End time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Send summary notification to Discord
SUMMARY_MESSAGE="Backup process completed. - Uploaded backups: $UPLOAD_COUNT - Total upload size: $UPLOAD_SIZE_HR - Duration: $(($DURATION / 60)) minutes and $(($DURATION % 60)) seconds - Removed old directories: $(echo "$OLD_DIRS" | wc -w)"

curl -H "Content-Type: application/json" -X POST -d "{\"content\": \"$SUMMARY_MESSAGE\"}" $WEBHOOK_URL

echo "Backup process completed and notification sent."
