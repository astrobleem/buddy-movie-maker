/* Test-only DOS child wrapper: redirects the real player's refusal to a log.
 * No hardware operations. Used only in a disposable Windows3 real-mode guest. */
#include <stdio.h>
#include <process.h>
int main(void)
{
    int result;
    if(!freopen("C:\\DOSCHILD.LOG","w",stdout))return 2;
    result=spawnl(P_WAIT,"C:\\MOVPLAY.EXE","MOVPLAY","/P",(char *)0);
    printf("CHILD_RETURN=%d\n",result);return result;
}
