/* Native silent ELKS WZR1 player. First-party DOS run/fill format unchanged.
 * GPL-3.0. The only platform dependencies are in backend.c. */
#include "backend.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/stat.h>

typedef unsigned char U8;
typedef unsigned long U32;
static U8 *packet;
static U32 *offsets,frames,duration,rendered,last=0xffffffffUL;
static unsigned fps,max_packet;
static int cached;
static U32 preload_ms,startup_ms,cache_bytes,cache_copy_bytes,owned_start;
static int file=-1;
static U32 start,elapsed,read_ms,check_ms,draw_ms,max_read,max_poll,poll_at,video_bytes;
static const char *error="",*reason="Complete";
static inline unsigned word(const U8 *p) {return p[0]|((unsigned)p[1]<<8);}
static inline U32 dword(const U8 *p) {return (U32)word(p)|((U32)word(p+2)<<16);}
int frame_pump(void)
{
    U32 now=clock_ms(),gap=now-poll_at;
    if(poll_at&&gap>max_poll)max_poll=gap;
    poll_at=now;return !stop_requested();
}
static int exact(void *data,unsigned count)
{
    U8 *p=data;unsigned n;int got;
    while(count){
        n=count;if(n>4096)n=4096;
        got=read(file,p,n);screen_after_io();
        if(got<0&&errno==EINTR&&!stop_requested())continue;
        if(got<=0)return 0;
        p+=got;count-=got;
        if(!frame_pump())return 0;
    }
    return 1;
}
static int open_movie(const char *path)
{
    U8 h[24];U32 head,size,i,span;struct stat st;unsigned bytes;
    file=open(path,O_RDONLY);
    if(file<0){error="cannot open movie";return 0;}
    if(!exact(h,24)||memcmp(h,"WZR1",4)||word(h+4)!=160||word(h+6)!=100){error="not a 160x100 WZR1 movie";return 0;}
    fps=word(h+8);frames=dword(h+12);duration=dword(h+16);
    if((fps!=2&&fps!=4&&fps!=8&&fps!=16)||!frames||frames>9600UL||
       !duration||duration>600000UL||duration>frames*1000UL/fps||
       duration<=(frames-1)*1000UL/fps){error="invalid movie timing";return 0;}
    head=(24UL+(frames+1)*4+511UL)&~511UL;
    if(word(h+10)!=head||dword(h+20)!=16384UL||fstat(file,&st)<0){error="invalid index header";return 0;}
    size=(U32)st.st_size;bytes=(unsigned)((frames+1)*4);
    offsets=malloc(bytes);
    if(!offsets){error="not enough memory for frame index";return 0;}
    if(!exact(offsets,bytes)||offsets[0]!=head||offsets[frames]!=size||(size&511UL)){error="invalid frame index";return 0;}
    for(i=0;i<frames;i++){
        span=offsets[i+1]-offsets[i];
        if((offsets[i]&511UL)||offsets[i+1]<=offsets[i]||span>16384UL){error="invalid frame bounds";return 0;}
        if(span>max_packet)max_packet=(unsigned)span;
    }
    packet=malloc(max_packet);
    if(!packet){error="not enough memory for frame packet";return 0;}
    return 1;
}
/* Explicit -p only: short movies up to 60K of frame data. The original
 * format, validation, playback clock, and streaming default are unchanged.
 * Report this up-front I/O separately; do not present it as free throughput. */
