/* Original ELKS console/file-independent display backend. GPL-3.0.
 * Lifecycle follows our elks-w16/ELKSWeb stock-console backends. */
#include "backend.h"
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <linuxmt/ntty.h>
#include <linuxmt/mem.h>
#include <arch/param.h>

typedef volatile unsigned char __far *far_bytes;
#define FAR(seg,off) ((far_bytes)(((unsigned long)(seg)<<16)|(unsigned)(off)))
static far_bytes video=FAR(0xb800,0);
static int console=-1,locked,raw,term_saved,changed;
static unsigned ctrl;
static volatile unsigned __far *ticks;
static int clock_checked;
static unsigned long input_at=~0UL;
static volatile int stopped;
static struct termios saved;
struct screen_info screen_info;
const char *screen_error="";

static unsigned bios(unsigned ax,unsigned *out)
{
    unsigned bx=out?*out:0;
    __asm__ volatile("push %%ds\n\tpush %%es\n\tpush %%bp\n\tpush %%si\n\tpush %%di\n\t"
        "int $0x10\n\tpop %%di\n\tpop %%si\n\tpop %%bp\n\tpop %%es\n\tpop %%ds"
        : "+a"(ax), "+b"(bx) : : "cx","dx","cc","memory");
    if(out)*out=bx;
    return ax;
}
static void outbyte(unsigned port,unsigned char value)
{__asm__ volatile("out %%al,%%dx" : : "a"(value),"d"(port) : "memory");}
static unsigned char inbyte(unsigned port)
{
    unsigned char v;
    __asm__ volatile("in %%dx,%%al" : "=a"(v) : "d"(port) : "memory");
    return v;
}
static unsigned crt(unsigned index)
{outbyte(0x3d4,(unsigned char)index);return inbyte(0x3d5);}
static void reg(unsigned index,unsigned value)
{
    unsigned pair=index|(value<<8);
    __asm__ volatile("out %%ax,%%dx" : : "a"(pair),"d"(0x3d4) : "memory");
}
static void on_signal(int sig) {(void)sig;stopped=1;}
unsigned long clock_ms(void)
{
    struct timeval t;
    unsigned ds,off,hi,lo;int fd;
    if(!clock_checked){
        clock_checked=1;fd=open("/dev/kmem",O_RDONLY);
        if(fd>=0){
            if(!ioctl(fd,MEM_GETDS,&ds)&&!ioctl(fd,MEM_GETJIFFADDR,&off))
                ticks=(volatile unsigned __far *)(((unsigned long)ds<<16)|off);
            close(fd);
        }
    }
    if(ticks){
        /* Stock ELKS exposes a read-only jiffies address. High/low/high
         * avoids tearing without masking the timer interrupt. */
        do{hi=ticks[1];lo=ticks[0];}while(hi!=ticks[1]);
        return (((unsigned long)hi<<16)|lo)*(1000/HZ);
    }
    gettimeofday(&t,0);
    return (unsigned long)t.tv_sec*1000UL+(unsigned long)t.tv_usec/1000UL;
}
static void drain(void)
{
    unsigned char bytes[16];unsigned tries=16;
    while(tries--&&read(console,bytes,sizeof(bytes))>0){}
}
int stop_requested(void)
{
    unsigned char bytes[16];int n,i;unsigned long now;
    if(console<0||stopped)return stopped!=0;
    /* Retry at the next stock kernel tick, rather than spending a system
     * call on every sub-millisecond render chunk. Signals stay immediate. */
    now=clock_ms();if(now==input_at)return 0;input_at=now;
    n=read(console,bytes,sizeof(bytes));
    for(i=0;i<n;i++){
        unsigned b=bytes[i];
        if(raw){
            if(b==0x1d)ctrl=1;else if(b==0x9d)ctrl=0;
            if(b==1||b==0x39||(ctrl&&b==0x2e))stopped=1;
        }else if(b==27||b==3||b==32)stopped=1;
    }
    return stopped!=0;
}
int screen_open(void)
{
    static const unsigned char regs[16]={113,80,90,10,127,6,100,112,2,1,32,0,0,0,0,0};
    struct termios term;unsigned bx=0,ax,i;
    screen_error="local console unavailable";
    console=open("/dev/tty1",O_RDWR|O_NONBLOCK);
    if(console<0)return 0;
    if(tcgetattr(console,&saved)<0)goto bad;
    term_saved=1;
    screen_error="console graphics ownership unavailable";
    if(ioctl(console,DCGET_GRAPH,(void *)0)<0)goto bad;
    locked=1;
    screen_info.old_mode=bios(0x0f00,0)&0x7f;
    screen_info.old_rows=crt(6);
    screen_error="first fullscreen backend requires ordinary IBM-compatible CGA text mode 3";
    if(screen_info.old_mode!=3)goto bad;
    ax=bios(0x1a00,&bx);
    if((ax&255)==0x1a&&(bx&255)!=2)goto bad; /* DCC 2 is CGA. */
    bx=0xff10;bios(0x1200,&bx);
    if(!(bx&0xff00)&&(bx&255)<=3)goto bad; /* EGA */
    screen_error="PCjr shared-memory layout is unsupported";
    if(*FAR(0xfc00,0)!=0x21&&*FAR(0xf000,0xfffe)==0xfd)goto bad;
    if(*FAR(0xfc00,0)==0x21){
        /* Stock ELKS uses INT12 at boot. Keep Tandy's existing 16K text
         * page; never switch to 32K mode 9 after those pages became live. */
        screen_info.bios_kb=*FAR(0x40,0x13)|((unsigned)*FAR(0x40,0x14)<<8);
        screen_error="Tandy CGA100 requires BIOS-reserved top 16K (INT12 <= 624K)";
        if(screen_info.bios_kb>624||screen_info.bios_kb<128)goto bad;
    }
    term=saved;
    term.c_lflag&=~(ECHO|ECHONL|ICANON|ISIG|IEXTEN);
    term.c_iflag&=~(ICRNL|INLCR|IGNCR|ISTRIP|IXON|IXOFF|BRKINT);
    term.c_cc[VMIN]=0;term.c_cc[VTIME]=0;
    screen_error="console input mode unavailable";
    if(tcsetattr(console,TCSAFLUSH,&term)<0)goto bad;
    drain();
    if(ioctl(console,DCSET_KRAW,(void *)0)>=0)raw=1;
    signal(SIGINT,on_signal);signal(SIGTERM,on_signal);signal(SIGHUP,on_signal);
    changed=1;bios(3,0);
    outbyte(0x3d8,1);
    for(i=0;i<16;i++)reg(i,regs[i]);
    *FAR(0x40,0x65)=9;
    outbyte(0x3d9,0);
    fill_cells(0,8000,0);
    outbyte(0x3d8,9);
    screen_info.installed_mode=3;
    screen_info.installed_rows=crt(6);
    screen_info.installed_scanline=crt(9);
    screen_error="";return 1;
bad:
    screen_close();return 0;
}
void screen_close(void)
{
    if(console<0)return;
    if(raw){if(ioctl(console,DCREL_KRAW,(void *)0)<0)screen_info.release_error=1;raw=0;}
    drain();
    if(changed){
        bios(screen_info.old_mode,0);changed=0;
        screen_info.restored_mode=bios(0x0f00,0)&0x7f;
        screen_info.restored_rows=crt(6);
    }
    if(locked){if(ioctl(console,DCREL_GRAPH,(void *)0)<0)screen_info.release_error=1;locked=0;}
    if(term_saved){if(tcsetattr(console,TCSAFLUSH,&saved)<0)screen_info.release_error=1;term_saved=0;}
    close(console);console=-1;
}
/* Stock bioshd's spin_timer() writes/clears character 79 even with the
 * console graphics lock held. Restore that glyph after completed file I/O;
 * preserve its movie attribute. Never write video before acquiring it. */
void screen_after_io(void)
{
    if(changed)video[158]=0xde;
}
void fill_cells(unsigned cell,unsigned count,unsigned char value)
{
    unsigned off=cell*2,word=0xde|((unsigned)value<<8);
    __asm__ volatile("push %%es\n\tmov %%dx,%%es\n\tcld\n\trep stosw\n\tpop %%es"
        : "+D"(off),"+c"(count) : "a"(word),"d"(0xb800) : "cc","memory");
}
void copy_cells(unsigned cell,unsigned count,const unsigned char *source)
{
    unsigned off=cell*2+1;
    while(count--){video[off]=*source++;off+=2;}
}
int snapshot(const char *path)
{
    unsigned char buf[512];unsigned off=0,i,n;int fd,got;
    if(!path)return 1;
    fd=open(path,O_WRONLY|O_CREAT|O_TRUNC,0644);
    if(fd<0)return 0;
    while(off<16000){
        n=16000-off;if(n>sizeof(buf))n=sizeof(buf);
        for(i=0;i<n;i++)buf[i]=video[off+i];
        got=write(fd,buf,n);
        if(got!=(int)n){close(fd);return 0;}
        off+=n;
    }
    return close(fd)==0;
}
