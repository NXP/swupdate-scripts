#!/bin/bash
#
# Copyright 2022-2023 NXP
# All rights reserved.
#
# SPDX-License-Identifier: BSD-3-Clause

usage_help()
{
    echo "usage:"
    echo "$0 <pad start> <pad filename> <pad end>"
    echo "$0 <pad filename> <pad end>"
    echo " "
    echo "<pad start> and  <pad end>"
    echo "K =1024, M =1024*1024, G =1024*1024*1024, and so on for T, P, E, Z, Y."
    echo " "
    echo "author: Biyong SUN"
}

if [ $# -lt 2 ]; then
    usage_help
    exit 2
fi

if [ $# -gt 3 ]; then
    usage_help
    exit 3
fi

if [ $# -eq 2 ]; then
	pad_filename=$1
	pad_size=$2
	pad_base=0
fi

if [ $# -eq 3 ]; then
	pad_base=$1
	pad_filename=$2
	pad_size=$3
fi

declare -u pad_base=${pad_base}
declare -u pad_size=${pad_size}

if [ ! -f ${pad_filename} ]; then
    echo "file ${pad_filename} not found"
    exit 4
fi

pad_base_num=$(numfmt --from=iec ${pad_base})
pad_size_num=$(numfmt --from=iec ${pad_size})

pad_file_size=$(wc -c ${pad_filename}  |cut -d " " -f 1)

pad_start=` expr ${pad_base_num} + ${pad_file_size} `

if [ ${pad_start} -gt ${pad_size_num} ]; then
	echo "pad_start:${pad_start}(pad_base:${pad_base_num} + pad file size:${pad_file_size})   >  pad end:  ${pad_size_num}" 
	exit -1
fi

if [ ${pad_start} -eq ${pad_size_num} ]; then
    echo "no need padding."
    exit 0
fi 

padding_size=` expr ${pad_size_num} -  ${pad_start} `

echo "${padding_size} need to add to pad to ${pad_size_num}"

hum_pad_base_num=$(numfmt --to=iec ${pad_base_num})
hum_pad_size_num=$(numfmt --to=iec ${pad_size_num})

echo "${pad_filename}_${hum_pad_base_num}_to_${hum_pad_size_num}.pad"
truncate -s ${padding_size}   "${pad_filename}_${hum_pad_base_num}_to_${hum_pad_size_num}.pad"

exit 0

