#!/bin/bash
# Script to create the index page

set -e
set -x

outdir="$( cd "$( dirname "$0" )" && pwd )";

cat  > ${outdir}/index.html <<HTML
<!DOCTYPE html>
<html class="no-js">
    <head>
        <meta charset="utf-8">
        <title>CSPlib Pull Requests Builds</title>
    </head>
    <body>
        <ul>
HTML


for name in $(find . -maxdepth 1 -type d \( !  -name .git \)); do
	echo "            <li> <a href='${name}'/>${name}</li>" >> ${outdir}/index.html
done


cat  >> ${outdir}/index.html <<HTML
        </ul>
    </body>
</html>
HTML

set +x