	.section	__TEXT,__text,regular,pure_instructions
	.macosx_version_min 10, 15
	.section	__TEXT,__literal4,4byte_literals
	.p2align	2               ## -- Begin function main
LCPI0_0:
	.long	1077936128              ## float 3
	.section	__TEXT,__text,regular,pure_instructions
	.globl	_main
	.p2align	4, 0x90
_main:                                  ## @main
	.cfi_startproc
## %bb.0:                               ## %entry
	pushq	%rax
	.cfi_def_cfa_offset 16
	leaq	L_format(%rip), %rdi
	movss	LCPI0_0(%rip), %xmm0    ## xmm0 = mem[0],zero,zero,zero
	movb	$1, %al
	callq	_printf
	popq	%rax
	retq
	.cfi_endproc
                                        ## -- End function
	.section	__TEXT,__cstring,cstring_literals
L_format:                               ## @format
	.asciz	"%f\n"

.subsections_via_symbols
