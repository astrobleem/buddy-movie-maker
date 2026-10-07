/* Test-only controlled external speaker gate, disposable DOSBox guest only. */
#include <conio.h>
int main(int argc,char **argv)
{
    unsigned bits=inp(0x61)&0xfc;
    if(argc>1&&argv[1][0]=='1')bits|=3;
    outp(0x61,bits);return 0;
}
