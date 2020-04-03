---
title: "Implementing LLVM's Kaleidoscope in Swift - Part 3"
---

Last post we implemented a parser that assembles the output of the lexer into a more meaningful abstract syntax tree, i.e. into expressions, function definitions and external declarations. In this post we're going to generate LLVM-IR from those AST-nodes.

> *Important note:*  
Although I have been able to work through implementing an IR-generator for *Kaleidoscope*, I am by no means a source of knowledge on this topic. Hence this post will rely *heavily* on external sources, as manifest in the quote-fest below.

---

*Considering that this series of posts is called *"Implementing **LLVM**'s Kaleidoscope in Swift"* you might have noticed a distinct lack of *LLVM*-ness so far. That's because so far we've been busy turning *Kaleidoscope*-code into some representation the *we* understand - i.e. our AST. The job of *LLVM* is to turn a code-representation that *it* understands into an executable program. In consequence, we have to convert our AST-representation into *LLVM*'s *"intermediate representation" (IR)*. For that purpose we'll create an *"IR-Generator"*.

# LLVM IR

*LLVM*'s intermediate representation in itself is a [vast topic](https://llvm.org/docs/LangRef.html), but for the purpose of *Kaleidoscope* we only need to understand a couple of its concepts. I have selected relevant sections from the documentation for explanation:

