#!/bin/bash

# Exit on any error
set -e

# Navigate to the correct directory
cd "$(dirname "$0")"

# Check if required files exist
if [ ! -f driver.lua ] || [ ! -f driver.xml ]; then
    echo "Error: driver.lua and/or driver.xml not found"
    exit 1
fi

# Remove existing zip/c4z if they exist
rm -f AndriodRemote.zip AndriodRemote.c4z

# Create zip file (-j = junk paths)
zip -r AndriodRemote.zip driver.lua driver.xml drivers-common-public/

# Rename to .c4z
mv AndriodRemote.zip AndriodRemote.c4z

echo "Created AndriodRemote.c4z successfully"