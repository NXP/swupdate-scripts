#!/bin/bash

WRK_DIR="$(pwd)"
OUTPUT_IMAGE_NAME=""
IMG_SIZE=''
IMG_FS_FMT=''
FILES_DIR=''
SUPPORTED_IMG_FS_FMT="
vfat
ext2
ext3
ext4
"

function print_help()
{
	echo "$0 - generate partition mirror image"
	echo "-o specify output image name."
	echo "-d directory that contains image files. These files will be copied into the image."
	echo "-s image size. The size will be passed to truncate command directly."
	echo "   The size argument is an integer and optional unit."
	echo "For example: 10K is 10*1024. Units are K,M,G,T,P,E,Z,Y, powers of 1024 or KB,MB,... powers of 1000."
	echo "-f image filesystem format. vfat, ext2, ext3 and ext4 are supported."
	echo "-h print this help."
}

function check_valide_fs_fmt()
{
	local fs_fmt=$1

	if [ -z "${fs_fmt}" ]; then
		echo "No filesystem format specified!"
		exit 1
	else
		VALID_FS_FLAG=false
		for each_item in $SUPPORTED_IMG_FS_FMT; do
			if [ x${each_item} == x${fs_fmt} ]; then
				VALID_FS_FLAG=true
			fi
		done
		if [ x${VALID_FS_FLAG} == x"${false}" ]; then
			echo "Not supported SoC: ${fs_fmt}"
			exit 1
		fi
	fi

	return 0
}

while getopts "s:o:d:f:h" arg; do
	case $arg in
		s)
			IMG_SIZE=$OPTARG
			;;
		o)
			OUTPUT_IMAGE_NAME=$OPTARG
			;;
		d)
			FILES_DIR=$OPTARG
			;;
		f)
			IMG_FS_FMT=$OPTARG
			;;
		h)
			print_help
			exit 0
			;;
		?)
			echo "Error: unkonw argument!"
			exit 1
			;;
	esac
done

source ${WRK_DIR}/../utils/utils.sh
source ${WRK_DIR}/../boards/cfg_boards.cfg

echo -n ">>>> Check parameters..."
if [ -z "${OUTPUT_IMAGE_NAME}" ]; then
	echo "ERROR: need to specify an output image name!"
	exit 1
fi

if [ -z "${IMG_SIZE}" ]; then
	echo "ERROR: need to specify mirror image size!"
	exit 1
fi

if [ -z "${IMG_FS_FMT}" ]; then
	echo "ERROR: need to specify filesystem on mirror image size!"
	exit 1
fi
echo "DONE"

echo -n ">>>> Check files directory..."
if [ -z "${FILES_DIR}" ]; then
	echo "WARNING: No files directory specified! An empty partition mirror will be created!"
else
	if [ ! -d "${FILES_DIR}" ]; then
		echo "Error: files directory can't be found!"
		exit 0
	fi
fi
echo "DONE"

echo -n ">>>> Check filesystem format..."
check_valide_fs_fmt ${IMG_FS_FMT}
if [ $? != 0 ]; then
	echo "Not a supported filesystem format!"
	exit 1
fi
echo "DONE"

# 1. Copy images to boot partition
echo -n ">>>> Create mirror image..."
truncate -s ${IMG_SIZE} ${OUTPUT_IMAGE_NAME}
if [ $? != 0 ]; then
	echo "truncate to ${IMG_SIZE} on ${OUTPUT_IMAGE_NAME} failed!"
	exit 1
fi
echo "DONE"

case ${IMG_FS_FMT} in
	vfat)
		mkfs.vfat ${OUTPUT_IMAGE_NAME}
		if [ $? != 0 ]; then
			echo "mkfs.vfat failed!"
			exit 1
		fi

		if [ ! -z "${FILES_DIR}" ]; then
			mcopy -i ${OUTPUT_IMAGE_NAME} -s ${FILES_DIR}/* ::/
			mdir -i ${OUTPUT_IMAGE_NAME}
		fi
		;;
	ext2|ext3|ext4)
		if [ -z "${FILES_DIR}" ]; then
			mke2fs -t ${IMG_FS_FMT} -F -i 4096 -U time ${OUTPUT_IMAGE_NAME}
		else
			mke2fs -t ${IMG_FS_FMT} -F -i 4096 -U time ${OUTPUT_IMAGE_NAME} -d ${FILES_DIR}
		fi
		if [ $? != 0 ]; then
			echo "mke2fs execute failed!"
			exit 1
		fi
		e2fsck -f ${OUTPUT_IMAGE_NAME}
		resize2fs ${OUTPUT_IMAGE_NAME}
		;;
	?)
		echo "Unsupported filesystem type!"
		exit 1
		;;
esac

echo "==========================================================================="
echo "Create mirror partition image $OUTPUT_IMAGE_NAME successfully"
echo "==========================================================================="

