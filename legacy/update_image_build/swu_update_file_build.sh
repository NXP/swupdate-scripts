#!/bin/bash

SIGN_PEM_FILE=""
SIGN_FLAG=false
WRK_DIR="$(pwd)"
OUTPUT_IMAGE_NAME=""
DOUBLESLOT_FLAG=false
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
	echo "-b soc name. Currently, imx8mm and imx6ull are supported."
	echo "-h print this help."
}

while getopts "s:o:b:deh" arg; do
	case $arg in
		s)
			SIGN_PEM_FILE=$OPTARG
			SIGN_FLAG=true
			;;
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

SOC_ASSEMBLE_SETTING_FILE="cfg_${SOC}_update_file.cfg"
source ${WRK_DIR}/../boards/${SOC_ASSEMBLE_SETTING_FILE}

if [ -z "${OUTPUT_IMAGE_NAME}" ]; then
	if [ x"$SIGN_FLAG" == x"true" ]; then
		OUTPUT_IMAGE_NAME=${SOC_NAME}_${UPDATE_CONTAINER_VER}_${UPDATE_BSP_VER}_${COPY_MODE}_${STORAGE_DEVICE}_file_${CUR_DATE}_sign.swu
	else
		OUTPUT_IMAGE_NAME=${SOC_NAME}_${UPDATE_CONTAINER_VER}_${UPDATE_BSP_VER}_${COPY_MODE}_${STORAGE_DEVICE}_file_${CUR_DATE}_nosign.swu
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
for each_img in ${UPDATE_IMAGES}; do
	if [ -e ${WRK_DIR}/slot_update/${each_img} ]; then
		cp ${WRK_DIR}/slot_update/${each_img} ${WRK_DIR}/
	fi
	test ! -e "${WRK_DIR}/${each_img}" && echo "${WRK_DIR}/${each_img} not exists!!!" && exit -1;
done
echo "DONE"

# 5. Generate sw-decription file
echo -n ">>>> Check sw-decription file..."
generate_sw_desc ${WRK_DIR}/sw-description $SW_DESCRIPTION_TEMPLATE ${COMPRESS_FLAG} $UPDATE_IMAGES
echo "DONE"

# 6. Check if need to sign image
echo -n ">>>> Check if need a sign image..."
UPDATE_FILES="sw-description"
if [ x"$SIGN_FLAG" == x"true" ]; then
	echo "YES"
	if [ -z "${SIGN_PEM_FILE}" ]; then
		echo "Error: please specify a pem file!"
		exit 1
	fi
	UPDATE_FILES="$UPDATE_FILES sw-description.sig"

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

for each_item in $UPDATE_IMAGES; do
	if [ x${COMPRESS_FLAG} == xtrue ]; then
		UPDATE_FILES="$UPDATE_FILES ${each_item}.gz"
	else
		UPDATE_FILES="$UPDATE_FILES ${each_item}"
	fi
done

# 8. assemble cpio package.
echo ">>>> Creating CPIO package..."
echo $UPDATE_FILES
for each_item in $UPDATE_FILES; do
	echo ${each_item}
done | cpio -ov -H crc > $OUTPUT_IMAGE_NAME
echo "DONE"

echo "==========================================================================="
echo "Create update image $OUTPUT_IMAGE_NAME successfully"
echo "==========================================================================="

