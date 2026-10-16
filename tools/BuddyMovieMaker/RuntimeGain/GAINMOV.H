/* Separate WZG1 revision1. Fixed buffers; preflight before hardware ownership. */
static int gainMarker(char *name,char *magic)
{
    int f,ok;U8 b[4];
    if(_dos_open(name,O_RDONLY,&f))return 0;
    ok=lseek(f,0L,2)==4L&&lseek(f,0L,0)==0L&&
        readExact(f,b,4)&&!memcmp(b,magic,4);
    _dos_close(f);return ok;
}
static int gainBundle(void)
{
    U8 h[20];int f,ok;
    gainFamily=pitMagic("MOVIE.WZV","WZV4")||pitMagic("MOVIE.WZM","WZM3");
    if(!gainFamily)return (access("GAIN.REQ",0)==0||access("MOVIE.WZG",0)==0)?fail(90):1;
    if(!(mode&1)||!gainMarker("GAIN.REQ","WZG1")||
       !gainMarker("INST.REQ","WZI1")||!pitDirectory())return fail(90);
    if(_dos_open("MOVIE.WZI",O_RDONLY,&f))return fail(90);
    ok=readExact(f,h,20)&&!memcmp(h,"WZI1",4)&&wordAt(h+4)==20&&
       wordAt(h+6)==8&&wordAt(h+18)==0x0102;
    _dos_close(f);if(!ok)return fail(91);
    gainFlags=wordAt(h+16);
    if(!(gainFlags&2)||(gainFlags&0xfff8)||!pitCheckMusic()||
       !pitCheckVideo()||longAt(h+12)!=pitDuration)return fail(91);
    duration=pitDuration;return 1;
}
static int gainFetch(void)
{
    U8 b[8];unsigned i;
    if(gainRead==gainCount){gainNextValid=0;return 1;}
    if(!readExact(gainFile,b,8))return fail(93);
    gainWhen=longAt(b);
    if(gainWhen>duration||(!gainRead&&gainWhen)||
       (gainRead&&gainWhen<=gainPrevious))return fail(94);
    for(i=0;i<4;i++){
        if(b[4+i]>15)return fail(94);gainNext[i]=b[4+i];
        if(gainRead==gainCount-1&&b[4+i]!=15)return fail(94);
    }
    if(gainRead==gainCount-1&&gainWhen!=duration)return fail(94);
    gainPrevious=gainWhen;gainRead++;gainNextValid=1;return 1;
}
static int gainOpen(void)
{
    U8 h[20];U32 length;
    if(!gainFamily)return 1;
    if(_dos_open("MOVIE.WZG",O_RDONLY,&gainFile))return fail(92);
    if(!readExact(gainFile,h,20)||memcmp(h,"WZG1",4)||wordAt(h+4)!=20||
       wordAt(h+6)!=8||longAt(h+12)!=duration||longAt(h+16))return fail(92);
    gainCount=longAt(h+8);length=(U32)lseek(gainFile,0L,2);
    if(gainCount<2||gainCount>10000UL||length!=20UL+gainCount*8UL)return fail(92);
    if(lseek(gainFile,20L,0)!=20L)return fail(93);
    while(gainRead<gainCount)if(!gainFetch())return 0;
    gainRead=gainPrevious=0;
    if(lseek(gainFile,20L,0)!=20L)return fail(93);
    return gainFetch();
}
/* Select the earliest stream. WZI precedes WZM precedes WZG at equal time. */
static unsigned gainWhich(U32 limit)
{
    U32 t=0xffffffffUL;unsigned which=0;
    if(nextInstrumentValid&&instrumentWhen<=limit){t=instrumentWhen;which=1;}
    if(nextValid&&nextState.when<=limit&&nextState.when<t){t=nextState.when;which=2;}
    if(gainNextValid&&gainWhen<=limit&&gainWhen<t)which=3;
    return which;
}
