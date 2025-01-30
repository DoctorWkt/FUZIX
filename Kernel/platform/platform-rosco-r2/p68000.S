
#include "../../cpu-68000/kernel-68000.def"

		.globl plt_reboot
		.globl init_early
		.globl init_hardware
		.globl program_vectors
		.globl plt_idle
		.globl outchar
		.globl plt_monitor
		.globl udata_block0
		.globl devide_read_data
		.globl devide_write_data
		.globl sd_spi_clock
		.globl sd_spi_raise_cs
		.globl sd_spi_lower_cs
		.globl sd_spi_transmit_byte
		.globl sd_spi_receive_byte
		.globl sd_spi_transmit_sector
		.globl sd_spi_receive_sector
		.globl ch375_irq5_handler
		.globl ch375_send_cmd
		.globl ch375_send_data
		.globl ch375_read_data
		.globl ch375_get_status
		.globl ch375_get_status_now
		.globl ch375_read_block
		.globl ch375_write_block
		.globl cpu_delay

/* Defines for SD card access via SPI */
SPI_CS_B   = 2	/* Output port pin */
SPI_SCK_B  = 4	/* Output port pin */
SPI_COPI_B = 6	/* Output port pin */
SPI_CIPO_B = 2	/* Input port pin  */
SPI_CS1_B  = 7	/* Output port pin */

/* Calculate bit values for bit positions */
SPI_CS	 = (1<<SPI_CS_B)
SPI_CS1	 = (1<<SPI_CS1_B)
SPI_SCK	 = (1<<SPI_SCK_B)
SPI_COPI = (1<<SPI_COPI_B)
SPI_CIPO = (1<<SPI_CIPO_B)

/* DUART defines */
#define CTUR $D
#define CTLR $F
#define IMR  $B
#define IVR $19

DUART_BASE_MBR2 = 0xf00001
R_INPUTPORT = 0x1a
W_OPR_SETCMD = 0x1c
W_OPR_RESETCMD = 0x1e
DUART_INPUT   = DUART_BASE_MBR2 + R_INPUTPORT
DUART_OUT_LO  = DUART_BASE_MBR2 + W_OPR_SETCMD
OUT_LO_OFFSET = W_OPR_SETCMD - R_INPUTPORT
OUT_HI_OFFSET = W_OPR_RESETCMD - W_OPR_SETCMD

/* CH375 I/O addresses */
#define CHDATARD  $FFF001
#define CHDATAWR  $FFF001
#define CHCMDWR   $FFF003

/* CH375 Commands */
#define CMD_RESET_ALL           $05
#define CMD_SET_USB_MODE        $15
#define CMD_GET_STATUS          $22
#define CMD_RD_USB_DATA         $28
#define CMD_WR_USB_DATA         $2B
#define CMD_DISK_INIT           $51
#define CMD_DISK_SIZE           $53
#define CMD_DISK_READ           $54
#define CMD_DISK_RD_GO          $55
#define CMD_DISK_WRITE          $56
#define CMD_DISK_WR_GO          $57
#define CMD_DISK_READY          $59

/* CH375 Status Results */
#define USB_INT_SUCCESS         $14
#define USB_INT_CONNECT         $15
#define USB_INT_DISCONNECT      $16
#define USB_INT_DISK_READ       $1D
#define USB_INT_DISK_WRITE      $1E

/* Address of the IRQ5 and clock tick vector */
#define IRQ5_VECTOR   $74
#define TICK_VECTOR   $114

.mri 1
plt_monitor:
	; Need to check if top of memory at FE7000, if so
	; copy vectors from FE7000 to 0 (where we saved them)
	; them jmp to FE8000
plt_reboot:
	    or #$0700,sr
	    bra plt_monitor

init_early:
	    lea.l udata_block0,a5	; udata ptr
	    move.l a5,udata_shadow	; shadow copy for entry/exit
	    rts

plt_idle:
	    stop #($2000+EI_MASK)
	    rts

init_hardware:
	    ; set system RAM size(hardcode hacks for now)
	    move.w #1024,d0
