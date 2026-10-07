/* Isolated WZG1/WZV4/WZM3 gain player. MSC 6, /G0, small model. */
#include <dos.h>
#include <io.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <malloc.h>
#include "PERIODS.H"
#include "CAPTION.H"
#include "INSTR.H"
#include "DOSSND.H"
#define U32 unsigned long
#define U8 unsigned char
#define VIDEO_HEADER 24
#define MUSIC_HEADER 20
#define RECORD_SIZE 14
#define MUSIC_CHUNK 64
#define MAX_FRAME 32000
#define DAY_TICKS 0x1800b0UL
extern U32 _cdecl ClockTick(void);
extern unsigned _cdecl VideoMode(void);
extern void _cdecl SetMode(unsigned);
extern void _cdecl VideoRow(U8 *,unsigned,unsigned);
extern void _cdecl PsgByte(unsigned);
extern unsigned _cdecl KeyRead(void);
extern unsigned _cdecl IsWindows(void);
static int vf=-1,mf=-1,haveHardware,displayChanged,handlers,mode=2,error;
static int soundAcquired,soundFailure;
static unsigned oldMode,width,height,fps,frameBytes,rowBytes,xByte,yTop;
static U8 pixels[MAX_FRAME],musicBuffer[MUSIC_CHUNK*RECORD_SIZE];
static U8 _far *tailPixels;
static U32 tailInterval,tailAdvance,tailDrawBegin,tailDrawEnd,finalRestTarget,finalRestDispatch;
static unsigned bufferCount,bufferIndex;
static U32 frames,duration,eventCount,recordsRead,previousEvent;
static U32 startTick,lastService,lastFrame=0xffffffffUL;
static U32 playStart,playEnd,prerolled;
static int fullRange,captionEnabled,captionStatus,openingFrame;
static U32 rendered,dropped,applied,skipped,maxLate,totalLate,maxGap;
static U32 maxVideoRead,maxMusicRead,maxDraw,psgWrites,elapsedEnd;
static U8 volume[4]={15,15,15,15};
volatile int interrupted;
extern unsigned _cdecl PlayPCM(U8 _far *,unsigned);
extern unsigned _cdecl ValidatePCM(U8 _far *,unsigned);
extern unsigned Late,PCMReason;
extern unsigned _cdecl SpeakerPort(void);
unsigned pcmTickBase,pcmTickLimit;
#define MAX_CLIPS 16
#define MAX_CLIP_BYTES 48000
#define MAX_SPEECH_BYTES 360000UL
typedef struct {U32 start,end;unsigned length;U8 _far *data;} CLIP;
static CLIP clips[MAX_CLIPS];
static unsigned clipCount,clipNext,speechCompleted,speechGuarded,speechAvoided;
static U32 speechBytes,speechPlayed,speechLate,speechHeadSkipped,speechHeld;
static U32 clipActual[MAX_CLIPS];
static unsigned clipPlayed[MAX_CLIPS],clipReason[MAX_CLIPS];
static int speechResumePending;

