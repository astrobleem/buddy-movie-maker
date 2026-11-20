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
#include <malloc.h>

typedef volatile unsigned char __far *far_bytes;
#define FAR(seg,off) ((far_bytes)(((unsigned long)(seg)<<16)|(unsigned)(off)))
static far_bytes video=FAR(0xb800,0);
static int console=-1,locked,raw,term_saved,changed;
static unsigned ctrl;
static volatile unsigned __far *ticks;
static int clock_checked;
static int vga;
static unsigned pairs[16];
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
    static const unsigned char regs[16]={113,80,90,10,127,6,100,112,2,1,32,0,0,BUDDY_CGA_START/2,0,0};
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
    screen_error="fullscreen playback requires initial BIOS text mode 3";
    if(screen_info.old_mode!=3)goto bad;
    ax=bios(0x1a00,&bx);
    if((ax&255)==0x1a){
        unsigned adapter=bx&255;
        vga=adapter==7||adapter==8;
        screen_error="requires CGA, Tandy CGA-compatible video, or BIOS VGA";
        if(!vga&&adapter!=2)goto bad;
    }
    if(!vga){
        bx=0xff10;bios(0x1200,&bx);
        if(!(bx&0xff00)&&(bx&255)<=3)goto bad; /* EGA */
    }
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
    changed=1;
    if(vga){
        bios(0x13,0);
        screen_error="VGA BIOS mode 13h unavailable";
        if((bios(0x0f00,0)&0x7f)!=0x13)goto bad;
        video=FAR(0xa000,0);
        /* Explicit standard RGBI DAC; do not rely on a BIOS palette. */
        outbyte(0x3c8,0);
        for(i=0;i<16;i++){
            unsigned bright=(i&8)?21:0;
            unsigned red=((i&4)?42:0)+bright;
            unsigned green=((i&2)?42:0)+bright;
            unsigned blue=((i&1)?42:0)+bright;
            if(i==6)green=21;
            outbyte(0x3c9,(unsigned char)red);
            outbyte(0x3c9,(unsigned char)green);
            outbyte(0x3c9,(unsigned char)blue);
            pairs[i]=i|(i<<8);
        }
        screen_info.installed_mode=0x13;
        screen_info.installed_rows=crt(6);
        screen_info.installed_scanline=crt(9);
        screen_error="";return 1;
    }
    bios(3,0);
    outbyte(0x3d8,1);
    for(i=0;i<16;i++)reg(i,regs[i]);
    *FAR(0x40,0x65)=9;
    outbyte(0x3d9,0);
    fill_cells(0,8000,0);
    outbyte(0x3d8,9);
    screen_info.installed_mode=3;
    /* Start-address readback is not portable on 6845 variants. Report
     * the programmed offset; native framebuffer captures verify the view. */
    screen_info.viewport_word=BUDDY_CGA_START/2;
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
/* Same 160x100 pixels, doubled to 320x200 in VGA's separate framebuffer.
 * WZR1 high nibble is left, low nibble right; input bytes never change. */
