#!/usr/bin/bash

function generate_padding_file()
{
	local pad_base=$1
	local pad_filename=$2
	local pad_size=$3
	local output_pad_file=$4

	echo "pad_base: $pad_base"
	echo "pad_filename: $pad_filename"
	echo "pad_size: $pad_size"
	echo "output_pad_file: $output_pad_file"

	local pad_base_num=$(numfmt --from=iec ${pad_base})
	local pad_size_num=$(numfmt --from=iec ${pad_size})

	
	local pad_file_size=$(wc -c ${pad_filename} | cut -d" " -f1)

	local pad_start=`expr ${pad_base_num} + ${pad_file_size}`

	if [[ ${pad_start} -gt ${pad_size_num} ]]; then
		echo "pad_start:${pad_start} (pad_base:${pad_base_num} + pad file size:${pad_file_size}) > pad end: ${pad_size_num}" 
		return -1
	fi

	if [[ ${pad_start} -eq ${pad_size_num} ]]; then
    	echo "no need padding."
    	return 0
	fi 

	local padding_size=`expr ${pad_size_num} - ${pad_start}`

	echo "${padding_size} need to add to pad to ${pad_size_num}"

	cp $pad_filename $output_pad_file
	truncate -s +${padding_size} ${output_pad_file}
}

function copy_images_to_boot_pt()
{
	local boot_pt=$1
	# slot can be SLOTA or SLOTB
	local slot=$2

	echo "boot_pt: $boot_pt"
	echo "slot: $slot"

	local slot_upper=$(echo $slot | tr a-z A-Z)
	eval slot_boot_pt_files="\$${slot_upper}_BOOT_PT_FILES"
	mkfs.vfat $boot_pt
	mdir -i $boot_pt
	for each_file in $slot_boot_pt_files; do
		if [ ! -e ${each_file} ]; then
			echo "${each_file} not existed!"
			exit 1
		fi
		img_name=$(basename ${each_file})
		#mdel -i $boot_pt ${img_name}
		mcopy -i $boot_pt ${each_file} ::${img_name}
	done
	mdir -i $boot_pt
}

function calculate_pt_size()
{
	local pt_info=$1
	local out_pt_size=$2

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

	eval $out_pt_size=$pt_size_num

	echo "Calculated partition size: $PT_SIZE"
}

# $1 - output sw_desc file name.
# $2 - sw desc template file.
# $3 - image list
function generate_sw_desc()
{
	local sw_desc_file=$1
	shift
	local template_file=$1
	shift
	local compress_flag=$1
	shift
	local image_list=$@

	echo "software desc file: $sw_desc_file"
	echo "template file: $template_file"
	echo "image_list: $image_list"

	echo "Generating software description file..."
	if [ -e $template_file ]; then
		# template file can be found, so create a new sw-description file.
		echo "Create new sw-description file"
		cp $template_file $sw_desc_file
	else
		# No template file
		echo "Use existing sw-description file"
	fi
	for each_item in $image_list; do
		if [ x${compress_flag} == xtrue ]; then
			sed -i "s/${each_item}/${each_item}.gz/" $sw_desc_file
			hash_filename=${each_item}.gz
			sed -i "/<${hash_filename}_sha256>/acompressed = \"zlib\";" $sw_desc_file
		else
			hash_filename=${each_item}
		fi
		hash_str=$(sha256sum ${WRK_DIR}/${hash_filename})
		echo $hash_str
		sha256_sum=$(echo $hash_str | cut -d' ' -f1)
		sed -i "s/<${hash_filename}_sha256>/${sha256_sum}/" $sw_desc_file
	done
	echo "DONE"
}

function generate_pt_tbl_dualslot()
{
	local PT_DISKLABEL=$1
	local PT_FILESIZE=$2
	local PT_FMT=$3

	if [ -z "${PT_DISKLABEL}" ]; then
		echo "Error: please specify an disk label for MBR!"
		exit 1
	fi

	if [ -z "${PT_FILESIZE}" ]; then
        echo "Error: please specify a file size for MBR!"
        exit 1
	fi

	truncate -s ${PT_FILESIZE} ${PT_DISKLABEL}
	if [ $? != 0 ]; then
		echo "truncate to ${PT_FILESIZE} on ${PT_DISKLABEL} failed!"
		exit -1
	fi

	for each_item in $IMAGE_PT_TBL_STRUCT; do
		local pt_index=$(echo $each_item | cut -d: -f1)
		local pt_name=$(echo $each_item | cut -d: -f2)
		local pt_start=$(echo $each_item | cut -d: -f3)
		local pt_end=$(echo $each_item | cut -d: -f4)
		local pt_fs=$(echo $each_item | cut -d: -f5)
		case $PT_FMT in
			MBR)
				sudo parted ${PT_DISKLABEL} unit MiB mkpart primary ${pt_fs} ${pt_start} ${pt_end}
				;;
			GPT)
				sudo sgdisk -a 8 -n ${pt_index}:${pt_start}:${pt_end} -t ${pt_index}:${pt_fs} -c ${pt_index}:${pt_name} -e ${PT_DISKLABEL}
				;;
			?)
				echo "Invalid partition type!"
				exit -1
				;;
		esac
		if [ $? != 0 ]; then
			echo "Make partition ${pt_fs} from ${pt_start} to ${pt_end} on ${PT_DISKLABEL} failed!"
			exit -1
		fi
	done

	case $PT_FMT in
		MBR)
			sudo parted ${PT_DISKLABEL} unit MiB print
			;;
		GPT)
			sudo sgdisk -p -e ${PT_DISKLABEL}
			;;
		?)
			echo "Invalid partition type!"
			exit -1
			;;
	esac

	truncate -s ${IMAGE_PT_TBL_LENGTH} ${PT_DISKLABEL}
	if [ $? != 0 ]; then
		echo "truncate to ${IMAGE_PT_TBL_SIZE} on ${PT_DISKLABEL} failed!"
		exit -1
	fi
}

function check_valid_boards()
{
	local soc_name=$1

	if [ -z "${soc_name}" ]; then
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
			exit -1
		fi
	fi
}
