#!/usr/bin/bash

function print_help()
{
	echo "$0 - generate update image"
	echo "-o specify output image name. Default is swu_<SLOT>_rescue_<soc>_<storage>_<date>.sdcard"
	echo "-d enable double slot copy. Default is single slot copy."
	echo "-e enable emmc. Default is sd."
	echo "-b soc name. Currently, imx93, imx8mm and imx6ull are supported."
	echo "-m Only regenerate or overwrite MBR. This option can be used to generate MBR individually."
	echo "   Suppose that we don't need to generate MBR every time. Normally we only need to generate it once."
	echo "-h print this help."
}

WRK_DIR="$(pwd)"
TMP_BIN_FILE="./tmp.bin"

OUTPUT_IMAGE_NAME=""
DOUBLESLOT_FLAG=false
COPY_MODE="singlecopy"
STORAGE_EMMC_FLAG=false
STORAGE_DEVICE="sd"
PT_SIZE=''
GENERATE_MBR_ONLY_FLAG=false

while getopts "o:deb:mh" arg; do
	case $arg in
		o)
			OUTPUT_IMAGE_NAME=$OPTARG
			;;
		d)
			DOUBLESLOT_FLAG=true
			COPY_MODE="doublecopy"
			;;
		e)
			STORAGE_EMMC_FLAG=true
			STORAGE_DEVICE="emmc"
			;;
		b)
			SOC=$OPTARG
			;;
		m)
			GENERATE_MBR_ONLY_FLAG=true
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

check_valid_boards $SOC

SOC_ASSEMBLE_SETTING_FILE="cfg_${SOC}_base.cfg"
source ${WRK_DIR}/../boards/${SOC_ASSEMBLE_SETTING_FILE}

if [[ -z "${OUTPUT_IMAGE_NAME}" ]]; then
	echo "No output image name specified! Use default name!"
	OUTPUT_IMAGE_NAME=swu_${COPY_MODE}_rescue_${SOC_NAME}_${STORAGE_DEVICE}_${CUR_DATE}.sdcard
fi
echo "Output image name is: $OUTPUT_IMAGE_NAME"
if test -e ./$OUTPUT_IMAGE_NAME; then
	echo -n "Delete existing $OUTPUT_IMAGE_NAME..."
	rm ./$OUTPUT_IMAGE_NAME
	echo "DONE"
fi

echo -n ">>>> Check partition table file..."
IMAGE_PT_TBL_SIZE=$(echo ${IMAGE_PT_TBL} | cut -d: -f3)
PT_FILENAME=$(basename ${IMAGE_PT_TBL_PATH})
PT_FILEDIR=$(dirname ${IMAGE_PT_TBL_PATH})
if [ x$GENERATE_PT_TBL_ONLY_FLAG == xtrue ]; then
	echo ">>>> Regenerate or overwrite partition table..."
	if [ -e ${IMAGE_PT_TBL_PATH} ]; then
		echo "Delete existed partition table ${IMAGE_PT_TBL_PATH}"
		rm ${IMAGE_PT_TBL_PATH}
	fi
	echo "Generating ${IMAGE_PT_TBL_PATH}"
	cd $PT_FILEDIR
	generate_pt_tbl_dualslot $PT_FILENAME $IMAGE_PT_SIZE $IMAGE_PT_TBL_FMT
	cd -
	echo "DONE"
	exit 0
else
	if [ ! -e ${IMAGE_PT_TBL_PATH} ]; then
		echo -n "\nNo partition table file, will generate ..."
		cd $PT_FILEDIR
		generate_pt_tbl_dualslot $PT_FILENAME $IMAGE_PT_TBL_SIZE $IMAGE_PT_TBL_FMT
		cd -
	fi
fi
echo "DONE"

echo -n ">>>> Check slota boot partition mirror..."
BOOT_PT=$(echo $SLOTA_BOOT_PT | cut -d: -f1)
if [[ -z ${BOOT_PT} ]]; then
	echo "No slotA boot part, ignored!"
