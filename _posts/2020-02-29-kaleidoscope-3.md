---
title: "Implementing LLVM's Kaleidoscope in Swift - Part 3"
---

Last post we implemented a parser that assembles the output of the lexer into a more meaningful abstract syntax tree, i.e. into expressions, function definitions and external declarations. In this post we're going to generate LLVM-IR from those AST-nodes.

---

Considering that this series of posts is called *"Implementing **LLVM**'s Kaleidoscope in Swift"* you might have noticed a distinct lack of *LLVM*-ness so far. That's because so far we've been busy turning *Kaleidoscope*-code into some representation the *we* understand - i.e. our AST. The job of *LLVM* is to turn a code-representation that *it* understands into an executable program. In consequence, we have to convert our AST-representation into *LLVM*'s *"intermediate representation" (IR)*. For that purpose we'll create an *"IR-Generator"*.

# LLVM IR

*LLVM*'s intermediate representation in itself is a [vast topic](https://llvm.org/docs/LangRef.html), but for the purpose of *Kaleidoscope* we only need to understand a couple of its concepts. As I am not sufficiently knowledgable on this topic to explain it myself, I have selected relevant sections from the documentation for explanation:

> The LLVM code representation is designed to be used in three different forms: as an in-memory compiler IR, as an on-disk bitcode representation (suitable for fast loading by a Just-In-Time compiler), and as a human readable **assembly language representation**. [...] It aims to be a “universal IR” of sorts, by being at a low enough level that high-level ideas may be cleanly mapped to it [...]. [↗](https://llvm.org/docs/LangRef.html#introduction)

> There is a difference between what the parser accepts and what is considered ‘well formed’. [...] The LLVM infrastructure provides a **verification pass** that may be used to verify that an LLVM module is well formed. [...] The violations pointed out by the verifier pass indicate bugs in transformation passes or input to the parser. [↗](https://llvm.org/docs/LangRef.html#well-formedness)

> LLVM programs are composed of **modules**, each of which is a translation unit of the input programs. Each module consists of functions, global variables, and symbol table entries. [↗](https://llvm.org/docs/LangRef.html#module-structure)

> LLVM **function definitions** consist of the “define” keyword, [...] a return type, [...] a function name, a (possibly empty) argument list (each with optional parameter attributes), [...] an opening curly brace, a  list of basic blocks, and a closing curly brace.  
LLVM **function declarations** consist of the “declare” keyword, [...] a return type, [...] a function name, a possibly empty list of arguments [...].  
A function definition contains a list of **basic blocks**, forming the CFG (Control Flow Graph) for the function. Each basic block [...] contains a list of instructions, and ends with a terminator instruction (such as a branch or function return). [...]  
The first basic block in a function is special in two ways: it is immediately executed on entrance to the function, and it is not allowed to have predecessor basic blocks (i.e. there can not be any branches to the entry block of a function). [↗](https://llvm.org/docs/LangRef.html#functions)

If you don't understand all of these concepts right now, don't worry. Translating our AST into LLVM-IR will make them much more understandable.  
Also, if you happen to reference any of the material above, you might see code like this:

```llvm
; Declare the string constant as a global constant.
@.str = private unnamed_addr constant [13 x i8] c"hello world\0A\00"

; External declaration of the puts function
declare i32 @puts(i8* nocapture) nounwind

; Definition of main function
define i32 @main() {   ; i32()*
  ; Convert [13 x i8]* to i8*...
  %cast210 = getelementptr [13 x i8], [13 x i8]* @.str, i64 0, i64 0

  ; Call puts function to write out the string to stdout.
  call i32 @puts(i8* %cast210)
  ret i32 0
}

; Named metadata
!0 = !{i32 42, null, !"string"}
!foo = !{!0}
```

This is indeed the kind of result we're trying to achieve, but luckily we don't even have to be able to read the code above. We'll let the LLVM-library generate all of this code for us using function calls from plain old Swift.

# Installing LLVM

Before we can dive into using said LLVM-library, we need to tie it into our package. We could just use [Harlan Haskins](https://twitter.com/harlanhaskins) and [Robert Widmann](https://twitter.com/CodaFi_)'s [LLVMSwift](https://github.com/llvm-swift/LLVMSwift) wrapper library - but hey, we're trying to become compiler wizards. So let's use the LLVM C-bindings directly.

> The LLVM project has multiple components. The core of the project is itself called “LLVM”. This contains all of the tools, libraries, and header files needed to process intermediate representations and converts it into object files. Tools include an assembler, disassembler, bitcode analyzer, and bitcode optimizer. [↗](https://llvm.org/docs/GettingStarted.html#overview)

For installation I simply used *LLVM*'s [Homebrew formula](https://formulae.brew.sh/formula/llvm):

```terminal
marcus@~: brew install llvm
```

If you don't (want to) use Homebrew though, you can also [build LLVM yourself](https://llvm.org/docs/GettingStarted.html#getting-the-source-code-and-building-llvm). Either way, make sure you add the location of your LLVM-install to your `PATH` (preferably in your `.bash_profile` or equivalent):

```
export PATH="/usr/local/opt/llvm/bin:$PATH"
```

*Note*: When installing other programs/utilities, if you ever get an error along the lines of `stdio.h not found` (e.g. when using `bundler`), temporarily remove LLVM from your `PATH` and try again.

# Adding LLVM to the Swift Package

Now that we have *LLVM* installed on our machines, we need to add it to our existing Swift package. More specifically, we need to tie the *C-bindings* of *LLVM* into our project. Natively *LLVM* is written in C++, but since Swift can't call into C++ code (yet) we need to use the C-bindings, which Swift *can* interact with.



Until then, thanks for reading!

<br/>

---

<br/>

A full code listing for this post can be found [here](https://github.com/marcusrossel/marcusrossel.github.io/tree/master/assets/kaleidoscope/code/part-3).