static void vga_cells(unsigned cell,unsigned count,unsigned char value,const unsigned char *source)
{
    unsigned row,x,n,off,off2,i,left,right;unsigned char byte;
    while(count){
        row=cell/80;x=cell%80;n=80-x;if(n>count)n=count;
        off=row*640+x*4;off2=off+320;
        for(i=0;i<n;i++){
            byte=source?*source++:value;left=pairs[byte>>4];right=pairs[byte&15];
            *(volatile unsigned __far *)(video+off)=left;
            *(volatile unsigned __far *)(video+off+2)=right;
            *(volatile unsigned __far *)(video+off2)=left;
            *(volatile unsigned __far *)(video+off2+2)=right;
            off+=4;off2+=4;
        }
        cell+=n;count-=n;
    }
}
int render_cga_packet(const unsigned char *commands);
int frame_pump(void);
int render_packet(const unsigned char *commands)
{
    unsigned cmd,count,cell=0,n,budget=512;unsigned char value;
    if(!vga)return render_cga_packet(commands);
    while(cell<8000){
        cmd=commands[0]|((unsigned)commands[1]<<8);commands+=2;
        count=cmd&0x7fff;value=0;if(cmd&0x8000)value=*commands++;
        while(count){
            n=count;if(n>budget)n=budget;
            vga_cells(cell,n,value,(cmd&0x8000)?0:commands);
            if(!(cmd&0x8000))commands+=n;
            cell+=n;count-=n;budget-=n;
            if(!budget){if(!frame_pump())return 0;budget=512;}
        }
    }
    return 1;
}
void fill_cells(unsigned cell,unsigned count,unsigned char value)
{
    unsigned off=BUDDY_CGA_START+cell*2,word=0xde|((unsigned)value<<8);
    __asm__ volatile("push %%es\n\tmov %%dx,%%es\n\tcld\n\trep stosw\n\tpop %%es"
        : "+D"(off),"+c"(count) : "a"(word),"d"(0xb800) : "cc","memory");
}
void copy_cells(unsigned cell,unsigned count,const unsigned char *source)
{
    unsigned off=BUDDY_CGA_START+cell*2+1;
    while(count--){video[off]=*source++;off+=2;}
}
int snapshot(const char *path)
{
    unsigned char buf[512];unsigned off=0,i,n;int fd,got;
    if(!path)return 1;
    fd=open(path,O_WRONLY|O_CREAT|O_TRUNC,0644);
    if(fd<0)return 0;
    while(off<(vga?64000U:16000U)){
        n=(vga?64000U:16000U)-off;if(n>sizeof(buf))n=sizeof(buf);
        for(i=0;i<n;i++)buf[i]=video[off+i+(vga?0:BUDDY_CGA_START)];
        got=write(fd,buf,n);
        if(got!=(int)n){close(fd);return 0;}
        off+=n;
    }
    return close(fd)==0;
}

/* Optional bounded cache uses memory owned by the stock ELKS allocator,
 * never a guessed physical RAM range. All transfers are even-sized WZR1
 * sector spans. Keep DS unchanged so asynchronous signal handlers are safe. */
static unsigned short cache_segment;
int movie_cache_open(unsigned bytes)
{
    if(!bytes||bytes>61440U)return 0;
    return _fmemalloc((bytes+15U)>>4,&cache_segment)==0;
}
void movie_cache_put(unsigned offset,const void *data,unsigned bytes)
{
    unsigned src=(unsigned)data,words=bytes>>1;
    __asm__ volatile("push %%es\n\tmov %%ax,%%es\n\tcld\n\trep movsw\n\tpop %%es"
        : "+S"(src),"+D"(offset),"+c"(words) : "a"(cache_segment) : "cc","memory");
}
void movie_cache_get(void *data,unsigned offset,unsigned bytes)
{
    /* WZR1 sectors are multiples of 512. Copy four words per branch;
     * source uses ES overrides, leaving DS and interrupts untouched. */
    unsigned dest=(unsigned)data,groups=bytes>>3,seg=cache_segment;
    __asm__ volatile("push %%es\n\tmov %%ax,%%es\n\tcld\n\t"
        "1: es lodsw\n\tmov %%ax,(%%di)\n\tes lodsw\n\tmov %%ax,2(%%di)\n\t"
        "es lodsw\n\tmov %%ax,4(%%di)\n\tes lodsw\n\tmov %%ax,6(%%di)\n\t"
        "add $8,%%di\n\tloop 1b\n\tpop %%es"
        : "+S"(offset),"+D"(dest),"+c"(groups),"+a"(seg) : : "cc","memory");
}
int movie_cache_close(void)
{
    int ok=1;
    if(cache_segment){ok=_fmemfree(cache_segment)==0;cache_segment=0;}
    return ok;
}
