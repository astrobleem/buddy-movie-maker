/* Test-only resident Escape injection when the PC speaker enters PWM.
   Runs only inside a disposable DOSBox guest, never in the shipped app. */
#include <dos.h>
#include <conio.h>
static void (_interrupt _far *previous)(void);
static volatile unsigned sent;
static unsigned dataSegment;
static unsigned began;
void _interrupt _far tick(void)
{
    unsigned _far *head;unsigned _far *tail;unsigned _far *key;unsigned next;
#ifdef STOP_MUSIC
    if(!sent&&(unsigned)(*(unsigned _far *)0x0040006cUL-began)>=8){
#else
    if(!sent&&(inp(0x61)&3)==3){
#endif
        head=(unsigned _far *)0x0040001aUL;
        tail=(unsigned _far *)0x0040001cUL;
        next=*tail+2;if(next>=0x3e)next=0x1e;
        if(next!=*head){
            key=(unsigned _far *)(0x00400000UL+*tail);
            *key=0x011b;*tail=next;sent=1;
        }
    }
    _chain_intr(previous);
}
int main(void)
{
    union REGS r;unsigned psp;
    began=*(unsigned _far *)0x0040006cUL;
    r.h.ah=0x62;intdos(&r,&r);psp=r.x.bx;
    _asm mov ax,ds
    _asm mov dataSegment,ax
    previous=_dos_getvect(0x1c);_dos_setvect(0x1c,tick);
    _dos_keep(0,dataSegment-psp+0x400);return 0;
}
