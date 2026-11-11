#!/bin/bash
set -e

current_version=$(sed -n 's/.*<version>\([0-9][0-9]*\)<\/version>.*/\1/p' driver.xml)
if [ -z "$current_version" ]; then
	echo "Could not find a numeric <version> in driver.xml" >&2
	exit 1
fi

next_version=$((current_version + 1))
modified=$(date '+%-m/%-d/%Y %-I:%M %p')
sed -E "s#<modified>[^<]*</modified>#<modified>${modified}</modified>#; s#<version>[0-9]+</version>#<version>${next_version}</version>#" driver.xml > driver.xml.tmp
mv driver.xml.tmp driver.xml

rm -f c4_wol.c4z
zip c4_wol.c4z driver.xml driver.lua