else
	if [ ! -e ${BOOT_PT} ]; then
		echo ""
		echo -n "No slota boot partition mirror, generate..."
		cd $BOOT_PT_DIR
		calculate_pt_size $SLOTA_BOOT_PT PT_SIZE
		truncate -s ${PT_SIZE} ${BOOT_PT}
		cd -
	fi
fi
echo "DONE"

echo -n ">>>> Check slotb boot partition mirror..."
BOOT_PT=$(echo $SLOTB_BOOT_PT | cut -d: -f1)
if [[ -z ${BOOT_PT} ]]; then
	echo "No slotB boot part, ignored!"
else
	if [ ! -e ${BOOT_PT} ]; then
		echo ""
		echo -n "\nNo slotb boot partition mirror, generate..."
		calculate_pt_size $SLOTB_BOOT_PT PT_SIZE
		truncate -s ${PT_SIZE} ${BOOT_PT}
	fi
fi
echo "DONE"

echo -n ">>>> Check slota link..."
if test ! -d ${WRK_DIR}/slota; then
	echo "ERROR: need to link slota to yocto image deploy directory!"
	exit 1
fi
echo "DONE"

echo -n ">>>> Check slotb link..."
if test ! -d ${WRK_DIR}/slotb; then
	echo "ERROR: need to link slotb to yocto image deploy directory!"
	exit 1
fi
echo "DONE"

# assemble images
touch $OUTPUT_IMAGE_NAME

# 1. assemble header
echo ">>>> Making header..."
if [[ -z $IMAGES_HEADER ]]; then
	echo "NULL header, ignored!"
else
	for each_item in $IMAGES_HEADER; do
		img_file=$(echo $each_item | cut -d: -f1)
		pad_start=$(echo $each_item | cut -d: -f2)
		pad_end=$(echo $each_item | cut -d: -f3)
		touch $TMP_BIN_FILE
		generate_padding_file $pad_start $img_file $pad_end $TMP_BIN_FILE
		if [ $? != 0 ]; then
			rm -f $TMP_BIN_FILE
			exit 1
		fi
		cat $TMP_BIN_FILE >> $OUTPUT_IMAGE_NAME
		rm -f $TMP_BIN_FILE
	done
fi
echo "DONE"

# 2. assemble swupdate
echo ">>>> Making swupdate..."
if [[ -z $IMAGES_SWUPDATE ]]; then
	echo "NULL swupdate ramdisk images, Ignored!"
else
	for each_item in $IMAGES_SWUPDATE; do
		img_file=$(echo $each_item | cut -d: -f1)
		pad_start=$(echo $each_item | cut -d: -f2)
		pad_end=$(echo $each_item | cut -d: -f3)
		touch $TMP_BIN_FILE
		generate_padding_file $pad_start $img_file $pad_end $TMP_BIN_FILE
		if [ $? != 0 ]; then
			rm -f $TMP_BIN_FILE
			exit 1
		fi
		cat $TMP_BIN_FILE >> $OUTPUT_IMAGE_NAME
		rm -f $TMP_BIN_FILE
	done
fi
echo "DONE"

# 3. assemble slota
echo ">>>> Making slota..."
if [[ -z $SLOTA_BOOT_PT_FILES ]]; then
	echo "No slotA files to copy to boot part, ignored!"
else
	BOOT_PT_PATH=$(echo $SLOTA_BOOT_PT | cut -d: -f1)
	copy_images_to_boot_pt $BOOT_PT_PATH slota
fi
if [[ -z $SLOTA_ROOTFS ]]; then
	echo "No slotA rootfs, ignored!"
else
	ROOTFS_IMG=$(echo $SLOTA_ROOTFS | cut -d: -f1)
	if [ ! -e $ROOTFS_IMG ]; then
		echo "SLOTA ROOTFS image not found!"
		exit -1
	fi
	calculate_pt_size $SLOTA_ROOTFS PT_SIZE
	truncate -s $PT_SIZE $ROOTFS_IMG
	e2fsck -f $ROOTFS_IMG
	resize2fs $ROOTFS_IMG
	for each_item in $SLOTA_IMAGES; do
		item_path=$(echo $each_item | cut -d: -f1)
		cat $item_path >> $OUTPUT_IMAGE_NAME
	done