static void (_interrupt _far *oldBreak)();
static void (_interrupt _far *oldCritical)();
typedef struct { U32 when; U8 note[4],velocity[4],retrigger; } STATE;
static STATE current,nextState,seed;
static int seedValid;
static int nextValid;
static int inf=-1,expressive,nextInstrumentValid;
static U32 instrumentCount,instrumentRead,instrumentPrevious;
static U32 instrumentWhen,synthQuantum=0xffffffffUL,synthPasses;
static unsigned synthFlags,periodOn[4],noiseReset;
static U32 noiseResets,noiseControls[4],noiseCoupledWrites;
static U8 programs[3],nextPrograms[3],synthActive[4];
static TVOICE voiceState[4];
static void synthState(STATE *,U32);
static void synthService(U32);
static int gainFamily,gainFlags,gainDirty,gainFile=-1,gainNextValid;
static U32 gainCount,gainRead,gainPrevious,gainWhen,gainApplied,gainFlushes;
static U8 gainExtra[4],gainNext[4];
static U32 gainSameQuantum,attackStarts[4];
typedef struct {U32 when,now,began[4];U8 extra[4],atten[4],preset[4],velocity[4];} GTRACE;
static GTRACE gainTrace[64];static unsigned gainTraceCount;
static unsigned wordAt(U8 *p) {return (unsigned)p[0]|((unsigned)p[1]<<8);}
static U32 longAt(U8 *p) {return (U32)wordAt(p)|((U32)wordAt(p+2)<<16);}
static U32 since(U32 first,U32 last) {return last>=first?last-first:DAY_TICKS-first+last;}
static U32 elapsed(void)
{
    if(openingFrame)return playStart;
    return playStart+since(startTick,ClockTick())*54925UL/1000UL;
}
static void output(unsigned b)
{
    if(b==0xe2)noiseControls[0]++;
    if(b==0xe4)noiseControls[1]++;
    if(b==0xe5)noiseControls[2]++;
    if(b==0xe6)noiseControls[3]++;
    if(b==0xe3||b==0xe7)noiseCoupledWrites++;
    if(DosSoundPsgByte(b)<0){soundFailure=1;error=86;return;}
    psgWrites++;
}
static void mute(void)
{
    unsigned i;if(!haveHardware)return;
    for(i=0;i<4;i++){output(0x9f|(i<<5));volume[i]=15;}
}
static int fail(int n) {error=n;return 0;}
static int readExact(int f,void *p,unsigned n)
{
    unsigned got;return !_dos_read(f,(void _far *)p,n,&got)&&got==n;
}
#include "PITMOV.H"
#include "GAINMOV.H"
void _interrupt _far onBreak(void) {interrupted=1;}
void _far onCritical(unsigned deverr,unsigned errcode,unsigned _far *devhdr)
{
    (void)deverr;(void)errcode;(void)devhdr;_hardresume(_HARDERR_FAIL);
}
static void cleanup(void)
{
    unsigned i;
    if(soundAcquired){DosSoundPwmEnd();DosSoundRelease();soundAcquired=0;}
    for(i=0;i<4;i++)volume[i]=15;
    for(i=0;i<clipCount;i++)if(clips[i].data){_ffree(clips[i].data);clips[i].data=0;}
    if(tailPixels){_ffree(tailPixels);tailPixels=0;}
    if(displayChanged){SetMode(oldMode);displayChanged=0;}
    if(vf>=0){_dos_close(vf);vf=-1;}
    if(mf>=0){_dos_close(mf);mf=-1;}
    if(inf>=0){_dos_close(inf);inf=-1;}
    if(gainFile>=0){_dos_close(gainFile);gainFile=-1;}
    if(pitFile>=0){_dos_close(pitFile);pitFile=-1;}
}
static void restoreHandlers(void)
{
    if(handlers){_dos_setvect(0x23,oldBreak);_dos_setvect(0x24,oldCritical);handlers=0;}
}
static int openVideo(void)
{
    U8 h[VIDEO_HEADER];U32 length,expected,step;unsigned got;
    if(_dos_open("MOVIE.WZV",O_RDONLY,&vf))return fail(10);
    if(!readExact(vf,h,VIDEO_HEADER))return fail(11);
    width=wordAt(h+4);height=wordAt(h+6);fps=wordAt(h+8);
    if(memcmp(h,gainFamily?"WZV4":pitRequired?"WZV3":"WZV2",4)||wordAt(h+10)!=VIDEO_HEADER||
       !(width>=4&&width<=320&&!(width&3)&&height>=1&&height<=200&&(fps==2||fps==4||fps==8)))return fail(12);
    frames=longAt(h+12);duration=longAt(h+16);
    frameBytes=width*height/2;rowBytes=width/2;
    if(longAt(h+20)!=(U32)frameBytes)return fail(12);
    step=1000UL/fps;
    if(!frames||frames>4800UL||!duration||duration>600000UL||
       duration>frames*step||duration<=(frames-1)*step)return fail(13);
    expected=VIDEO_HEADER+frames*(U32)frameBytes;length=(U32)lseek(vf,0L,2);
    if(length!=expected)return fail(14);
    tailInterval=duration-(frames-1)*step;
    if(gainFamily&&tailInterval<55UL){
        /* Read the short last frame before acquisition, so a disk read cannot
           erase its entire sub-tick interval. Display may advance <=one tick. */
        tailPixels=(U8 _far *)_fmalloc(frameBytes);if(!tailPixels)return fail(16);
        if(lseek(vf,(long)(expected-frameBytes),0)!=(long)(expected-frameBytes)||
           _dos_read(vf,tailPixels,frameBytes,&got)||got!=frameBytes)return fail(15);
    }
    xByte=(320-width)/4;yTop=(200-height)/2;return 1;
}
static int fetchEvent(void)
{
    U8 *p;unsigned i,wanted;U32 n,t,spent;
    if(recordsRead==eventCount){nextValid=0;return 1;}
    if(bufferIndex==bufferCount){
        n=eventCount-recordsRead;if(n>MUSIC_CHUNK)n=MUSIC_CHUNK;
        wanted=(unsigned)n*RECORD_SIZE;t=ClockTick();
        if(!readExact(mf,musicBuffer,wanted))return fail(23);
        spent=since(t,ClockTick());if(spent>maxMusicRead)maxMusicRead=spent;
        bufferCount=(unsigned)n;bufferIndex=0;
    }
    p=musicBuffer+bufferIndex*RECORD_SIZE;nextState.when=longAt(p);
    if(nextState.when>duration||(recordsRead&&nextState.when<=previousEvent)||
       (p[12]&0xf0)||p[13])return fail(24);
    for(i=0;i<4;i++){
        nextState.note[i]=p[4+i];nextState.velocity[i]=p[8+i];
        if(p[8+i]>127||(!p[4+i]&&p[8+i])||(p[4+i]&&!p[8+i])||
           (p[4+i]&&((unsigned)p[4+i]<(i==3?35U:45U)||(unsigned)p[4+i]>(i==3?81U:96U))))return fail(25);
    }
    nextState.retrigger=p[12];previousEvent=nextState.when;
    recordsRead++;bufferIndex++;nextValid=1;return 1;
}
static int openMusic(void)
{
    U8 h[MUSIC_HEADER];U32 musicDuration,length;
    if(_dos_open("MOVIE.WZM",O_RDONLY,&mf))return fail(20);
    if(!readExact(mf,h,MUSIC_HEADER))return fail(21);
    if(memcmp(h,gainFamily?"WZM3":pitRequired?"WZM2":"WZM1",4)||wordAt(h+4)!=MUSIC_HEADER||
       wordAt(h+6)!=RECORD_SIZE||longAt(h+16))return fail(22);
    eventCount=longAt(h+8);musicDuration=longAt(h+12);
    if(!eventCount||eventCount>10000UL||!musicDuration||musicDuration>600000UL)return fail(22);
    if((mode&2)&&musicDuration!=duration)return fail(26);
    duration=musicDuration;length=(U32)lseek(mf,0L,2);
    if(length!=MUSIC_HEADER+eventCount*RECORD_SIZE)return fail(27);
    if(lseek(mf,MUSIC_HEADER,0)!=MUSIC_HEADER)return fail(23);
    return fetchEvent();
}
static int openCue(void)
{
    int f;U8 h[16];long length;
    if(_dos_open("MOVIE.CUE",O_RDONLY,&f)){
        if(fullRange){playStart=0;playEnd=duration;return 1;}
        return fail(50);
    }
    length=lseek(f,0L,2);
    if(length!=16L||lseek(f,0L,0)!=0L||!readExact(f,h,16)){
        _dos_close(f);return fail(51);
    }
    _dos_close(f);playStart=longAt(h+8);playEnd=longAt(h+12);
    if(memcmp(h,"WZC1",4)||longAt(h+4)!=duration||
       playStart>=playEnd||playEnd>duration)return fail(52);
    if(fullRange){playStart=0;playEnd=duration;}
    return 1;
}
static int fetchInstrument(void)
{
    U8 p[8];unsigned i;
    if(instrumentRead==instrumentCount){
        nextInstrumentValid=0;return 1;
    }
    if(!readExact(inf,p,8))return fail(73);
    instrumentWhen=longAt(p);
    if(instrumentWhen>duration||p[7]||
       (!instrumentRead&&instrumentWhen)||
       (instrumentRead&&instrumentWhen<=instrumentPrevious))
        return fail(74);
    for(i=0;i<3;i++){
        if(p[4+i]>112||(p[4+i]&15))return fail(74);
        nextPrograms[i]=p[4+i];
    }
    instrumentPrevious=instrumentWhen;instrumentRead++;
    nextInstrumentValid=1;return 1;
}
static int openInstrument(void)
{
    U8 h[20];unsigned i;U32 length;int required=0,f;
    if(access("INST.REQ",0)==0){
        required=1;
        if(_dos_open("INST.REQ",O_RDONLY,&f))return fail(70);
        length=(U32)lseek(f,0L,2);
        if(length!=4UL||lseek(f,0L,0)!=0L||
           !readExact(f,h,4)||memcmp(h,"WZI1",4)){
            _dos_close(f);return fail(70);
        }
        _dos_close(f);
    }
    if(access("MOVIE.WZI",0)!=0)return required?fail(70):1;
    if(!(mode&1))return fail(70);
    if(_dos_open("MOVIE.WZI",O_RDONLY,&inf))return fail(70);
    if(!readExact(inf,h,20)||memcmp(h,"WZI1",4)||
       wordAt(h+4)!=20||wordAt(h+6)!=8||
       longAt(h+12)!=duration||(wordAt(h+16)&(gainFamily?0xfff8:0xfffe))||
       wordAt(h+18)!=0x0102)return fail(71);
    instrumentCount=longAt(h+8);
    length=(U32)lseek(inf,0L,2);
    if(!instrumentCount||instrumentCount>10000UL||
       length!=20UL+instrumentCount*8UL)return fail(72);
    if(lseek(inf,20L,0)!=20L)return fail(73);
    /* Validate the whole sidecar with a fixed eight-byte buffer. */
    while(instrumentRead<instrumentCount)
        if(!fetchInstrument())return 0;
    instrumentRead=instrumentPrevious=0;
    if(lseek(inf,20L,0)!=20L||!fetchInstrument())return 0;
    for(i=0;i<3;i++)programs[i]=nextPrograms[i];
    if(!fetchInstrument())return 0;
    synthFlags=(wordAt(h+16)&1)?2:0;expressive=1;
    return 1;
}
static void synthState(STATE *s,U32 when)
{
    unsigned i,n,atten,preset,period;
    for(i=0;i<4;i++){
        if(current.note[i]==s->note[i]&&
           current.velocity[i]==s->velocity[i]&&
           !(s->retrigger&(1<<i)))continue;
        n=s->note[i];synthActive[i]=(U8)(n!=0);
        if(i==3)noiseReset=0;
        if(!n)continue;
        atten=14-(((unsigned)s->velocity[i]-1)*14)/126;
        if(i<3){preset=programs[i]>>4;period=periods[n-45];}
        else {
            preset=9;period=0xe6;
            if(n==35||n==36){preset=8;period=0xe2;}
            else if(n==38||n==40)period=0xe5;
            else if(n==42||n==44||n==46){preset=10;period=0xe4;}
            noiseReset=1;
        }
        InstStart(voiceState+i,preset,atten,period,when/55UL);
        attackStarts[i]++;
    }
    current=*s;synthQuantum=0xffffffffUL;
}
static void synthService(U32 now)
{
    unsigned i,period,atten;U32 quantum;int same;
    if(!expressive)return;
    quantum=now/55UL;same=quantum==synthQuantum;
    if(same&&!gainDirty)return;
    if(gainDirty)gainFlushes++;
    if(same&&gainDirty)gainSameQuantum++;
    synthQuantum=quantum;synthPasses++;
    for(i=0;i<4;i++){
        atten=15;period=periodOn[i];
        if(synthActive[i]&&
           !InstRead(voiceState+i,quantum,i==3?0:synthFlags,
                     &period,&atten))
            synthActive[i]=0;
        if(gainFamily){atten+=gainExtra[i];if(atten>15)atten=15;}
        if(i==3){
            if(synthActive[i]&&noiseReset){
                output(0xff);volume[3]=15;output(period);
                periodOn[3]=period;noiseResets++;
            }
            noiseReset=0;
        }else if(!same&&synthActive[i]&&period!=periodOn[i]){
            output(0x80|(i<<5)|(period&15));output(period>>4);
            periodOn[i]=period;
        }
        if(atten!=volume[i]){
            output(0x90|(i<<5)|atten);volume[i]=(U8)atten;
        }
    }
    gainDirty=0;
}
static void traceGain(U32 when,U32 now)
{
    GTRACE *p;unsigned i;if(gainTraceCount>=64)return;
    p=gainTrace+gainTraceCount++;p->when=when;p->now=now;
    for(i=0;i<4;i++){
        p->began[i]=voiceState[i].began;p->extra[i]=gainExtra[i];
        p->atten[i]=volume[i];p->preset[i]=voiceState[i].preset;
        p->velocity[i]=voiceState[i].velocity;
    }
}
static int openSpeech(void)
{
    int f;U8 h[12];unsigned i,n,got;U32 total=0,previous=0;CLIP *c;
    if(access("SPEECH.PCM",0)!=0)return 1;
    if(_dos_open("SPEECH.PCM",O_RDONLY,&f))return fail(60);
    if(!readExact(f,h,8)||memcmp(h,"SPC1",4)||wordAt(h+6)||
       !(n=wordAt(h+4))||n>MAX_CLIPS){_dos_close(f);return fail(61);}
    clipCount=n;
    for(i=0;i<n;i++){
        c=clips+i;
        if(!readExact(f,h,12)){_dos_close(f);return fail(61);}
        c->start=longAt(h);c->end=longAt(h+4);c->length=wordAt(h+8);
        if(wordAt(h+10)||(i&&c->start<previous+150UL)||
           c->start>=c->end||c->end>duration||
           !c->length||c->length>MAX_CLIP_BYTES||
           (c->end-c->start)*6UL!=(U32)c->length){
            _dos_close(f);return fail(62);
        }
        previous=c->end;total+=c->length;if(total>MAX_SPEECH_BYTES){_dos_close(f);return fail(62);}
        c->data=(U8 _far *)_fmalloc(c->length);
        if(!c->data){_dos_close(f);return fail(63);}
        if(_dos_read(f,c->data,c->length,&got)||got!=c->length){_dos_close(f);return fail(61);}
        if(!ValidatePCM(c->data,c->length)){_dos_close(f);return fail(62);}
    }
    if(_dos_read(f,h,1,&got)||got){_dos_close(f);return fail(61);}
    _dos_close(f);speechBytes=total;return 1;
}
static int primeMusic(void)
{
    unsigned which;
    if(!(mode&1))return 1;
    if(gainFamily){
        while((which=gainWhich(playStart))!=0){
            if(which==1){memcpy(programs,nextPrograms,3);if(!fetchInstrument())return 0;}
            else if(which==2){
                synthState(&nextState,nextState.when);seed=nextState;seedValid=1;prerolled++;
                if(!fetchEvent())return 0;
            }else{
                memcpy(gainExtra,gainNext,4);gainDirty=1;gainApplied++;
                if(!gainFetch())return 0;
            }
        }return 1;
    }
    if(expressive){
        /* Reconstruct attack-time programs and phases without port I/O. */
        while((nextValid&&nextState.when<=playStart)||
              (nextInstrumentValid&&instrumentWhen<=playStart)){
            if(nextInstrumentValid&&instrumentWhen<=playStart&&
               (!nextValid||instrumentWhen<=nextState.when)){
                memcpy(programs,nextPrograms,3);if(!fetchInstrument())return 0;
            }else{
                synthState(&nextState,nextState.when);seed=nextState;seedValid=1;prerolled++;
                if(!fetchEvent())return 0;
            }
        }return 1;
    }
    while(nextValid&&nextState.when<=playStart){
        seed=nextState;seedValid=1;prerolled++;if(!fetchEvent())return 0;
    }
    return 1;
}
static void soundState(STATE *s)
{
    unsigned i,n,period,atten,change;
    if(expressive){synthState(s,s->when);synthService(elapsed());return;}
    for(i=0;i<4;i++){
        change=current.note[i]!=s->note[i]||current.velocity[i]!=s->velocity[i]||
               (s->retrigger&(1<<i));
        if(!change)continue;
        output(0x9f|(i<<5));volume[i]=15;n=s->note[i];if(!n)continue;
        atten=14-(((unsigned)s->velocity[i]-1)*14)/126;
        if(i<3){period=periods[n-45];output(0x80|(i<<5)|(period&15));output(period>>4);}
        else {period=0xe6;if(n==35||n==36)period=0xe2;
              else if(n==38||n==40)period=0xe5;
              else if(n==42||n==44||n==46)period=0xe4;output(period);}
        output(0x90|(i<<5)|atten);volume[i]=(U8)atten;
    }
    current=*s;
}
static int musicService(U32 now)
{
    STATE pending;U32 count=0,late,gap,group;unsigned which;int changed;
    if(openingFrame)return 1;
    if(soundFailure)return fail(86);
    if(pitPwm)return 1;
    if(now>=playEnd){if(!gainFamily)return 1;now=playEnd;}
    if(!pitService(now))return 0;
    gap=now-lastService;if(gap>maxGap)maxGap=gap;lastService=now;
    if(!(mode&1))return 1;
    if(gainFamily){
        while((which=gainWhich(now))!=0){
            group=which==1?instrumentWhen:which==2?nextState.when:gainWhen;
            changed=0;
            do {
                if(which==1){memcpy(programs,nextPrograms,3);if(!fetchInstrument())return 0;}
                else if(which==2){
                    if((current.note[0]||current.note[1]||current.note[2]||current.note[3])&&
                       !nextState.note[0]&&!nextState.note[1]&&!nextState.note[2]&&!nextState.note[3]){
                        finalRestTarget=nextState.when;finalRestDispatch=elapsed();
                    }
                    synthState(&nextState,nextState.when);applied++;
                    late=now-nextState.when;if(late>maxLate)maxLate=late;totalLate+=late;
                    if(!fetchEvent())return 0;
                }else{
                    memcpy(gainExtra,gainNext,4);gainDirty=1;gainApplied++;
                    changed=1;
                    if(!gainFetch())return 0;
                }
            }while((which=gainWhich(group))!=0);
            synthService(now);
            if(changed)traceGain(group,now);
        }
        synthService(now);return 1;
    }
    if(expressive){
        /* Merge both streams by event time, before rendering current phase.
           A late attack snapshots its own program, not wall-clock state. */
        while((nextValid&&nextState.when<=now)||
              (nextInstrumentValid&&instrumentWhen<=now)){
            if(nextInstrumentValid&&instrumentWhen<=now&&
               (!nextValid||instrumentWhen<=nextState.when)){
                memcpy(programs,nextPrograms,3);
                if(!fetchInstrument())return 0;
            }else{
                synthState(&nextState,nextState.when);applied++;
                late=now-nextState.when;
                if(late>maxLate)maxLate=late;totalLate+=late;
                if(!fetchEvent())return 0;
            }
        }
        synthService(now);return 1;
    }
    while(nextValid&&nextState.when<=now){pending=nextState;count++;if(!fetchEvent())return 0;}
    if(!count)return 1;
    applied++;skipped+=count-1;late=now-pending.when;totalLate+=late;if(late>maxLate)maxLate=late;
    soundState(&pending);return 1;
}
static int captionMusic(void) {return musicService(elapsed());}
static int speechService(U32 now)
{
    CLIP *c;unsigned i,head,n,got,caught,why,total;
    U32 end,guard,boundary,logical;
    if(!clipCount)return 1;
    while(clipNext<clipCount){
        c=clips+clipNext;
        if(c->end<=playStart||c->start<playStart||c->end>playEnd||now>=c->end){clipNext++;continue;}
        if(now<c->start)return 1;
        /* Speech never takes over an active or imminent PSG passage. */
        for(i=0;i<4;i++)if(current.note[i])break;
        if(i<4){speechAvoided++;clipNext++;continue;}
        /* Consume only silent score states before entering the PWM loop.
           No DOS reads or drawing occur inside that loop. */
        while(nextValid&&nextState.when<c->end+80UL){
            for(i=0;i<4;i++)if(nextState.note[i])break;
            if(i<4)break;
            prerolled++;if(!fetchEvent())return 0;
        }
        if(nextValid&&nextState.when<c->end+80UL){
            speechAvoided++;clipNext++;continue;
        }
        head=(unsigned)((now-c->start)*6UL);if(head>=c->length){clipNext++;continue;}
        speechHeadSkipped+=head;clipActual[clipNext]=now;total=0;why=0;
        if(DosSoundPwmBegin()<0)return fail(86);
        pitPwm=1;pitNote=0;pitAttack=0;
        for(i=0;i<4;i++)volume[i]=15;
        guard=c->end+100UL;
        if(nextValid&&nextState.when>60UL&&guard>nextState.when-60UL)guard=nextState.when-60UL;
        while(head<c->length){
            /* Render only at a caption boundary, with the speaker stopped.
               The source offset catches up afterward; music/movie clocks
               never pause. No C, drawing, or DOS calls enter the PWM loop. */
            now=elapsed();lastService=now;logical=c->start+(U32)head/6UL;
            if(logical<now)logical=now;
            if(captionEnabled&&(mode&2)&&!CaptionService(logical,captionMusic)){
                DosSoundPwmEnd();pitPwm=0;return 0;
            }
            now=elapsed();if(now>=c->end)break;
            caught=(unsigned)((now-c->start)*6UL);
            if(caught>head){speechHeadSkipped+=caught-head;head=caught;}
            if(head>=c->length)break;
            n=c->length-head;
            if(captionEnabled&&(mode&2)){
                boundary=CaptionNextTime();
                if(boundary<=c->start+(U32)head/6UL)continue;
                if(boundary<c->end&&boundary>c->start+(U32)head/6UL)
                    n=(unsigned)((boundary-c->start)*6UL)-head;
            }
            pcmTickBase=(unsigned)ClockTick();
            pcmTickLimit=(unsigned)((guard-now)*1000UL/54925UL);
            if(!pcmTickLimit)pcmTickLimit=1;
            got=PlayPCM(c->data+head,n);head+=got;total+=got;
            speechPlayed+=got;speechLate+=Late;why=PCMReason;
            if(why||interrupted)break;
        }
        DosSoundPwmEnd();pitPwm=0;
        end=elapsed();clipPlayed[clipNext]=total;clipReason[clipNext]=why;clipNext++;
        speechResumePending=1;
        if(why==1||interrupted)return 0;
        if(why==2)speechGuarded++;else speechCompleted++;
        /* Only current-time states may resume after exclusive PWM. */
        for(i=0;i<4;i++)periodOn[i]=0xffff;
        if(gainFamily){for(i=0;i<4;i++)volume[i]=0xff;gainDirty=1;}
        synthQuantum=0xffffffffUL;
        if(!musicService(end))return 0;
        lastService=end;
        if(captionEnabled&&(mode&2)&&!CaptionService(end,captionMusic))return 0;
        return 1;
    }
    return 1;
}
static int videoService(U32 now)
{
    U32 frame,t,spent,offset;unsigned y,screenY,bankOffset,done,chunk;
    if(!(mode&2))return 1;
    frame=now*fps/1000UL;if(frame>=frames)frame=frames-1;
    if(tailPixels&&playEnd==duration&&now<duration&&now+55UL>=duration){
        frame=frames-1;
    }
    if(frame==lastFrame)return 1;
    if(lastFrame!=0xffffffffUL&&frame>lastFrame+1){
        dropped+=frame-lastFrame-1;if(speechResumePending)speechHeld+=frame-lastFrame-1;
    }
    speechResumePending=0;
    t=ClockTick();offset=VIDEO_HEADER+frame*(U32)frameBytes;
    if(tailPixels&&frame==frames-1){_fmemcpy((void _far *)pixels,tailPixels,frameBytes);goto draw;}
    if(lseek(vf,(long)offset,0)!=(long)offset)return fail(15);
    for(done=0;done<frameBytes;done+=chunk){
        chunk=frameBytes-done;if(chunk>4096)chunk=4096;
        if(!readExact(vf,pixels+done,chunk))return fail(15);
        spent=since(t,ClockTick());if(spent>maxVideoRead)maxVideoRead=spent;
        now=elapsed();if(now>=playEnd)return 1;
        /* DOS read has returned before servicing the independent music handle. */
        if(!musicService(now))return 0;
        t=ClockTick();
    }
draw:
    if(tailPixels&&frame==frames-1){
        tailDrawBegin=elapsed();
        if(tailDrawBegin<(frames-1)*1000UL/fps)
            tailAdvance=(frames-1)*1000UL/fps-tailDrawBegin;
    }
    t=ClockTick();
    for(y=0;y<height;y++){
        screenY=y+yTop;bankOffset=(screenY&3)*8192+(screenY>>2)*160+xByte;
        VideoRow(pixels+y*rowBytes,bankOffset,rowBytes);
        if((y&15)==15||y+1==height){
            spent=since(t,ClockTick());if(spent>maxDraw)maxDraw=spent;
            if(!musicService(elapsed()))return 0;
            t=ClockTick();
        }
    }
    if(tailPixels&&frame==frames-1)tailDrawEnd=elapsed();
    lastFrame=frame;rendered++;return 1;
}
static void report(char *reason)
{
    FILE *f=fopen("MOVPLAY.LOG","w");unsigned i,j,mask=0;GTRACE *p;
    if(!f)return;
    for(i=0;i<4;i++)if(volume[i]!=15)mask|=1<<i;
    fprintf(f,"%s\nversion=4\nbuild=WZG1-01\nmode=%d\nerror=%d\n",reason,mode,error);
    fprintf(f,"gain_required=%d\ngain_flags=%d\ngain_records=%lu\ngain_applied=%lu\ngain_flushes=%lu\ngain_same_quantum_flushes=%lu\n",
            gainFamily,gainFlags,gainRead,gainApplied,gainFlushes,gainSameQuantum);
    for(i=0;i<4;i++)fprintf(f,"voice_%u_attacks=%lu\nvoice_%u_extra=%u\nvoice_%u_attack_quantum=%lu\n",
        i,attackStarts[i],i,(unsigned)gainExtra[i],i,voiceState[i].began);
    fprintf(f,"gain_trace_count=%u\n",gainTraceCount);
    fprintf(f,"final_rest_target_ms=%lu\nfinal_rest_dispatch_ms=%lu\nlast_frame_interval_ms=%lu\nlast_frame_advance_ms=%lu\nlast_frame_advance_limit_ms=55\nlast_frame_draw_begin_ms=%lu\nlast_frame_draw_end_ms=%lu\n",
        finalRestTarget,finalRestDispatch,tailInterval,tailAdvance,tailDrawBegin,tailDrawEnd);
    for(j=0;j<gainTraceCount;j++){
        p=gainTrace+j;fprintf(f,"gain_%u_time=%lu\ngain_%u_dispatch=%lu\n",j,p->when,j,p->now);
        for(i=0;i<4;i++)fprintf(f,"gain_%u_lane_%u=%lu,%u,%u,%u,%u\n",j,i,
            p->began[i],(unsigned)p->preset[i],(unsigned)p->velocity[i],
            (unsigned)p->extra[i],(unsigned)p->atten[i]);
    }
    fprintf(f,"pit_required=%d\npit_enabled=%d\npit_records=%lu\npit_applied=%lu\npit_skipped=%lu\n",pitRequired,pitEnabled,pitRead,pitApplied,pitSkipped);
    fprintf(f,"width=%u\nheight=%u\nfps=%u\nduration_ms=%lu\nelapsed_ms=%lu\n",width,height,fps,duration,elapsedEnd);
    fprintf(f,"frames=%lu\ndropped_frames=%lu\nmusic_events_applied=%lu\nmusic_events_skipped=%lu\nmusic_events_read=%lu\n",rendered,dropped,applied,skipped,recordsRead);
    fprintf(f,"music_max_late_ms=%lu\nmusic_total_late_ms=%lu\nservice_max_gap_ms=%lu\n",maxLate,totalLate,maxGap);
    fprintf(f,"video_read_chunk_bytes=4096\ndraw_batch_rows=16\n");
    fprintf(f,"video_read_max_ticks=%lu\nmusic_read_max_ticks=%lu\ndraw_max_ticks=%lu\n",maxVideoRead,maxMusicRead,maxDraw);
    fprintf(f,"play_start_ms=%lu\nplay_end_ms=%lu\nrun_elapsed_ms=%lu\nprerolled_records=%lu\nfull_range=%d\n",playStart,playEnd,elapsedEnd>=playStart?elapsedEnd-playStart:0UL,prerolled,fullRange);
    fprintf(f,"sound_mask_after_stop=%u\npsg_writes=%lu\nold_mode=%u\nrestored_mode=%u\n",mask,psgWrites,oldMode,VideoMode());
    fprintf(f,"speech_clips=%u\nspeech_bytes=%lu\nspeech_completed=%u\nspeech_guarded=%u\nspeech_avoided_music=%u\nspeech_samples=%lu\nspeech_late=%lu\nspeech_head_skipped_samples=%lu\nspeech_held_frames=%lu\nunexpected_video_drops=%lu\nspeaker_bits_after_stop=%u\n",clipCount,speechBytes,speechCompleted,speechGuarded,speechAvoided,speechPlayed,speechLate,speechHeadSkipped,speechHeld,dropped>=speechHeld?dropped-speechHeld:0UL,SpeakerPort()&3);
    fprintf(f,"caption_enabled=%d\ncaption_status=%d\ncaption_cues=%u\ncaption_updates=%u\n",captionEnabled,captionStatus,CaptionCount(),CaptionUpdates());
    fprintf(f,"expressive=%d\nsynth_flags=%u\nsynth_passes=%lu\n",expressive,synthFlags,synthPasses);
    fprintf(f,"noise_resets=%lu\nnoise_e2=%lu\n"
              "noise_e4=%lu\nnoise_e5=%lu\n"
              "noise_e6=%lu\nnoise_tone_clock_writes=%lu\n",
            noiseResets,noiseControls[0],noiseControls[1],
            noiseControls[2],noiseControls[3],noiseCoupledWrites);
    for(i=0;i<4;i++)fprintf(f,"voice_%u_preset=%u\n",i,
                          (unsigned)voiceState[i].preset);
    for(i=0;i<clipCount;i++)fprintf(f,"clip_%u_target=%lu-%lu actual=%lu samples=%u reason=%u\n",i,clips[i].start,clips[i].end,clipActual[i],clipPlayed[i],clipReason[i]);
    fclose(f);
}
int main(int argc,char **argv)
{
    unsigned key;U32 now;char *reason="Complete";int marker,i;union REGS r;
    fullRange=1;captionEnabled=1;if(access("MOVIE.WZM",0)==0)mode=3;
    for(i=1;i<argc;i++){
        if(strlen(argv[i])!=2||argv[i][0]!='/')goto usage;
        switch(argv[i][1]){
        case 'A':case 'a':mode=1;break;
        case 'V':case 'v':mode=2;break;
        case 'B':case 'b':mode=3;break;
        case 'F':case 'f':fullRange=1;break;

        case 'L':case 'l':captionEnabled=1;break;
        case 'P':case 'p':pitEnabled=1;break;
        case 'R':case 'r':fullRange=0;break;
        default:goto usage;
        }
    }
    if(IsWindows()){puts("Exit Windows first. MOVPLAY needs exclusive Tandy hardware.");return 1;}
    r.h.ah=0x30;intdos(&r,&r);if(r.h.al<3){puts("DOS 3.0 or later required.");return 1;}
    if(*(U8 _far *)0xfc000000UL!=0x21){puts("Tandy 1000 hardware required.");return 1;}
    oldMode=VideoMode();
    oldBreak=_dos_getvect(0x23);oldCritical=_dos_getvect(0x24);
    _dos_setvect(0x23,onBreak);_harderr(onCritical);handlers=1;
    if(!gainBundle()||!pitBundle()||((mode&2)&&!openVideo())||((mode&1)&&!openMusic())||
       !openCue()||!openInstrument()||!gainOpen()||!openSpeech()||!pitGuards()||!pitOpen()||!primeMusic()||!pitPrime()){
        reason="Error";goto done;
    }
    if(pitRequired&&!pitEnabled){fail(84);reason="Error";goto done;}
    if(DosSoundAcquire(DS_PSG|(pitRequired?DS_PIT:0)|(clipCount?DS_PWM:0))<0){
        fail(87);reason="Error";goto done;
    }
    soundAcquired=1;haveHardware=1;mute();
    if(captionEnabled&&(mode&2)&&height<=160)captionStatus=CaptionLoad("MOVIE.LRC",duration);
    if(mode&2){displayChanged=1;SetMode(9);if(VideoMode()!=9){fail(40);reason="Error";goto done;}}
    if(!_dos_creat("DOSSTART.LOG",0,&marker))_dos_close(marker);
    startTick=ClockTick();lastService=playStart;
    /* Prepare frame zero without consuming any timed score states.
       The video and score clocks start together on the ready image. */
    if(playStart==0&&(mode&2)){
        openingFrame=1;
        if(!videoService(0)){openingFrame=0;reason="Error";goto done;}
        openingFrame=0;
        startTick=ClockTick();lastService=0;
    }
    if(seedValid){if(expressive)synthService(playStart);else soundState(&seed);applied++;}
    if(gainFamily)traceGain(playStart,playStart);
    if(!pitService(playStart)){reason="Error";goto done;}
    for(;;){
        key=KeyRead();if(interrupted||key==3||key==27||key==32){reason="Stopped";break;}
        now=elapsed();
        if(now>=playEnd){if(!pitService(playEnd)||(gainFamily&&!musicService(playEnd)))reason="Error";break;}
        if(!musicService(now)){reason="Error";break;}
        if((mode&2)&&lastFrame==0xffffffffUL&&!videoService(now)){reason="Error";break;}
        now=elapsed();
        if(!speechService(now)){reason=error?"Error":"Stopped";break;}
        now=elapsed();
        if(!musicService(now)){reason="Error";break;}
        if(!videoService(now)||!musicService(elapsed())){reason="Error";break;}
        if(captionEnabled&&(mode&2)&&!CaptionService(elapsed(),captionMusic)){reason="Error";break;}
    }
    elapsedEnd=elapsed();
done:
    cleanup();report(reason);restoreHandlers();printf("MOVPLAY: %s. Error %d. See MOVPLAY.LOG.\n",reason,error);
    if(speechGuarded||speechAvoided)puts("Some speech shortened/skipped to protect music. See MOVPLAY.LOG.");
    if(captionEnabled&&(mode&2)&&captionStatus<0)puts("Invalid subtitle file: captions disabled.");
    return error?1:0;
usage:
    puts("MOVPLAY [/P enable required PIT voice] [/A audio | /V video | /B both]\nControlled foreground DOS session only; no other sound/timer writers.\nEscape/Space: stop; relaunch to restart.");return 1;
}
