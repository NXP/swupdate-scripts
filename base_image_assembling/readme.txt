a. prepare boot partition mirror file 
   truncate -s 120M common/slota_boot_pt_120M.mirror
   truncate -s 120M common/slotb_boot_pt_120M.mirror

b. create slota slotb symbol link
   ln -s  <yocto/deploy image directory a> slota
   ln -s  <yocto/deploy image directory b> slotb
c. assemble image
   cd workspace  
       
   mkfs.vfat 05-boot_pt

   mdir -i 05-boot_pt
   mcopy -i 05-boot_pt  03-imx8mm-evk.dtb ::imx8mm-evk.dtb
   mcopy -i 05-boot_pt 02-Image ::Image
   mdir -i 05-boot_pt
 
   ./padding_file_create.sh 0k 00-swu_7.5G.pt 33K
   ./padding_file_create.sh 33K  01-imx-boot 8M
   ./padding_file_create.sh 8M 02-Image 38M
   ./padding_file_create.sh 38M 03-imx8mm-evk.dtb 42M
   ./padding_file_create.sh 42M 04-swupdate-image 100M

   truncate -s 3000M 06-imx-image-multimedia 
   e2fsck -f 06-imx-image-multimedia 
   resize2fs  06-imx-image-multimedia 

   var_storage=emmc&& var_DATE=$(date "+%Y%m%d-%H%M%S") && cat $(ls 0*) > swu_slota_w_swu_rescue_imx8mm_${var_storage}_${var_DATE}.sdcard  && zip -9 swu_slota_w_swu_rescue_imx8mm_${var_storage}_${var_DATE}.sdcard.zip swu_slota_w_swu_rescue_imx8mm_${var_storage}_${var_DATE}.sdcard


   mkfs.vfat 15-boot_pt

   mdir -i 15-boot_pt
   mcopy -i 15-boot_pt  13-imx8mm-evk.dtb ::imx8mm-evk.dtb
   mcopy -i 15-boot_pt  12-Image ::Image
   mdir -i 15-boot_pt

   truncate -s 3000M 16-imx-image-multimedia 
   e2fsck -f 16-imx-image-multimedia 
   resize2fs  16-imx-image-multimedia 

    var_storage=emmc&& var_DATE=$(date "+%Y%m%d-%H%M%S") && cat $(ls 0*) 15-boot_pt 16-imx-image-multimedia > swu_slota_w_swu_rescue_imx8mm_${var_storage}_${var_DATE}.entire.sdcard  && zip -9 swu_slota_w_swu_rescue_imx8mm_${var_storage}_${var_DATE}.entire.sdcard.zip swu_slota_w_swu_rescue_imx8mm_${var_storage}_${var_DATE}.entire.sdcard


