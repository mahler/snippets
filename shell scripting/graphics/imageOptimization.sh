#!/bin/sh
#
# Optimzies (as in minimizing the size) all PNG and JPEG images recursively in a directory structure.
# This may be helpful when builk optimizing uploaded wordpress images from the command line.

set -o errexit

if [ `command -v optipng` ]; then
        echo "ok"
else
        echo "optipng missing. please install and try again."
        # 127 - "command not found"
        exit 127
fi

if [ `command -v jpegtran` ]; then
        echo "ok"
else
        echo "jpegtran missing. please install and try again."
        # 127 - "command not found"
        exit 127
fi

 
PNGS=`find . -iname "*.png"`
 
echo "Optimizing PNG"
for PNG in ${PNGS}
do
	PRESIZE=`stat -c %s ${PNG}`
	echo -n "	${PNG}: ${PRESIZE} "
	optipng -o5 -quiet -preserve ${PNG}
 
	POSTSIZE=`stat -c %s ${PNG}`
	if [ "$AFTER" -lt "$PRESIZE" ]; then
		echo "--> ${POSTSIZE}"
	else
		echo "(Already optimal)"
	fi
done
JPGS=`find . -iname "*.jpg"`
 
echo "Optimizing JPG"
for JPG in ${JPGS}
do
	PRESIZE=`stat -c %s ${JPG}`
	echo -n "	${JPG}: ${PRESIZE} "
	jpegtran -optimize -progressive -outfile ${JPG} ${JPG}
	POSTSIZE=`stat -c %s ${JPG}`
 
	if [ "$POSTSIZE" -lt "$PRESIZE" ]; then
		echo "--> ${POSTSIZE}"
	else
		echo "(Already optimal)"
	fi
done

