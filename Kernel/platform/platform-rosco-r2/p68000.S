
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

#define CTUR $D
#define CTLR $F
#define IMR  $B
#define IVR $19

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

/* Since DUART GPIO is active-low, use register aliases
 * for DUART ports to be less confusing
 */

DUART_BASE_MBR2 = 0xf00001
R_INPUTPORT = 0x1a
W_OPR_SETCMD = 0x1c
W_OPR_RESETCMD = 0x1e
DUART_INPUT   = DUART_BASE_MBR2 + R_INPUTPORT
DUART_OUT_LO  = DUART_BASE_MBR2 + W_OPR_SETCMD
OUT_LO_OFFSET = W_OPR_SETCMD - R_INPUTPORT
OUT_HI_OFFSET = W_OPR_RESETCMD - W_OPR_SETCMD

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
;	    lea $300000,a0		; will be wrapped on the rc2014
;	    lea $100000,a1		; well above the kernel
;	    move.w #$AA55,(a0)
;	    cmp.w #$AA55,(a1)
;	    bne tiny68k
;	    move.w #$55AA,(a0)
;	    cmp.w #$55AA,(a1)
;	    bne tiny68k
;	    move.w #2048,d0
;	    bra kernelmem
;tiny68k:
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

	    /* We use Vector 0x45 (dec. 69) for the DUART */
	    move.l #timer_irq,$114

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