kernelmem:
	    move.w d0,ramsize
	    move.l #_end+512,d1
	    lsr.l #8,d1
	    lsr.l #2,d1
	    sub.w  d1,d0		; Guess for kernel
	    move.w d0,procmem		; guesses for now

	    bsr install_vectors

	    /* Connect the timer and CH375 interrupt handlers */
	    move.l #timer_irq,TICK_VECTOR
	    move.l #ch375_irq5_handler,IRQ5_VECTOR

	    lea.l $F00000,a0
	    move.b #$80,CTLR(a0)
	    move.b #$4,CTUR(a0)
	    move.b #$45,IVR(a0)
	    move.b #$2A,IMR(a0)
	    rts

timer_irq:
	    ; C will save and restore a2+/d2+
	    movem.l a0-a1/a5/d0-d1,-(sp)
	    move.l udata_shadow,a5	; set up the register global
	    move.b #1,U_DATA__U_ININTERRUPT(a5)
	    jsr plt_interrupt
	    clr.b U_DATA__U_ININTERRUPT(a5)

	    tst.b U_DATA__U_INSYS(a5)
	    bne no_preempt
	    tst.b need_resched
	    beq no_preempt
	    ;
	    ;	Vanish into the scheduler. Some other task will pop back out
	    ;	and eventually we'll re-appear here and continue.
	    ;
	    ;	FIXME: check IRQ masking
	    ;
	    move.l U_DATA__U_PTAB(a5),a0
	    ; We might be in STOPPED state in which case do not go back
	    ; to ready !
	    cmp.b #P_RUNNING,P_TAB__P_STATUS_OFFSET(a0)
	    bne no_ready
	    move.b #P_READY,P_TAB__P_STATUS_OFFSET(a0)
	    ori.b #PFL_BATCH,P_TAB__P_FLAGS_OFFSET(a0)
no_ready:
	    bsr switchout
no_preempt:
	    tst.b U_DATA__U_CURSIG(a5)
	    beq no_signal
	    ;	FIXME: this is ugly
	    movem.l (sp)+,a0-a1/a5/d0-d1
	    move.w sr,-(sp)
	    move.w #0,-(sp)
	    movem.l a0-a6/d0-d7,-(sp)
	    move.l (sp),-(sp)
	    bsr exception
	    addq #4,sp
	    movem.l (sp)+,a0-a6/d0-d7
	    addq #4,sp
	    rte
no_signal:
	    movem.l (sp)+,a0-a1/a5/d0-d1
	    rte

;
;	Nothing to do in 68000 - all set up once at boot
;
program_vectors:
	rts

;
;	We do no banking so we need to do nothing here.
;
map_process_always:
map_process:
map_kernel:
map_restore:
map_save:
	rts

; outchar: Wait for UART TX idle, then print the char in d0

outchar:
outcharw:
	btst #2,$00F00003
	beq outcharw
	move.b d0,$00F00007
	rts
;
;	IDE:
;
devide_read_data:
	move.l blk_op,a0
	move.l #$00FFD000,a1
	move.w #255,d0
devide_read_l:
	move.w (a1),(a0)+
	dbra d0,devide_read_l
	rts

devide_write_data:
	move.l blk_op,a0
	move.l #$00FFD000,a1
	move.w #255,d0
devide_write_l:
	move.w (a0)+,(a1)
	dbra d0,devide_write_l
	rts

;
;	SD via SPI
;
sd_spi_clock:
	rts
sd_spi_raise_cs:
	move.b #4,DUART_OUT_LO
	rts
sd_spi_lower_cs:
	move.b #0,DUART_OUT_LO
	rts

/* This code borrowed from Rosco r2 blockdev/dua_spi_asm.asm */
sd_spi_transmit_byte:
	move.b	4+3(sp),d0		/*   12	 d0 = send byte */
	movem.l d2-d5,-(a7)		/* 12+32 save regs */
	move.l	#DUART_OUT_LO,a0	/*   12	 a0 = output LO */
	lea.l	OUT_HI_OFFSET(a0),a1	/*    8	 a1 = output HI */
	moveq.l #SPI_SCK,d1		/*    4	 d1 = SCK bit mask */
	moveq.l #SPI_COPI,d2		/*    4	 d2 = COPI bit mask */
	moveq.l #SPI_SCK,d3		/*    4	 d3 = SCK|COPI bit mask */
	or.l	#SPI_COPI,d3
					/*	 d4 = temp (COPI LO) */
					/*	 d5 = temp (COPI HI) */
	rept	8
