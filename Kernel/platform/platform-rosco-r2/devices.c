#include <kernel.h>
#include <version.h>
#include <kdata.h>
#include <devide.h>
#include <blkdev.h>
#include <devsys.h>
#include <tty.h>
#include <vt.h>

struct devsw dev_tab[] =  /* The device driver switch table */
{
// minor    open         close        read      write       ioctl
// -----------------------------------------------------------------
  /* 0: /dev/hd		Disc block devices  */
  {  blkdev_open,   no_close,    blkdev_read,   blkdev_write, blkdev_ioctl },
  /* 1: /dev/fd		Hard disc block devices (absent) */
  {  nxio_open,     no_close,    no_rdwr,   no_rdwr,   no_ioctl },
  /* 2: /dev/tty	TTY devices */
  {  tty_open,     tty_close,   tty_read,  tty_write,  tty_ioctl },
  /* 3: /dev/lpr	Printer devices */
  {  no_open,     no_close,   no_rdwr,   no_rdwr,  no_ioctl  },
  /* 4: /dev/mem etc	System devices (one offs) */
  {  no_open,      no_close,    sys_read, sys_write, sys_ioctl  },
  /* Pack to 7 with nxio if adding private devices and start at 8 */
};

bool validdev(uint16_t dev)
{
    /* This is a bit uglier than needed but the right hand side is
       a constant this way */
    if(dev > ((sizeof(dev_tab)/sizeof(struct devsw)) << 8) - 1)
	return false;
    else
        return true;
}

void device_init(void)
{
  // devide_init();
  devsd_init();
  // devch375_init();
}

/* These functions go in-between the devsd.c code and the assembly code. */
/* They disable interrupts, do the work and then re-enable them. We need */
/* this to ensure the bit-banging doesn't get context switched out. */

extern void sd_bb_transmit_byte(uint_fast8_t byte);
extern uint_fast8_t sd_bb_receive_byte(void);
extern bool sd_bb_receive_sector(void);
extern bool sd_bb_transmit_sector(void);

void sd_spi_transmit_byte(uint_fast8_t byte)
{
    irqflags_t irq = di();
    sd_bb_transmit_byte(byte);
    irqrestore(irq);
}

uint_fast8_t sd_spi_receive_byte(void)
{
    irqflags_t irq = di();
    uint_fast8_t result= sd_bb_receive_byte();
    irqrestore(irq);
    return(result);
}

bool sd_spi_receive_sector(void)
{
    irqflags_t irq = di();
    bool result= sd_bb_receive_sector();
    irqrestore(irq);
    return(result);
}

bool sd_spi_transmit_sector(void)
{
    irqflags_t irq = di();
    bool result= sd_bb_transmit_sector();
    irqrestore(irq);
    return(result);
}