> The LLVM code representation is designed to be used in three different forms: as an in-memory compiler IR, as an on-disk bitcode representation (suitable for fast loading by a Just-In-Time compiler), and as a human readable **assembly language representation**. [...] It aims to be a “universal IR” of sorts, by being at a low enough level that high-level ideas may be cleanly mapped to it [...]. [↗](https://llvm.org/docs/LangRef.html#introduction)

> LLVM programs are composed of **modules**, each of which is a translation unit of the input programs. Each module consists of functions, global variables, and symbol table entries. [↗](https://llvm.org/docs/LangRef.html#module-structure)

> LLVM **function definitions** consist of the “define” keyword, [...] a return type, [...] a function name, a (possibly empty) argument list (each with optional parameter attributes), [...] an opening curly brace, a  list of basic blocks, and a closing curly brace.  
LLVM **function declarations** consist of the “declare” keyword, [...] a return type, [...] a function name, a possibly empty list of arguments [...].  
A function definition contains a list of **basic blocks**, forming the CFG (Control Flow Graph) for the function. Each basic block [...] contains a list of instructions, and ends with a terminator instruction (such as a branch or function return). [...]  
The first basic block in a function is special in two ways: it is immediately executed on entrance to the function, and it is not allowed to have predecessor basic blocks (i.e. there can not be any branches to the entry block of a function). [↗](https://llvm.org/docs/LangRef.html#functions)

> There is a difference between what the parser accepts and what is considered ‘well formed’. [...] The LLVM infrastructure provides a **verification pass** that may be used to verify that an LLVM module is well formed. [...] The violations pointed out by the verifier pass indicate bugs in transformation passes or input to the parser. [↗](https://llvm.org/docs/LangRef.html#well-formedness)

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

This is indeed the kind of code we're trying to generate, but luckily we don't even have to be able to read the code above in order to achieve this. We'll let the LLVM-library generate all of this code for us using function calls from plain old Swift.

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

> *Note*: When installing other programs/utilities, if you ever get an error along the lines of `stdio.h not found` (e.g. when using `bundler`), temporarily remove LLVM from your `PATH` and try again.

# Adding LLVM as a Dependency

Now that we have *LLVM* installed on our machines, we need to add it to our existing Swift package. More specifically, we need to tie the *C-bindings* of *LLVM* into our project. Natively *LLVM* is written in C++, but since Swift can't call into C++ code (yet) we need to use the C-bindings, which Swift *can* interact with.  
Importing a system library into a Swift package is a little bit involved. You can read a detailed of the process in the [corresponding SPM documentation](https://github.com/apple/swift-package-manager/blob/master/Documentation/Usage.md#requiring-system-libraries), but if you don't care about such details you can just copy the following steps.

First we need to adjust our `Package.swift` as follows:

```swift
// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "Kaleidoscope",

    products: [
        .executable(
            name: "Kaleidoscope",
            targets: ["Kaleidoscope"]
        ),
    ],

    dependencies: [ ],

    targets: [
        .systemLibrary(
            name: "CLLVM",
            providers: [.brew(["llvm"])]
        ),
        .target(
            name: "KaleidoscopeLib",
            dependencies: ["CLLVM"]
        ),
        .target(
            name: "Kaleidoscope",
            dependencies: ["KaleidoscopeLib"]
        ),
        .testTarget(
            name: "KaleidoscopeLibTests",
            dependencies: ["KaleidoscopeLib"]
        ),
    ]
)
```

We declare a new target of type `.systemLibrary` and tell it how the library can be accessed - in my case through a Homebew install.

> If you didn't use Homebrew for installation you can e.g. also provide a *pkg-config* name via the `pkgConfig` parameter. The SwiftLLVM repository contains a [script](https://github.com/llvm-swift/LLVMSwift/blob/master/utils/make-pkgconfig.swift) that can be used to add LLVM to your pkg-config.  

Now despite our specification of this new target, declaring `import CLLVM` will still fail. This is because although we have declared the `CLLVM` *target* we need to define its corresponding *package* - so it needs a corresponding folder to live in:

```terminal
marcus@Sources: mkdir CLLVM
marcus@Sources: cd CLLVM
```

To this directory we add two files, a *module map* and an *umbrella header*:

```terminal
marcus@CLLVM: touch module.modulemap
marcus@CLLVM: touch umbrella.h
```

For the purpose of this series, you don't need to understand what these files are for. If you are interested though, there's a [great talk](https://www.youtube.com/watch?v=586c_QMXir4) by [Doug Gregor](https://twitter.com/dgregor79) about the benefits of modules over headers.  
In short, these files are used for briding from C's concept of *headers* to Swift's concept of *modules*. So in these files we need to tell Swift how and what to import from the C library:

```c
// module.modulemap

module CLLVM [system] {
  umbrella header "umbrella.h"
  module * { export * }
}
```

```c
// umbrella.h

#define _GNU_SOURCE
#define __STDC_CONSTANT_MACROS
#define __STDC_FORMAT_MACROS
#define __STDC_LIMIT_MACROS

#include <llvm-c/Analysis.h>
#include <llvm-c/BitReader.h>
#include <llvm-c/BitWriter.h>
#include <llvm-c/Core.h>
#include <llvm-c/Comdat.h>
#include <llvm-c/DebugInfo.h>
#include <llvm-c/Disassembler.h>
#include <llvm-c/ErrorHandling.h>
#include <llvm-c/ExecutionEngine.h>
#include <llvm-c/Initialization.h>
#include <llvm-c/IRReader.h>
#include <llvm-c/Linker.h>
#include <llvm-c/LinkTimeOptimizer.h>
#include <llvm-c/lto.h>
#include <llvm-c/Object.h>
#include <llvm-c/OptRemarks.h>
#include <llvm-c/OrcBindings.h>
#include <llvm-c/Support.h>
#include <llvm-c/Target.h>
#include <llvm-c/TargetMachine.h>
#include <llvm-c/Transforms/IPO.h>
#include <llvm-c/Transforms/PassManagerBuilder.h>
#include <llvm-c/Transforms/Scalar.h>
#include <llvm-c/Transforms/Utils.h>
#include <llvm-c/Transforms/Vectorize.h>
#include <llvm-c/Types.h>
```

If you've completed all of the steps above, you should be able to open up `IRGenerator.swift`, type `import CLLVM` and compile successfully.  

> If you're using Xcode, try typing `LLVM` into the file. You should see a long list of suggested types and functions that all look very "unswifty".

# Writing the IR-Generator

When we wrote our parser, we created a transformation from tokens to AST nodes. The AST then represents the *entire* parsed program. So if we want to translate a *Kaleidoscope* program to LLVM-IR, we only need to map our AST to LLVM-IR. And our AST is really simply:

```swift
// Parser.swift

public struct Program {
    var externals: [Prototype] = []
    var functions: [Function] = []
    var expressions: [Expression] = []
}
```

All we have are external definitions, functions and expressions.

## Structure

As mentioned above, LLVM programs are composed of modules.

> Modules are the top level container of all other LLVM Intermediate Representation (IR) objects. [↗](https://llvm.org/doxygen/classllvm_1_1Module.html#details)

That is, if we want to create a representation of something like an if-expression or a binary operation in LLVM-IR, we need to place it in such a module container. The type of such a container is `LLVMModuleRef`. Although *LLVM* allows for multiple modules per program, we will only need one.  

> [The instruction builder] is a helper object that makes it easy to generate LLVM instructions. Instances of [`LLVMBuilderRef`] keep track of the current place to insert instructions and has methods to create new instructions. [↗](http://llvm.org/docs/tutorial/MyFirstLanguageFrontend/LangImpl03.html#code-generation-setup)

Also, we will of course need access to the AST from which to generate IR:

```swift
public final class IRGenerator {

    public private(set) var ast: Program
    public private(set) var module: LLVMModuleRef
    private let irBuilder: LLVMBuilderRef

    public init(ast: Program) {
        self.ast = ast
        module = LLVMModuleCreateWithName("kaleidoscope")
        builder = LLVMCreateBuilderInContext(LLVMGetGlobalContext())
    }
}
```

As you can see, calling into the LLVM C-bindings is rather unergonomic. E.g. `LLVMModuleCreateWithName(_:)` actually takes an `UnsafePointer<Int8>!` as parameter. Luckily Swift can often bridge from "normal" types to these more unwieldy types when suitable. In the initializer above we just pass a string literal where an `UnsafePointer<Int8>!` is expected, and Swift transparently bridges it. Apple's documentation on [`UnsafePointer`](https://developer.apple.com/documentation/swift/unsafepointer) is actually quite a nice for picking up the basics of pointers in Swift - which we will be dealing with a lot when using the LLVM-C bindings.  
So... to create the module we call `LLVMModuleCreateWithName(_:)` and pass it an arbitrary name (`"kaleidoscope"` seemed fitting).  

To obtain the aforementioned "representations" of program constructs, we will use LLVM's instruction builder `LLVMBuilderRef`.  
The builder is created by calling `LLVMCreateBuilderInContext(_:)` which expects an `LLVMContextRef!`. What is an LLVM context though? The documentation just says that...

> [i]t (opaquely) owns and manages the core "global" data of LLVM's core infrastructure, including the type and constant uniquing tables. [↗](http://llvm.org/doxygen/classllvm_1_1LLVMContext.html#details)

The fact that it's "opaque", kind of tells us that we don't need need to understand what exactly it does. And as [CAFxX](https://stackoverflow.com/users/414813/cafxx) puts it:

> Just think of it as a reference to the core LLVM "engine" that you should pass to the various methods that require a LLVMContext. [↗](https://stackoverflow.com/a/13186374/3208492)

I've seen quite a few source use `LLVMGetGlobalContext()` as a means of obtaining a context. According to the LLVM Developers mailing list though...

> `getGlobalContext()` has been removed a few years ago. You need to manage the lifetime of the context yourself. [↗](https://groups.google.com/forum/#!topic/llvm-dev/w4eSx2uM2Ig)

So instead we will use `LLVMContextCreate()` and retain the resulting context in our IR-generator:

```swift
public final class IRGenerator {

    // ...

    private let context: LLVMContextRef
    private let irBuilder: LLVMBuilderRef

    public init(ast: Program) {

        // ...

        context = LLVMContextCreate()
        builder = LLVMCreateBuilderInContext(context)
    }
}
```




Until then, thanks for reading!

<br/>

---

<br/>

A full code listing for this post can be found [here](https://github.com/marcusrossel/marcusrossel.github.io/tree/master/assets/kaleidoscope/code/part-3).
