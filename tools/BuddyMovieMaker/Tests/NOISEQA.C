/* Test-only harness: actual production functions and PSG port output. */
#define main PlayerMain
#include "DOSPLAY.C"
#undef main
static FILE *qa;
static int check(int ok,char *label)
{
    if(!ok){fprintf(qa,"FAIL %s\n",label);return 0;}
    return 1;
}
int main(void)
{
    STATE s;unsigned n,preset,control,first,slot,j;
    unsigned heldPeriod;U32 heldAttack;
    qa=fopen("NOISEQA.LOG","w");if(!qa)return 1;
    haveHardware=1;expressive=1;mode=1;mute();
    memset(&s,0,sizeof(s));s.note[2]=48;s.velocity[2]=100;
    s.retrigger=4;synthState(&s,0);synthService(0);
    heldPeriod=periodOn[2];heldAttack=voiceState[2].began;
    for(n=35;n<=81;n++){
        control=0xe6;preset=9;first=0;slot=3;
        if(n==35||n==36){control=0xe2;preset=8;first=1;slot=0;}
        else if(n==38||n==40){control=0xe5;slot=2;}
        else if(n==42||n==44||n==46){
            control=0xe4;preset=10;first=2;slot=1;
        }
        for(j=0;j<4;j++)noiseControls[j]=0;
        s.note[3]=(U8)n;s.velocity[3]=73;s.retrigger=8;
        synthState(&s,0);synthService(0);
        if(!check(periodOn[3]==control&&(unsigned)voiceState[3].preset==preset&&
                  (unsigned)volume[3]==6U+first&&noiseControls[slot]==1UL,
                  "drum map / original attack attenuation"))goto bad;
        if(!check(periodOn[2]==heldPeriod&&
                  voiceState[2].began==heldAttack&&
                  voiceState[2].preset==0,"third tone unchanged"))goto bad;
        fprintf(qa,"drum_%u control=%u preset=%u atten=%u\n",
                n,control,preset,volume[3]);
        synthState(&s,55);synthService(55);
        if(!check(voiceState[3].began==1&&noiseControls[slot]==2UL,
                  "equal hit retriggers shift register"))goto bad;
        synthService(1000);
        if(!check(!synthActive[3]&&volume[3]==15,
                  "original drum self expiry"))goto bad;
        s.note[3]=s.velocity[3]=0;s.retrigger=0;
        synthState(&s,0);synthService(0);
    }
    if(!check(!noiseCoupledWrites,"no E3 / E7 coupling"))goto bad;
    /* Exercise the production stream merge with REPEAT.WZM/WZI. */
    memset(&current,0,sizeof(current));memset(synthActive,0,4);
    noiseResets=0;startTick=ClockTick();lastService=0;
    if(!check(openMusic(),"open repeat score"))goto bad;
    playEnd=duration;
    if(!check(openInstrument()&&primeMusic(),"open repeat sidecar"))
        goto bad;
    if(seedValid)soundState(&seed);
    if(!check(musicService(400)&&noiseResets==2&&
              voiceState[3].began==375UL/55UL,
              "late repeated hits use final attack snapshot"))goto bad;
    if(!check(musicService(750)&&noiseResets==2&&volume[3]==15,
              "late rest has no stale noise burst"))goto bad;
    if(!check(musicService(1000)&&noiseResets==3&&
              voiceState[3].preset==9&&voiceState[3].velocity==14,
              "noise volume endpoint at real attack time"))goto bad;
    cleanup();
    if(!check(volume[0]==15&&volume[1]==15&&volume[2]==15&&
              volume[3]==15&&!(SpeakerPort()&3),"cleanup mute"))goto bad;
    fprintf(qa,"PASS 47 maps / retrigger / expiry / tone isolation / late streams / cleanup\n");
    fclose(qa);return 0;
bad:
    cleanup();fclose(qa);return 1;
}