/* send bits 7...0 */
	add.b	d0,d0		/*  4  shift MSB to carry */
	scs	d5		/* 4/6	temp set to 0 or 0xff based on carry */
	and.b	d2,d5		/*  4  isolate COPI HI bit to output */
	move.b	d5,d4		/*  4  copy COPI HI bit */
	eor.b	d3,d4		/*  4  set SCK LO and invert COPI for LO bit  */
	move.b	d4,(a0)		/*  8  output SCK LO and COPI LO (if send bit LO) */
	move.b	d5,(a1)		/*  8  output COPI HI (if send bit HI) */
	move.b	d1,(a1)		/*  8  output SCK HI */
	endr

	movem.l (a7)+,d2-d5	/* 12+32  restore regs */
spi_sb_rts:	rts

sd_spi_receive_byte:
	movem.l d2-d3/a2,-(a7)		/* 12+24	save regs */
	move.l	#DUART_INPUT,a0		/* 12 a0 = input */
	lea.l	OUT_LO_OFFSET(a0),a1	/* 8  a1 = output LO */
	lea.l	OUT_HI_OFFSET(a1),a2	/* 8  a2 = output HI */
	moveq.l #SPI_SCK,d1		/* 4  d1 = SCK bit mask */
	moveq.l #SPI_CIPO_B,d2		/* 4  d2 = CIPO bit number */
					/*    d3 = temp */

/* read bit 7 */
	moveq.l #0,d0		/*     4	clear read byte */
	move.b	d1,(a1)		/*     8	output SCK LO */
	btst.b	d2,(a0)		/*     8	test input CIPO bit */
	sne	d3		/*   4/6	temp set to 0 or 0xff based on CIPO bit */
	sub.b	d3,d0		/*     4	set low bit of read byte by subtracting 0 or -1 */
	move.b	d1,(a2)		/*     8	output SCK HI */

	rept	7
/*  read bits 6...0 */
	add.b	d0,d0		/*     4	shift read byte left */
	move.b	d1,(a1)		/*     8	output SCK LO */
	btst.b	d2,(a0)		/*     8	test input CIPO bit */
	sne	d3		/*   4/6	temp set to 0 or 0xff based on CIPO bit */
	sub.b	d3,d0		/*     4	set low bit of read byte by subtracting 0 or -1 */
	move.b	d1,(a2)		/*     8	output SCK HI */
	endr
	movem.l (a7)+,d2-d3/a2	/* 12+24	restore regs */
				/*	d0 = result read byte */
spi_rb_rts:	rts

sd_spi_receive_sector:
	move.w	#512,d0
	/* Get the argument - address of buffer */
	/* As we are a flat system we don't have to worry about */
	/* kernel v user etc */
	move.l	blk_op,a0		/* 12	load data buffer */
	movem.l d2-d4/a2-a3,-(a7)	/*12+40	save regs */
	move.l	#DUART_INPUT,a1		/*  12	a1 = input */
	lea.l	OUT_LO_OFFSET(a1),a2	/*  8	a2 = output LO */
	lea.l	OUT_HI_OFFSET(a2),a3	/*  8	a3 = output HI */
	moveq.l #SPI_SCK,d1		/*  4	d1 = SCK bit mask */
	moveq.l #SPI_CIPO_B,d2		/*  4	d2 = CIPO bit num */
					/*	d3 = temp bit */
					/*	d4 = temp byte */

.spi_rb_loop:
	rept	8
/* read bits 7...0 */
	add.b	d4,d4			/*  4	shift read byte left */
	move.b	d1,(a2)			/*  8	set SCK LO */
	btst.b	d2,(a1)			/*  8	read input CIPO bit */
	sne	d3			/* 4/6	d3 = 0 or -1 */
	sub.b	d3,d4			/*  4	set low bit of read byte */
	move.b	d1,(a3)			/*  8	set SCK HI */
	endr

	move.b	d4,(a0)+		/*  8	save read byte */
	subq.l	#1,d0			/*  8	decrement count */
	bne.s	.spi_rb_loop		/* 8/10	loop if not zero */

.spi_rb_done:
	movem.l (a7)+,d2-d4/a2-a3	/* 12+40 restore regs */
	rts

