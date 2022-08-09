a. truncate -s 120M slotb_boot_pt_120M.mirror --- only run for first time.
b. cp <yocto/deploy image directory>/{Image,imx8mm-evk.dtb,imx-boot-imx8mmevk-sd.bin-flash_evk,imx-image-multimedia-imx8mmevk.ext4} .
c. run following command
mkfs.vfat slotb_boot_pt_120M.mirror
mdir -i slotb_boot_pt_120M.mirror
mcopy -i slotb_boot_pt_120M.mirror imx8mm-evk.dtb ::imx8mm-evk.dtb
mcopy -i slotb_boot_pt_120M.mirror Image ::Image
mdir -i slotb_boot_pt_120M.mirror
gzip -9k slotb_boot_pt_120M.mirror
truncate -s 3000M imx-image-multimedia-imx8mmevk.ext4
e2fsck -f imx-image-multimedia-imx8mmevk.ext4
resize2fs imx-image-multimedia-imx8mmevk.ext4
gzip -9k imx-image-multimedia-imx8mmevk.ext4
d. get sha256sum and modify the sw-description
sha256sum slotb_boot_pt_120M.mirror.gz imx-image-multimedia-imx8mmevk.ext4.gz imx-boot-imx8mmevk-sd.bin-flash_evk emmc_bootpart.sh
e. run ./swu_signed_image_build.sh
pass phrase is test
