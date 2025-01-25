extern void nap20(void);
extern void ch375_rblock(uint8_t *ptr);
extern void ch375_wblock(uint8_t *ptr);

volatile uint8_t *ch375_dport= (uint8_t *)0xFFF001;
volatile uint8_t *ch375_sport= (uint8_t *)0xFFF003;

#define ch375_rdata()	*ch375_dport
#define ch375_rstatus()	*ch375_sport

#define ch375_wdata(x)	do { *ch375_dport = (x); } while(0)
#define ch375_wcmd(x)	do { *ch375_sport = (x); } while(0)