sd_spi_transmit_sector:
	move.w	#512,d0
	move.l	blk_op,a0		/* 12	load data buffer */
	movem.l d2-d6/a2,-(a7)		/* 12+48 save regs */
	move.l	#DUART_OUT_LO,a1	/*  12	a1 = output LO */
	lea.l	OUT_HI_OFFSET(a1),a2	/*   8	a2 = output HI */
	moveq.l #SPI_SCK,d2		/*   4	d2 = SCK bit mask */
	moveq.l #SPI_COPI,d3		/*   4	d3 = COPI bit mask */
	moveq.l #SPI_SCK,d4		/*   4	d4 = SCK|COPI bit mask */
	or.l	#SPI_COPI,d4
					/*	d5 = temp COPI LO */
					/*	d6 = temp COPI HI */

.spi_sb_loop:
	move.b	(a0)+,d1		/*    8	load send byte */

	rept	8
/* send bits 7...0 */
	add.b	d1,d1			/*    4	shift MSB to carry */
	scs	d6			/*  4/6	temp set to 0 or 0xff based on carry */
	and.b	d3,d6			/*    4	isolate COPI HI bit to output */
	move.b	d6,d5			/*    4	copy COPI HI bit */
	eor.b	d4,d5			/*    4	set SCK LO and invert COPI for LO bit  */
	move.b	d5,(a1)			/*    8	output SCK LO and COPI LO (if send bit LO) */
	move.b	d6,(a2)			/*    8	output COPI HI (if send bit HI) */
	move.b	d2,(a2)			/*    8	output SCK HI */
	endr

	subq.l	#1,d0
	bne	.spi_sb_loop  

.spi_sb_done:
	movem.l (a7)+,d2-d6/a2		/* 12+48 restore regs */
	rts

/* CH375 code */

/*
 * This is the interrupt handler for the CH375.
 * Send a CMD_GET_STATUS to the device,
 * read a byte of data and save it in the
 * CH375_STATUS location.
 */
ch375_irq5_handler:
        move.b #CMD_GET_STATUS,CHCMDWR
        move.b CHDATARD,CH375_STATUS
        rte

/*
 * Write the given command to the CH375.
 * Clear the CH375_STATUS beforehand by
 * putting a dummy value there.
 */
ch375_send_cmd:
        move.b #$FF,CH375_STATUS
        move.b 7(A7),D0
        move.b D0,CHCMDWR
        rts

/* Write the given data to the CH375. */
ch375_send_data:
        move.b 7(A7),D0
        move.b D0,CHDATAWR
        rts

/* Read data from the CH375 */
ch375_read_data:
        move.b CHDATARD,D0
        rts

/*
 * Get the CH375 status from the
 * CH375_STATUS memory location.
 * Loop until it is not $FF
 */
ch375_get_status:
        move.b CH375_STATUS,D0
        cmpi.b #$FF,D0
        beq    ch375_get_status
        rts

/* As above but don't loop */
ch375_get_status_now:
        move.b CH375_STATUS,D0
        rts

/*
 * Given a pointer to a 512-byte buffer and an
 * LBA number, read the block from the CH375 into
 * the buffer. Return 1 on success, 0 otherwise.
 *
 * uint32_t ch375_read_block(uint8_t *buf, uint32_t lba)
 */
ch375_read_block:

        /* Check that buf isn't NULL */
        movea.l 4(SP),A0
        cmp.l   #0,4(SP)
        beq.w   ch375_readfail

        /* Send the disk read command followed by the LBA */
        /* in little-endian format, then ask for one block. */
        move.b  #$FF,CH375_STATUS
        move.b  #CMD_DISK_READ,CHCMDWR
        move.b  11(SP),CHDATAWR
        move.b  10(SP),CHDATAWR
        move.b  9(SP),CHDATAWR
        move.b  8(SP),CHDATAWR
        move.b  #1,CHDATAWR

        /* Loop eight times reading in */
        /* 64 bytes of data each time. */
        moveq.l #8,D1
CH375_READL1:

        /* Get the status, ensure that */
        /* it is USB_INT_DISK_READ */
        jsr     ch375_get_status
        cmpi.b  #USB_INT_DISK_READ,D0
        bne.s   ch375_readfail

        /* Send the command to read the data, */
        /* get back the number of bytes to read. */
        /* Divide it by eight to match the loop */
        /* unrolling below (this assumes the count */
        /* is a multiple of eight). */
        move.b  #$FF,CH375_STATUS
        move.b  #CMD_RD_USB_DATA,CHCMDWR
        clr.l   D0
        move.b  CHDATARD,D0
        lsr.l   #3,D0

        /* Loop cnt times reading data */
