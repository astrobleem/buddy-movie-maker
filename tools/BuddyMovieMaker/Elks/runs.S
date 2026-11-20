/* First-party DOS CgaRuns adapted to ELKS ia16 regparmcall. GPL-3.0.
 * Input AX points to a fully validated WZR1 command stream, exactly 8000
 * cells. Hardware interrupts remain enabled. Poll after each 512 cells. */
#include "backend.h"
.code16
.text
.global render_cga_packet
.type render_cga_packet,@function
render_cga_packet:
 push %bp
 push %bx
 push %si
 push %di
 push %es
 mov %ax,%si
 mov $0xb800,%ax
 mov %ax,%es
 mov $BUDDY_CGA_START,%di
 mov $512,%bx
 cld
.Lcommand:
 cmp $BUDDY_CGA_END,%di
 jae .Ldone
 lodsw
 mov %ax,%dx
 and $0x7fff,%dx
 test $0x8000,%ax
 jz .Lliteral
 lodsb
 mov %al,%ah
 mov $0xde,%al
.Lfill:
 mov %dx,%cx
 cmp %bx,%cx
 jbe .Lfillcount
 mov %bx,%cx
.Lfillcount:
 sub %cx,%dx
 sub %cx,%bx
 rep stosw
 or %bx,%bx
 jnz .Lfillmore
 call .Lpoll
 jz .Labort
.Lfillmore:
 or %dx,%dx
 jnz .Lfill
 jmp .Lcommand
.Lliteral:
 lodsb
 mov %al,%es:1(%di)
 add $2,%di
 dec %bx
 jnz .Lliteralmore
 call .Lpoll
 jz .Labort
.Lliteralmore:
 dec %dx
 jnz .Lliteral
 jmp .Lcommand
.Ldone:
 mov $1,%ax
 jmp .Lexit
.Labort:
 xor %ax,%ax
.Lexit:
 pop %es
 pop %di
 pop %si
 pop %bx
 pop %bp
 ret
.Lpoll:
 push %ax
 push %bx
 push %cx
 push %dx
 push %si
 push %di
 push %es
 call frame_pump
 or %ax,%ax
 pop %es
 pop %di
 pop %si
 pop %dx
 pop %cx
 pop %bx
 pop %ax
 mov $512,%bx
 ret
.size render_cga_packet,.-render_cga_packet

/* AX commands, DX byte length. Check every command before VRAM ownership. */
.global validate_packet
.type validate_packet,@function
validate_packet:
 push %bx
 push %si
 push %di
 mov %ax,%si
 mov %dx,%cx
 mov $8000,%di
 cld
.Lchecknext:
 or %cx,%cx
 jz .Lcheckend
 cmp $2,%cx
 jb .Lcheckbad
 lodsw
 sub $2,%cx
 mov %ax,%dx
 and $0x7fff,%dx
 jz .Lcheckbad
 cmp %di,%dx
 ja .Lcheckbad
 sub %dx,%di
 test $0x8000,%ax
 jz .Lcheckliteral
 jcxz .Lcheckbad
 inc %si
 dec %cx
 jmp .Lchecknext
.Lcheckliteral:
 cmp %cx,%dx
 ja .Lcheckbad
 add %dx,%si
 sub %dx,%cx
 jmp .Lchecknext
.Lcheckend:
 or %di,%di
 jnz .Lcheckbad
 mov $1,%ax
 jmp .Lcheckexit
.Lcheckbad:
 xor %ax,%ax
.Lcheckexit:
 pop %di
 pop %si
 pop %bx
 ret
.size validate_packet,.-validate_packet