static int preload_movie(void)
{
    U32 bytes=offsets[frames]-offsets[0],t=clock_ms(),off,read_at,spent;
    unsigned n;
    if(bytes>61440UL){error="-p movie data exceeds 60K cache limit";return 0;}
    if(!movie_cache_open((unsigned)bytes)){error="not enough memory for -p cache";return 0;}
    if(lseek(file,(long)offsets[0],SEEK_SET)!=(long)offsets[0]){error="preload seek failed";return 0;}
    for(off=0;off<bytes;off+=n){
        n=(unsigned)(bytes-off);if(n>max_packet)n=max_packet;if(n>4096)n=4096;
        read_at=clock_ms();
        if(!exact(packet,n)){error="preload read failed";return 0;}
        spent=clock_ms()-read_at;if(spent>max_read)max_read=spent;
        movie_cache_put((unsigned)off,packet,n);video_bytes+=n;
        if(!frame_pump())return 0;
    }
    cache_bytes=bytes;cached=1;preload_ms=clock_ms()-t;return 1;
}
static int draw_frame(U32 frame,int opening)
{
    unsigned n=(unsigned)(offsets[frame+1]-offsets[frame]);
    unsigned len,off,chunk;
    U32 t=clock_ms(),spent;
    if(cached){
        for(off=0;off<n;off+=chunk){
            chunk=n-off;if(chunk>4096)chunk=4096;
            movie_cache_get(packet+off,(unsigned)(offsets[frame]-offsets[0])+off,chunk);
            cache_copy_bytes+=chunk;
            if(!frame_pump())return 0;
        }
    }else{
        if(lseek(file,(long)offsets[frame],SEEK_SET)!=(long)offsets[frame]||!exact(packet,n)){
            error="frame read failed";return 0;
        }
        video_bytes+=n;
    }
    spent=clock_ms()-t;read_ms+=spent;if(!cached&&spent>max_read)max_read=spent;
    if(!opening&&clock_ms()-start>=duration)return 1;
    t=clock_ms();len=word(packet);
    if(!len||len>n-2||!validate_packet(packet+2,len)){error="invalid run packet";return 0;}
    check_ms+=clock_ms()-t;t=clock_ms();
    if(!render_packet(packet+2))return 0;
    draw_ms+=clock_ms()-t;
    last=frame;rendered++;return 1;
}
int main(int argc,char **argv)
{
    const char *path,*shot=0;U32 now,target;
    int result=1,owned=0,hold=0,held=0,preload=0,arg=1,timing_started=0;
    for(;arg<argc&&argv[arg][0]=='-';arg++){
        if(!strcmp(argv[arg],"-h"))hold=1;
        else if(!strcmp(argv[arg],"-p"))preload=1;
        else if(!strcmp(argv[arg],"-s")&&arg+1<argc)shot=argv[++arg];
        else break;
    }
    if(arg+1!=argc||argv[arg][0]=='-'){
        fprintf(stderr,"usage: buddy160 [-p] [-h] [-s snapshot] movie.wzd\n");
        fprintf(stderr,"-p caches at most 60K; startup time is reported separately.\n");return 1;
    }
    path=argv[arg];
    if(!open_movie(path))goto done;
    if(!screen_open()){error=screen_error;goto done;}
    owned=1;max_poll=0;owned_start=poll_at=clock_ms();
    if(preload&&!preload_movie())goto done;
    if(!draw_frame(0,1))goto done;
    start=clock_ms();poll_at=start;timing_started=1;startup_ms=start-owned_start;
    for(;;){
        now=clock_ms()-start;
        if(!frame_pump()){reason="Stopped";result=0;break;}
        if(now>=duration){result=0;break;}
        target=now*fps/1000UL;if(target>=frames)target=frames-1;
        if(target!=last){if(!draw_frame(target,0))break;}
        else usleep(10000UL);
    }
    elapsed=clock_ms()-start;
    if(!result&&hold&&!stop_requested()){
        held=1;write(1,"BUDDY_HOLD\n",11);
        while(!stop_requested())usleep(10000UL);
    }
done:
    if(owned&&!timing_started)startup_ms=clock_ms()-owned_start;
    if(stop_requested()&&!held){reason="Stopped";error="";result=0;}
    if(owned&&!snapshot(shot)){error="snapshot write failed";result=1;}
    screen_close();
    if(!movie_cache_close()){error="movie cache release failed";result=1;}
    if(result)reason="Error";
    printf("status=%s error=%s held_after_timing=%d\n",reason,*error?error:"none",held);
    printf("frames=%lu/%lu last=%lu unshown=%lu\n",rendered,frames,last,frames-rendered);
    printf("duration_ms=%lu elapsed_ms=%lu opening_before_clock=1\n",duration,elapsed);
    printf("cached=%d cache_bytes=%lu preload_ms=%lu startup_ms=%lu\n",cached,cache_bytes,preload_ms,startup_ms);
    printf("cache_copy_bytes=%lu active_ms=%lu\n",cache_copy_bytes,startup_ms+elapsed);
    printf("fps=%u video_bytes_read=%lu\n",fps,video_bytes);
    printf("read_ms=%lu validate_ms=%lu draw_ms=%lu\n",read_ms,check_ms,draw_ms);
    printf("max_read_ms=%lu max_service_gap_ms=%lu\n",max_read,max_poll);
    printf("mode=%u restored=%u release_error=%d\n",screen_info.old_mode,screen_info.restored_mode,screen_info.release_error);
    printf("installed_mode=%u bios_kb=%u\n",screen_info.installed_mode,screen_info.bios_kb);
    printf("rows=%u installed=%u restored=%u scanline=%u\n",screen_info.old_rows,screen_info.installed_rows,screen_info.restored_rows,screen_info.installed_scanline);
    if(file>=0)close(file);
    free(offsets);free(packet);
    return result||screen_info.release_error;
}