CH375_READL2:
        move.b  CHDATARD,(A0)+
        move.b  CHDATARD,(A0)+
        move.b  CHDATARD,(A0)+
        move.b  CHDATARD,(A0)+
        move.b  CHDATARD,(A0)+
        move.b  CHDATARD,(A0)+
        move.b  CHDATARD,(A0)+
        move.b  CHDATARD,(A0)+
        subi.l  #1,D0
        bne.s   CH375_READL2

        /* After cnt bytes, tell the CH375 */
        /* to get the next set of data */
        /* and loop back */
        move.b  #$FF,CH375_STATUS
        move.b  #CMD_DISK_RD_GO,CHCMDWR
        subi.l  #1,D1
        bne.s   CH375_READL1

        /* Get the status after reading the block */
        jsr     ch375_get_status
        cmpi.b  #USB_INT_SUCCESS,D0
        bne.s   ch375_readfail

        /* Return 1 on success, 0 on failure */
ch375_readok:
        moveq.l #1,d0
        rts

ch375_readfail:
        moveq.l #0,d0
        rts

/*
 * Given a pointer to a 512-byte buffer and an
 * LBA number, write the block from the buffer
 * to the CH375. Return 1 on success, 0 otherwise.
 *
 * uint32_t ch375_write_block(uint8_t *buf, uint32_t lba)
 */
ch375_write_block:

        /* Check that buf isn't NULL */
        movea.l 4(SP),A0
        cmp.l   #0,4(SP)
        beq.w   ch375_writefail

        /* Send the disk write command followed by the LBA in */
        /* little-endian format, then ask to send one block. */
        move.b  #$FF,CH375_STATUS
        move.b  #CMD_DISK_WRITE,CHCMDWR
        move.b  11(SP),CHDATAWR
        move.b  10(SP),CHDATAWR
        move.b  9(SP),CHDATAWR
        move.b  8(SP),CHDATAWR
        move.b  #1,CHDATAWR

        /* Loop eight times writing out */
        /* 64 bytes of data each time. */
        moveq.l #8,D1
CH375_WRITEL1:

        /* Get the status, ensure that */
        /* it is USB_INT_DISK_WRITE */
        jsr     ch375_get_status
        cmpi.b  #USB_INT_DISK_WRITE,D0
        bne.s   ch375_writefail

        /* Send the command to write the data */
        /* along with the count. Then set D0 */
        /* to 8 for the loop: it really is 64 */
        /* but we do loop unrolling. */
        move.b  #$FF,CH375_STATUS
        move.b  #CMD_WR_USB_DATA,CHCMDWR
        move.b  #64,CHDATAWR
        moveq.l #8,D0

        /* Loop 8 times writing data */
CH375_WRITEL2:
        move.b  (A0)+,CHDATAWR
        move.b  (A0)+,CHDATAWR
        move.b  (A0)+,CHDATAWR
        move.b  (A0)+,CHDATAWR
        move.b  (A0)+,CHDATAWR
        move.b  (A0)+,CHDATAWR
        move.b  (A0)+,CHDATAWR
        move.b  (A0)+,CHDATAWR
        subi.l  #1,D0
        bne.s   CH375_WRITEL2

        /* After 64 bytes, tell the CH375 to */
        /* get ready for the next set of data */
        /* and loop back */
        move.b  #$FF,CH375_STATUS
        move.b  #CMD_DISK_WR_GO,CHCMDWR
        subi.l  #1,D1
        bne.s   CH375_WRITEL1

        /* Get the status after writing the block */
        jsr     ch375_get_status
        cmpi.b  #USB_INT_SUCCESS,D0
        bne.s   ch375_writefail

        /* Return 1 on success, 0 on failure */
ch375_writeok:
        moveq.l #1,d0
        rts

ch375_writefail:
        moveq.l #0,d0
        rts

/* This comes from xosera_m68k_api.c. */
/* Delay for D0 milliseconds */
cpu_delay:
        move.l 4(A7),D0
        lsl.l  #8,D0
        add.l  D0,D0
L1:     subq.l #1,D0
        tst.l  D0
        bne.s  L1
        rts
