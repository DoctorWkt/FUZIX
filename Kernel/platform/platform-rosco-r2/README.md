# FUZIX Port to the Rosco r2 SBC

Warren Toomey - 2025/02/04

## Introduction

This is the port of FUZIX to the Rosco r2 m68k SBC:
https://github.com/rosco-m68k/rosco_m68k

It's a work in progress and some things don't work well yet.

## Building FUZIX

You will need the toolchain described in
https://github.com/rosco-m68k/rosco_m68k/blob/develop/code/Toolchain.md

At the top-level FUZIX directory, you can do:

```
make TARGET=rosco-r2 kernel        # Build the kernel, which creates
                                   # the file Kernel/fuzix.bin
make TARGET=rosco-r2 diskimage     # Builds the libraries and applications,
                                   # and then creates the filesystem image
                                   # Images/rosco-r2/filesys.img
make TARGET=rosco-r2 kclean        # Clean up the kernel build. Do this if
                                   # you make any kernel config changes
make TARGET=rosco-r2 clean         # Clean up everything
```

There is a shell script here called `mk_fs_img`. Once you have
`Kernel/fuzix.bin` and `Images/rosco-r2/filesys.img` you can run
this script to make the SD card image `sdcard.img` which has the
bootable kernel in partition 1 and the populated FUZIX filesystem
in partition 2.

There is a bzipped copy of a recent `sdcard.img` here in the repository
if you want to try it without installing the tool chain.

## Configuration

Look in `config.h` for compile-time configuration defines.
`TTY_INIT_BAUD` is set for 115200 baud. `CONFIG_FLAT` means we have no MMU.
`CONFIG_SD` and `SD_DRIVE_COUNT` sets us up for one SD card.
`CONFIG_USB` supports my USB expansion board:
https://github.com/DoctorWkt/xv6-rosco-r2/tree/ch375/hardware

This line in `fuzix.ld`:

```
ram (rwx) : ORIGIN = 0x2000, LENGTH = 0x100000-0x2000
```

says that the kernel starts at $2000 and we have $100000 (1 Meg) of RAM.

## Booting

The Rosco ROM loads the kernel at address $40000. The code in `crt0.S`
copies the kernel down to $2000. Then, interrupts are enabled and the
BSS gets cleared. These functions are then called: `init_early()`,
`init_hardware()` and `fuzix_main()`.

## Devices

`devices.c` holds a tables of devices and associated functions. The
main ones are the block devices (0) and the tty device (2). 
`device_init()` is called to probe devices and initialise them.

## The DUART

The code to use the XR68C681 DUART is in `devtty.c`. I have made the
`tty_setup()` function do essentially nothing. The Rosco ROM sets the
DUART up for 115200 baud. The Fuzix code then does something which
scrambles the 115200 baud setting. Until I can figure it out, I've
just disabled it.

## SD card support.

The kernel is configured to have SD card support. The file `p68000.S` has
assembly functions to bit-bang the SD card using the DUART:

```
                .globl sd_spi_clock
                .globl sd_spi_raise_cs
                .globl sd_spi_lower_cs
                .globl sd_bb_transmit_byte
                .globl sd_bb_receive_byte
                .globl sd_bb_transmit_sector
                .globl sd_bb_receive_sector
```

and the high-level SD card code is in `Kernel/dev/devsd.c` and
`Kernel/dev/devsd_discard.c`.

Copy the SD card image `sdcard.img` to your SD card. Under Linux I do:

```
cat sdcard.img > /dev/sdc; sync; sync
```

At boot time, the SD card should appear as `hda` with two partitions.
Use the boot device `hda2` and login as `root` with no password.

## CH375 USB

Because the Rosco r2 SBC boots from the SD card, you need to copy
the SD card image `sdcard.img` to both your SD card and your USB drive.

At boot time, the SD card should appear as `hdb` with two partitions.
Use the boot device `hdb2` and login as `root` with no password.
