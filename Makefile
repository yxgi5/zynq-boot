#
#NDKPATH=/scratch/android-ndk-r9d/
ifeq ($(shell uname), Darwin)
    PREFIX=arm-none-eabi-
else
    NDK_OBJDUMP=$(shell $(NDKPATH)ndk-which objdump)
    PREFIX=$(shell dirname $(NDK_OBJDUMP))/arm-linux-androideabi-
endif
DTC=../device_xilinx_kernel/scripts/dtc/dtc

all: boot.bin sdcard

clean:
	## '"make realclean" to remove downloaded files
	rm -fr sdcard-* boot.bin *.tmp *.elf *.gz *.hex *.o foo.map xbootgen

realclean: clean
	rm -fr filesystems/*

boot.bin: zcomposite.elf imagefiles/zynq_$(BOARD)_fsbl.elf xbootgen reserved_for_interrupts.tmp
	if [ -f boot.bin ]; then mv -v boot.bin boot.bin.bak; fi
	cp -f imagefiles/zynq_$(BOARD)_fsbl.elf zynq_fsbl.elf
	./xbootgen zynq_fsbl.elf zcomposite.elf
	#rm -f zynq_fsbl.elf zcomposite.elf reserved_for_interrupts.tmp

dtb.tmp: imagefiles/zynq-$(BOARD)-portal.dts
	macbyte=`echo $(USER) | md5sum | cut -c 1-2`; sed s/73/$$macbyte/ <imagefiles/zynq-$(BOARD)-portal.dts >dtswork.tmp
	$(DTC) -I dts -O dtb -o dtb.tmp dtswork.tmp
	rm -f dtswork.tmp

zcomposite.elf: ramdisk dtb.tmp
	echo "******** PRINT GCC CONFIGURE OPTIONS *******"
	$(PREFIX)gcc -v 2>&1
	$(PREFIX)objcopy -I binary -B arm -O elf32-littlearm imagefiles/zImage z.tmp
	$(PREFIX)objcopy -I binary -B arm -O elf32-littlearm ramdisk.image.gz r.tmp
	$(PREFIX)objcopy -I binary -B arm -O elf32-littlearm dtb.tmp d.tmp
	rm -f dtb.tmp
	$(PREFIX)gcc -c clearreg.S
	$(PREFIX)ld -z noexecstack -Ttext 0 -e 0 -o c.tmp clearreg.o
	$(PREFIX)objcopy -I elf32-littlearm -O binary c.tmp c1.tmp
	$(PREFIX)objcopy -I binary -B arm -O elf32-littlearm c1.tmp c.tmp
	$(PREFIX)ld -e 0x1008000 -z max-page-size=0x8000 -o zcomposite.elf --script zynq_linux_boot.lds r.tmp d.tmp c.tmp z.tmp
	#rm -f z.tmp r.tmp d.tmp c.tmp c1.tmp clearreg.o ramdisk.image.gz

canoncpio: canoncpio.c
	gcc -o canoncpio canoncpio.c

ramdisk: canoncpio
	cd data; chmod 644 *.rc *.prop
	#find data -name \* -exec touch -h -t 201405010000 {} \;
	cd data; (find . -name unused -o -print | cpio -H newc -o | canoncpio | gzip -9 -n >../ramdisk.image.temp)
	cat ramdisk.image.temp /dev/zero | dd of=ramdisk.image.gz count=256 ibs=1024
	rm -f ramdisk.image.temp

xbootgen: xbootgen.c Makefile
	gcc -g -o xbootgen xbootgen.c

reserved_for_interrupts.tmp: reserved_for_interrupts.S
	$(PREFIX)gcc -c reserved_for_interrupts.S
	$(PREFIX)ld -Ttext 0 -e 0 -o i.tmp reserved_for_interrupts.o
	$(PREFIX)objcopy -O binary -I elf32-little i.tmp reserved_for_interrupts.tmp
	rm -f i.tmp reserved_for_interrupts.o

sdcard: sdcard-$(BOARD)/system.img sdcard-$(BOARD)/userdata.img sdcard-$(BOARD)/boot.bin
	cp -v imagefiles/zynqportal.ko imagefiles/portalmem.ko sdcard-$(BOARD)/
	echo "Files for $(BOARD) SD Card are in $(PWD)/sdcard-$(BOARD)"

.PHONY: sdcard

sdcard-$(BOARD)/boot.bin:
	mkdir -p sdcard-$(BOARD)
	rm -f boot.bin
	make BOARD=$(BOARD) boot.bin
	mv boot.bin sdcard-$(BOARD)/boot.bin

filesystems/system-130710.img.bz2:
	mkdir -p filesystems
	wget 'https://dl.dropboxusercontent.com/u/108092026/xbsv/system-130710.img.bz2' -O filesystems/system-130710.img.bz2

filesystems/userdata.img.bz2:
	mkdir -p filesystems
	wget 'https://dl.dropboxusercontent.com/u/108092026/xbsv/userdata.img.bz2' -O filesystems/userdata.img.bz2

sdcard-$(BOARD)/system.img: filesystems/system-130710.img.bz2
	mkdir -p sdcard-$(BOARD)
	bzcat filesystems/system-130710.img.bz2 > sdcard-$(BOARD)/system.img
	(cd sdcard-$(BOARD); md5sum -c ../imagefiles/filesystems.md5sum)

ifeq ($(shell uname), Darwin)
sdcard-$(BOARD)/userdata.img: filesystems/userdata.img.bz2
	mkdir -p sdcard-$(BOARD)
	bzcat filesystems/userdata.img.bz2 > sdcard-$(BOARD)/userdata.img
else
sdcard-$(BOARD)/userdata.img:
	mkdir -p sdcard-$(BOARD)
	# make a 100MB empty filesystem
	dd if=/dev/zero bs=1k count=102400 of=sdcard-$(BOARD)/userdata.img
	mkfs -F -t ext4 sdcard-$(BOARD)/userdata.img
endif
