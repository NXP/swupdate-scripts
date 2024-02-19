#!/bin/bash
#
# Copyright 2022-2023 NXP
# All rights reserved.
#
# SPDX-License-Identifier: BSD-3-Clause

SIGN_PEM_FILE=""
SIGN_FLAG=false
WRK_DIR="$(pwd)"
OUTPUT_IMAGE_NAME=""
COPY_MODE="singlecopy"
STORAGE_EMMC_FLAG=false
STORAGE_DEVICE="sd"
PT_SIZE=''
COMPRESS_FLAG=false

function print_help()
{
	echo "$0 - generate update image"
	echo "-o specify output image name. Current default is <SOC_NAME>_<CONTAINER_VER>_<slot>_<BSP_VER>_<COPY_MODE>_<STORAGE_DEVICE>_<date>".
	echo "-d enable double slot copy. default is single slot copy."
	echo "-e enable emmc. default is sd."
	echo "-s Specify public key file for sign image generation."
	echo "-b soc name. Currently, imx93, imx8mm and imx6ull are supported."
	echo "-g Compress image with gzip. Note that if installed-directly = true; is not specified in sw-description, compressed package need to be decompressed in RAM. Make sure ram is enough to hold the image."
	echo "-h print this help."
}

while getopts "s:o:b:degh" arg; do
	case $arg in
		s)
			SIGN_PEM_FILE=$OPTARG
			SIGN_FLAG=true
			;;
		o)
			OUTPUT_IMAGE_NAME=$OPTARG
			;;
		d)
			COPY_MODE="doublecopy"
			;;
		e)
			STORAGE_EMMC_FLAG=true
			STORAGE_DEVICE="emmc"
			;;
		b)
			SOC=$OPTARG
			;;
		g)
			COMPRESS_FLAG=true
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

SOC_ASSEMBLE_SETTING_FILE="cfg_${SOC}_update_image.cfg"
source ${WRK_DIR}/../boards/${SOC_ASSEMBLE_SETTING_FILE}

if [[ -z "${OUTPUT_IMAGE_NAME}" ]]; then
	if [ x"$SIGN_FLAG" == x"true" ]; then
		OUTPUT_IMAGE_NAME=${SOC_NAME}_${UPDATE_CONTAINER_VER}_${UPDATE_BSP_VER}_${COPY_MODE}_${STORAGE_DEVICE}_image_${CUR_DATE}_sign.swu
	else
		OUTPUT_IMAGE_NAME=${SOC_NAME}_${UPDATE_CONTAINER_VER}_${UPDATE_BSP_VER}_${COPY_MODE}_${STORAGE_DEVICE}_image_${CUR_DATE}_nosign.swu
	fi
fi

echo -n ">>>> Check slot_update link..."
if test ! -d ${WRK_DIR}/slot_update; then
	echo "ERROR: need to link slot_update to yocto image deploy directory!"
	exit 1
fi
echo "DONE"

# 2. Test if all needed images exist
echo -n ">>>> Testing update images..."
UPDATE_IMAGES_LIST=""
for each_img in ${UPDATE_IMAGES}; do
	img_name=$(echo $each_img | cut -d: -f1)
	img_truncate_size=$(echo $each_img | cut -d: -f2)
	if [ -e ${WRK_DIR}/slot_update/${img_name} ]; then
		cp ${WRK_DIR}/slot_update/${img_name} ${WRK_DIR}/
		if [[ ! -z $img_truncate_size ]]; then
			echo "Truncating ${WRK_DIR}/${img_name} to $img_truncate_size"
			truncate -s $img_truncate_size ${WRK_DIR}/${img_name}
		fi
	fi
	UPDATE_IMAGES_LIST="${img_name} ${UPDATE_IMAGES_LIST}"
	test ! -e "${WRK_DIR}/${img_name}" && echo "${WRK_DIR}/${img_name} not exists!!!" && exit -1;
done
echo "DONE"

# 4. Compress update image files 
if [ x${COMPRESS_FLAG} == xtrue ]; then
	echo ">>>> Compress update images..."
	for each_img in ${UPDATE_IMAGES_LIST}; do
		img_name=$(echo $each_img | cut -d: -f1)
		echo -n "Compressing $img_name..."
		gzip -9kf ${img_name}
		echo "OK"
	done
	echo "DONE"
fi

# 5. Generate sw-description file on images and scripts
echo -n ">>>> Check sw-description file for images..."
generate_sw_desc ${WRK_DIR}/sw-description ${SW_DESCRIPTION_TEMPLATE} ${COMPRESS_FLAG} ${UPDATE_IMAGES_LIST}
echo "DONE"

echo -n ">>>> Check sw-decription file for scripts..."
if [[ -z "${UPDATE_SCRIPTS}" ]]; then
	echo "No post scripts to handle, ignored!"
else
	generate_sw_desc ${WRK_DIR}/sw-description false false ${UPDATE_SCRIPTS}
fi
echo "DONE"

# 6. Check if need to sign image
echo -n ">>>> Check if need a sign image..."
CPIO_FILES_LIST="sw-description"
if [ x"$SIGN_FLAG" == x"true" ]; then
	echo "YES"
	if [[ -z "${SIGN_PEM_FILE}" ]]; then
		echo "Error: please specify a pem file!"
		exit 1
	fi
	CPIO_FILES_LIST="$CPIO_FILES_LIST sw-description.sig"

	echo -n ">>>> Generating signature..."
	#if you use RSA
	if [ x"$SSL_MODE" == "xRSA-PKCS-1.5" ]; then
		openssl dgst -sha256 -sign priv.pem sw-description > sw-description.sig
	elif [ x"$SSL_MODE" == "xRSA-PSS" ]; then
		openssl dgst -sha256 -sign priv.pem -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:-2 sw-description > sw-description.sig
	else
		openssl cms -sign -in sw-description -out sw-description.sig -signer mycert.cert.pem -inkey mycert.key.pem -outform DER -nosmimecap -binary
	fi
	echo "DONE"
else
	echo "NO"
fi

for each_item in $UPDATE_IMAGES_LIST; do
	if [ x${COMPRESS_FLAG} == xtrue ]; then
		CPIO_FILES_LIST="$CPIO_FILES_LIST ${each_item}.gz"
	else
		CPIO_FILES_LIST="$CPIO_FILES_LIST ${each_item}"
	fi
done

for each_item in $UPDATE_SCRIPTS; do
	CPIO_FILES_LIST="$CPIO_FILES_LIST ${each_item}"
done

# 8. assemble cpio package.
echo ">>>> Creating CPIO package..."
echo $CPIO_FILES_LIST
for each_item in $CPIO_FILES_LIST; do
	echo ${each_item}
done | cpio -ov -H crc > $OUTPUT_IMAGE_NAME
echo "DONE"

echo "==========================================================================="
echo "Create update image $OUTPUT_IMAGE_NAME successfully"
echo "==========================================================================="

