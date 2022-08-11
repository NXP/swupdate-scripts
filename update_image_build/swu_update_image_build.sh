#!/bin/bash

SIGN_PEM_FILE=""
SIGN_FLAG=false
WRK_DIR="$(pwd)"
#CUR_DATE="$(date "+%Y%m%d-%H%M%S")"
CUR_DATE="$(date "+%Y%m%d")"
OUTPUT_IMAGE_NAME=""
DOUBLESLOT_FLAG=false
COPY_MODE="singlecopy"
STORAGE_EMMC_FLAG=false
STORAGE_DEVICE="sd"
SUPPORTED_SOC="
imx8mm
imx6ull
"
SW_DESCP_MANIPU_FLAG=false
PT_SIZE=''

function print_help()
{
	echo "$0 - generate update image"
	echo "-o specify output image name. Current default is <SOC_NAME>_<CONTAINER_VER>_<slot>_<BSP_VER>_<COPY_MODE>_<STORAGE_DEVICE>_<date>".
	echo "-d enable double slot copy. default is single slot copy."
	echo "-e enable emmc. default is sd."
	echo "-s Specify public key file for sign image generation."
	echo "-b soc name. Currently, imx8mm and imx6ull are supported."
	echo "-S Generate software description file."
	echo "   This will use a template to generate software description file."
	echo "   User can also create their own template file."
	echo "-h print this help."
}

while getopts "s:o:b:deSh" arg; do
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
		S)
			SW_DESCP_MANIPU_FLAG=true
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

if [ -z "${SOC}" ]; then
	echo "No SOC specified!"
	exit 1
else
	VALID_SOC_FLAG=false
	for each_item in $SUPPORTED_SOC; do
		if [ x${each_item} == x${SOC} ]; then
			VALID_SOC_FLAG=true
		fi
	done
	if [ x${VALID_SOC_FLAG} == x"${false}" ]; then
		echo "Not supported SoC: ${SOC}"
	fi
fi

SOC_ASSEMBLE_SETTING_FILE="cfg_${SOC}.cfg"
source ${WRK_DIR}/../boards/${SOC_ASSEMBLE_SETTING_FILE}
source ${WRK_DIR}/../utils/utils.sh

if [ -z "${OUTPUT_IMAGE_NAME}" ]; then
	if [ x"$SIGN_FLAG" == x"true" ]; then
		OUTPUT_IMAGE_NAME=${SOC_NAME}_${UPDATE_CONTAINER_VER}_slot${SLOT}_${UPDATE_BSP_VER}_${COPY_MODE}_${STORAGE_DEVICE}_${CUR_DATE}_sign.swu
	else
		OUTPUT_IMAGE_NAME=${SOC_NAME}_${UPDATE_CONTAINER_VER}_slot${SLOT}_${UPDATE_BSP_VER}_${COPY_MODE}_${STORAGE_DEVICE}_${CUR_DATE}_nosign.swu
	fi
fi

echo -n ">>>> Check slot_update link..."
if test ! -d ${WRK_DIR}/slot_update; then
	echo "ERROR: need to link slat_update to yocto image deploy directory!"
	exit 1
fi
echo "DONE"

# 1. Copy images to boot partition
echo -n ">>>> Check update boot partition mirror..."
BOOT_PT=$(echo $UPDATE_BOOT_PT | cut -d: -f1)
if [ ! -e ${BOOT_PT} ]; then
	echo -n "\nNo update boot partition mirror, generate..."
	calculate_pt_size $UPDATE_BOOT_PT PT_SIZE
	truncate -s ${PT_SIZE} ${BOOT_PT}
fi
echo "DONE"

echo -n ">>>> Copying kernel images and dtbs to boot partition..."
copy_images_to_boot_pt $BOOT_PT update
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

# 3. Truncate rootfs
echo -n ">>>> Truncating rootfs..."
ROOTFS_IMG=$(echo $UPDATE_ROOTFS | cut -d: -f1)
if [ ! -e $ROOTFS_IMG ]; then
	echo "ROOTFS image not found!"
	exit -1
fi
calculate_pt_size $UPDATE_ROOTFS PT_SIZE
truncate -s $PT_SIZE $ROOTFS_IMG
e2fsck -f $ROOTFS_IMG
resize2fs $ROOTFS_IMG
echo "DONE"

# 4. Compress update image files 
echo -n ">>>> Compress update images..."
for each_img in ${UPDATE_IMAGES}; do
	gzip -9kf ${each_img}
done
echo "DONE"

# 5. Generate sw-decription file
echo -n ">>>> Check sw-decription file..."
if [ x$SW_DESCP_MANIPU_FLAG == xtrue ]; then
	generate_sw_desc ${WRK_DIR}/sw-description $SW_DESCRIPTION_TEMPLATE $UPDATE_IMAGES
fi
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
	UPDATE_FILES="$UPDATE_FILES ${each_item}.gz"
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

