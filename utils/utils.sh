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

# $1 - sw_desc file name.
# $2 - sw desc template file.
# $3 - image list
function generate_sw_desc()
{
	local sw_desc_file=$1
	local template_file=$2


}