fi
echo "DONE"

# 4. assemble slotb
if [ x$DOUBLESLOT_FLAG == x"true" ]; then
	echo ">>>> Making slotb..."
	if [[ -z $SLOTA_BOOT_PT_FILES ]]; then
		echo "No slotB files to copy to boot part, ignored!"
	else
		BOOT_PT_PATH=$(echo $SLOTB_BOOT_PT | cut -d: -f1)
		copy_images_to_boot_pt $BOOT_PT_PATH slotb
	fi
	if [[ -z $SLOTB_ROOTFS ]]; then
		echo "No slotB rootfs, ignored!"
	else
		ROOTFS_IMG=$(echo $SLOTB_ROOTFS | cut -d: -f1)
		if [ ! -e $ROOTFS_IMG ]; then
			echo "SLOTB ROOTFS image not found!"
			exit -1
		fi
		calculate_pt_size $SLOTB_ROOTFS PT_SIZE
		truncate -s $PT_SIZE $ROOTFS_IMG
		e2fsck -f $ROOTFS_IMG
		resize2fs $ROOTFS_IMG
		for each_item in $SLOTB_IMAGES; do
			item_path=$(echo $each_item | cut -d: -f1)
			cat $item_path >> $OUTPUT_IMAGE_NAME
		done
		echo "DONE"
	fi
fi

# 5. Check image map
echo "Checking partition image ..."
if [[ -z $IMAGE_PT_TBL_IMAGES ]]; then
	echo "No extra image map found, ignored!"
else
	echo "Find partition images, will program these images to disk partitions!"
	# Validate images
	for each_item in $IMAGE_PT_TBL_IMAGES; do
		pt_image_path=$(echo $each_item | cut -d: -f2)
		pt_image_offset=$(echo $each_item | cut -d: -f3)
		if [ ! -e $pt_image_path ]; then
			echo "Can't find $pt_image_path to dd!"
			exit -1
		fi
		if [[ -z $pt_image_offset ]]; then
			echo "Offset not found for $pt_image_path!"
			exit -1
		fi
	done
	cp $IMAGE_PT_TBL_PATH $OUTPUT_IMAGE_NAME
	for each_item in $IMAGE_PT_TBL_IMAGES; do
		pt_img_path=$(echo $each_item | cut -d: -f2)
		pad_start=$(echo $each_item | cut -d: -f3)
		pad_end=$(echo $each_item | cut -d: -f4)
		touch $TMP_BIN_FILE
		generate_padding_file $pad_start $img_file $pad_end $TMP_BIN_FILE
		if [ $? != 0 ]; then
			rm -f $TMP_BIN_FILE
			exit 1
		fi
		cat $TMP_BIN_FILE >> $OUTPUT_IMAGE_NAME
		rm -f $TMP_BIN_FILE
	done
fi
echo "DONE"

# 6. Check image tail for GPT
echo "Checking image tail for GPT..."
if [ x$IMAGE_PT_TBL_FMT == x"GPT" ]; then
	if [[ -z $IMAGES_TAIL ]]; then
		echo "Error: no image tail found!"
		exit -1
	else
		for each_item in $IMAGES_TAIL; do
			pt_img_path=$(echo $each_item | cut -d: -f1)
			pad_start=$(echo $each_item | cut -d: -f2)
			pad_end=$(echo $each_item | cut -d: -f3)
			touch $TMP_BIN_FILE
			generate_padding_file $pad_start $img_file $pad_end $TMP_BIN_FILE
			cat $TMP_BIN_FILE >> $OUTPUT_IMAGE_NAME
			rm -f $TMP_BIN_FILE
		done
	fi
else
	echo "Not using GPT, ignored!"
fi
echo "DONE"

echo "==========================================================================="
echo "Create base image $OUTPUT_IMAGE_NAME successfully"
echo "==========================================================================="

