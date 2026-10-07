/* Frozen MML3 revision1 reader. Fixed buffers, no sound or video writes.
 * Included after DOSPLAY's byte readers and speech structures. */
static int pitRequired,pitEnabled,pitFile=-1,pitNextValid,pitPwm;
static U32 pitCount,pitRead,pitDuration,pitWhen,pitPrevious,pitApplied,pitSkipped;
static unsigned pitNextNote,pitNextFlags,pitNote;
static int pitNeedsSync;
static U32 pitAttack;
static int pitMagic(char *name,char *magic)
{
    int f,yes;U8 b[4];
    if(_dos_open(name,O_RDONLY,&f))return 0;
    yes=readExact(f,b,4)&&!memcmp(b,magic,4);_dos_close(f);return yes;
}
static int pitMarker(void)
{
    int f,ok;U8 b[4];
    if(_dos_open("PIT.REQ",O_RDONLY,&f))return 0;
    ok=lseek(f,0L,2)==4L&&lseek(f,0L,0)==0L&&readExact(f,b,4)&&!memcmp(b,"WZP1",4);
    _dos_close(f);return ok;
}
static int pitDirectory(void)
{
    struct find_t file;char *ext;
    if(_dos_findfirst("*.*",0x27,&file))return 0;
    do {
        ext=strrchr(file.name,'.');if(!ext)continue;
        if(!strnicmp(ext,".WZ",3)){
            if(stricmp(file.name,"MOVIE.WZV")&&stricmp(file.name,"MOVIE.WZM")&&
               stricmp(file.name,"MOVIE.WZI")&&stricmp(file.name,"MOVIE.WZP")&&
               (!gainFamily||stricmp(file.name,"MOVIE.WZG")))return 0;
        }else if(!stricmp(ext,".REQ")&&stricmp(file.name,"PIT.REQ")&&stricmp(file.name,"INST.REQ")&&
                 (!gainFamily||stricmp(file.name,"GAIN.REQ")))return 0;
    }while(!_dos_findnext(&file));
    return 1;
}
static int pitCheckMusic(void)
{
    int f,ok=0;U8 h[20],b[14];U32 count,i,time,previous=0;unsigned j;
    if(_dos_open("MOVIE.WZM",O_RDONLY,&f))return 0;
    if(!readExact(f,h,20)||memcmp(h,gainFamily?"WZM3":"WZM2",4)||wordAt(h+4)!=20||wordAt(h+6)!=14||longAt(h+16))goto finish;
    count=longAt(h+8);pitDuration=longAt(h+12);
    if(count<2||count>10000UL||!pitDuration||pitDuration>600000UL||
       lseek(f,0L,2)!=20L+(long)count*14L||lseek(f,20L,0)!=20L)goto finish;
    for(i=0;i<count;i++){
        if(!readExact(f,b,14))goto finish;time=longAt(b);
        if(time>pitDuration||(!i&&time)||(i&&time<=previous)||(b[12]&0xf0)||b[13])goto finish;
        for(j=0;j<4;j++)if(b[8+j]>127||(!b[4+j]&&b[8+j])||(b[4+j]&&!b[8+j])||
           (b[4+j]&&((unsigned)b[4+j]<(j==3?35U:45U)||(unsigned)b[4+j]>(j==3?81U:96U))))goto finish;
        if(i==count-1){if(time!=pitDuration)goto finish;for(j=4;j<14;j++)if(b[j])goto finish;}
        previous=time;
    }
    ok=1;
finish:_dos_close(f);return ok;
}
static int pitCheckVideo(void)
{
    int f,ok=0;U8 h[24];U32 n;
    if(access("MOVIE.WZV",0)!=0)return !(mode&2);
    if(_dos_open("MOVIE.WZV",O_RDONLY,&f))return 0;
    if(!readExact(f,h,24)||memcmp(h,gainFamily?"WZV4":"WZV3",4)||wordAt(h+4)!=256||wordAt(h+6)!=160||
       wordAt(h+8)!=4||wordAt(h+10)!=24||longAt(h+16)!=pitDuration||longAt(h+20)!=20480UL)goto finish;
    n=longAt(h+12);if(n!=(pitDuration+249UL)/250UL||lseek(f,0L,2)!=24L+(long)n*20480L)goto finish;
    ok=1;
finish:_dos_close(f);return ok;
}
static int pitCheckPart(void)
{
    int f,ok=0;U8 h[16],b[8];U32 i,time,previous=0,count;unsigned note,flags;
    if(_dos_open("MOVIE.WZP",O_RDONLY,&f))return 0;
    if(!readExact(f,h,16)||memcmp(h,"WZP1",4)||wordAt(h+4)!=1||wordAt(h+6)||
       longAt(h+8)!=pitDuration||wordAt(h+14))goto finish;
    count=wordAt(h+12);if(count<2||count>10000UL||lseek(f,0L,2)!=16L+(long)count*8L||lseek(f,16L,0)!=16L)goto finish;
    for(i=0;i<count;i++){
        if(!readExact(f,b,8))goto finish;time=longAt(b);note=b[4];flags=b[5];
        if(time>pitDuration||(!i&&time)||(i&&time<=previous)||flags>1||wordAt(b+6)||
           (!note&&flags)||(note&&(note<45||note>96)))goto finish;
        if(i==count-1&&(time!=pitDuration||note||flags))goto finish;previous=time;
    }
    pitCount=count;ok=1;
finish:_dos_close(f);return ok;
}
static int pitBundle(void)
{
    int marker=access("PIT.REQ",0)==0,part=access("MOVIE.WZP",0)==0;
    pitRequired=gainFamily?(gainFlags&4)!=0:
        pitMagic("MOVIE.WZV","WZV3")||pitMagic("MOVIE.WZM","WZM2");
    if(!pitRequired)return (marker||part)?fail(80):1;
    if(!marker||!part||!pitMarker()||!pitDirectory()||!pitCheckMusic()||!pitCheckVideo()||!pitCheckPart())return fail(81);
    duration=pitDuration;
    if(!(mode&1))return fail(82);
    return 1;
}
static int pitWindow(U32 a,U32 b)
{
    unsigned i;U32 low,high;
    for(i=0;i<clipCount;i++){
        low=clips[i].start>150UL?clips[i].start-150UL:0UL;
        high=clips[i].end+150UL;if(high>duration)high=duration;
        if(a<high&&low<b)return 0;
    }return 1;
}
static int pitGuards(void)
{
    int f;U8 b[14];U32 i,t,previous=0;unsigned active=0,j;
    if((!pitRequired&&!gainFamily)||!clipCount)return 1;
    if(!pitRequired)goto music;
    if(_dos_open("MOVIE.WZP",O_RDONLY,&f))return fail(83);
    if(lseek(f,16L,0)!=16L){_dos_close(f);return fail(83);}
    for(i=0;i<pitCount;i++){
        if(!readExact(f,b,8)){_dos_close(f);return fail(83);}t=longAt(b);
        if(active&&!pitWindow(previous,t)){_dos_close(f);return fail(83);}active=b[4];previous=t;
    }_dos_close(f);
music:
    if(_dos_open("MOVIE.WZM",O_RDONLY,&f))return fail(83);
    if(lseek(f,20L,0)!=20L){_dos_close(f);return fail(83);}previous=0;active=0;
    for(i=0;i<eventCount;i++){
        if(!readExact(f,b,14)){_dos_close(f);return fail(83);}t=longAt(b);
        if(active&&!pitWindow(previous,t)){_dos_close(f);return fail(83);}
        active=0;for(j=4;j<8;j++)active|=b[j];previous=t;
    }_dos_close(f);return 1;
}
static int pitFetch(void)
{
    U8 b[8];
    if(pitRead==pitCount){pitNextValid=0;return 1;}
    if(!readExact(pitFile,b,8))return fail(85);
    pitWhen=longAt(b);pitNextNote=b[4];pitNextFlags=b[5];pitRead++;pitNextValid=1;return 1;
}
static int pitOpen(void)
{
    if(!pitRequired)return 1;
    if(_dos_open("MOVIE.WZP",O_RDONLY,&pitFile)||lseek(pitFile,16L,0)!=16L)return fail(85);
    return pitFetch();
}
static int pitPrime(void)
{
    if(!pitRequired)return 1;
    while(pitNextValid&&pitWhen<=playStart){
        if(pitNextNote&&(pitNextFlags||pitNextNote!=pitNote))pitAttack=pitWhen;
        pitNote=pitNextNote;if(!pitFetch())return 0;
    }pitNeedsSync=1;return 1;
}
static int pitService(U32 now)
{
    unsigned note=pitNote,attack=0,n=0;U32 when=pitAttack;
    if(!pitRequired||pitPwm||openingFrame)return 1;
    while(pitNextValid&&pitWhen<=now){
        attack=(pitNextFlags||pitNextNote!=note)&&pitNextNote;
        if(attack)when=pitWhen;
        note=pitNextNote;n++;
        if(!pitFetch())return 0;
    }
    if(n||pitNeedsSync){attack=note&&(pitNeedsSync||when!=pitAttack||note!=pitNote);pitApplied++;if(n)pitSkipped+=n-1;pitAttack=when;
        if(DosSoundPitNote(note,attack?1:0)<0)return fail(86);pitNote=note;pitNeedsSync=0;}
    return 1;
}
