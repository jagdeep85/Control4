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
rm -f android_app.zip android_app.c4z

# Create zip file (-j = junk paths)
zip -r android_app.zip driver.lua driver.xml www

# Rename to .c4z
mv android_app.zip android_app.c4z

echo "Created android_app.c4z successfully"