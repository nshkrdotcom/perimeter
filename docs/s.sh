#!/bin/bash

# ==============================================================================
# replace_perimeter.sh
#
# This script performs a search and replace for "perimeter" -> "perimeter"
# within all files in the current directory and its subdirectories.
# It handles singular, plural, and capitalized variations.
#
# It also renames any files or directories containing "perimeter" in their name.
#
# USAGE:
# 1. Place this script in the root directory of your project.
# 2. Give it execute permissions: chmod +x replace_perimeter.sh
# 3. Run it: ./replace_perimeter.sh
#
# WARNING:
# This script modifies files in-place and renames them.
# It is HIGHLY recommended to commit your changes to git or create a backup
# before running it.
# ==============================================================================

# --- Part 1: Replace content inside files ---

echo "STEP 1: Replacing content within files..."

# Find all regular files and use sed to replace the strings.
# The `find` command with `-print0` and `xargs -0` correctly handles filenames
# with spaces or special characters.
#
# The order of the -e expressions for sed is IMPORTANT. We must replace the
# longer strings (plural) before the shorter strings (singular) to avoid errors
# like "perimeters" becoming "perimeteries".
#
# Note: The `-i ''` syntax for sed is for BSD/macOS compatibility.
# On GNU/Linux, you can just use `-i`.
find . -type f -print0 | xargs -0 sed -i '' \
  -e 's/Perimeters/Perimeters/g' \
  -e 's/perimeters/perimeters/g' \
  -e 's/Perimeter/Perimeter/g' \
  -e 's/perimeter/perimeter/g'

echo "Content replacement complete."
echo "---"

# --- Part 2: Rename files and directories ---

echo "STEP 2: Renaming files and directories..."

# Find all files and directories containing 'perimeter' in their name (case-insensitive).
# The `-depth` option is crucial: it processes the contents of a directory
# before the directory itself. This prevents errors if a parent directory is
# renamed before its children are processed.
find . -depth -iname '*perimeter*' | while read -r old_path; do
  # Skip the script itself
  if [[ "$old_path" == "./replace_perimeter.sh" ]]; then
    continue
  fi

  # Construct the new path by replacing the variations of 'perimeter'
  # We use a pipeline of sed commands for simplicity, again ordered from longest to shortest match.
  new_path=$(echo "$old_path" | sed 's/Perimeters/Perimeters/g' | sed 's/perimeters/perimeters/g' | sed 's/Perimeter/Perimeter/g' | sed 's/perimeter/perimeter/g')

  # Only attempt to move if the name has actually changed
  if [[ "$old_path" != "$new_path" ]]; then
    # Create the parent directory for the new path if it doesn't exist
    # This handles cases where a directory rename hasn't been processed yet.
    mkdir -p "$(dirname "$new_path")"
    
    # Move the file/directory and print a message
    mv -v "$old_path" "$new_path"
  fi
done

echo "File and directory renaming complete."
echo "---"
echo "All operations finished!"

