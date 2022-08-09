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

function copy_images_to_boot_pt()
{
	local boot_pt=$1
	# slot can be SLOTA or SLOTB
	local slot=$2

	echo "boot_pt: $boot_pt"
	echo "slot: $slot"

	slot_upper=$(echo $slot | tr a-z A-Z)
	eval slot_boot_pt_files="\$${slot_upper}_BOOT_PT_FILES"
	mkfs.vfat $boot_pt
	mdir -i $boot_pt
	for each_file in $slot_boot_pt_files; do
		if [ ! -e ./${each_file} ]; then
			echo "./${each_file} not existed!"
			exit 1
		fi
		img_name=$(basename ${each_file})
		#mdel -i $boot_pt ${img_name}
		mcopy -i $boot_pt ./${each_file} ::${img_name}
	done
	mdir -i $boot_pt
}

function calculate_pt_size()
{
	local pt_info=$1

	local pt_start=$(echo $pt_info | cut -d: -f2)
	local pt_end=$(echo $pt_info | cut -d: -f3)

	local pt_start_num=$(numfmt --from=iec ${pt_start})
	local pt_end_num=$(numfmt --from=iec ${pt_end})


	if [[ ${pt_start_num} -gt ${pt_end_num} ]]; then
    	echo "partition start is greater than end!"
    	return -1
	fi 

	local pt_size_num=`expr ${pt_end_num} - ${pt_start_num}`
	echo "pt_size_num: $pt_size_num"

	#local pt_size=$(numfmt --to=iec ${pt_size_num})

	PT_SIZE=$pt_size_num

	echo "Calculated partition size: $PT_SIZE"
}

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

SOC_ASSEMBLE_SETTING_FILE="cfg_${SOC}.sh"
source ${WRK_DIR}/${SOC_ASSEMBLE_SETTING_FILE}

# 1. Check if need to sign image
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

if [ -z "${OUTPUT_IMAGE_NAME}" ]; then
	if [ x"$SIGN_FLAG" == x"true" ]; then
		OUTPUT_IMAGE_NAME=${SOC_NAME}_${UPDATE_CONTAINER_VER}_slot${SLOT}_${UPDATE_BSP_VER}_${COPY_MODE}_${STORAGE_DEVICE}_${CUR_DATE}_sign.swu
	else
		OUTPUT_IMAGE_NAME=${SOC_NAME}_${UPDATE_CONTAINER_VER}_slot${SLOT}_${UPDATE_BSP_VER}_${COPY_MODE}_${STORAGE_DEVICE}_${CUR_DATE}_nosign.swu
	fi
fi

# 2. Copy images to boot partition
echo -n ">>>> Check update boot partition mirror..."
BOOT_PT=$(echo $UPDATE_BOOT_PT | cut -d: -f1)
if [ ! -e ${BOOT_PT} ]; then
	echo -n "\nNo update boot partition mirror, generate..."
	PT_SIZE=''
	calculate_pt_size $UPDATE_BOOT_PT
	truncate -s ${PT_SIZE} ${BOOT_PT}
fi
echo "DONE"

echo -n ">>>> Copying kernel images and dtbs to boot partition..."
copy_images_to_boot_pt $BOOT_PT update
echo "DONE"

# 3. Truncate rootfs
echo -n ">>>> Truncating rootfs..."
PT_SIZE=''
ROOTFS_IMG=$(echo $UPDATE_ROOTFS | cut -d: -f1)
if [ ! -e $ROOTFS_IMG ]; then
	echo "ROOTFS image not found!"
	exit -1
fi
calculate_pt_size $UPDATE_ROOTFS
truncate -s $PT_SIZE $ROOTFS_IMG
e2fsck -f $ROOTFS_IMG
resize2fs $ROOTFS_IMG
echo "DONE"

# 4. Test if all needed images exist
echo -n ">>>> Testing update images..."
for each_img in ${UPDATE_IMAGES}; do
	test ! -e "${each_img}" && echo "${each_img} not exists!!!" && exit -1;
done
echo "DONE"

# 5. Compress update image files 
echo -n ">>>> Compress update images..."
for each_img in ${UPDATE_IMAGES}; do
	gzip -9kf ${each_img}
done
echo "DONE"

# 6. assemble cpio package.
echo ">>>> Creating CPIO package..."
echo $UPDATE_FILES
for each_item in $UPDATE_FILES; do
	echo ${each_item}
done | cpio -ov -H crc > $OUTPUT_IMAGE_NAME
echo "DONE"

echo "==========================================================================="
echo "Create update image $OUTPUT_IMAGE_NAME successfully"
echo "==========================================================================="

