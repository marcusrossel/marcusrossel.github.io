---
title: "LLVM's Kaleidoscope in Swift - Part 3: IR Generator"
---

Last post we implemented a parser that assembles the output of the lexer into a more meaningful abstract syntax tree, i.e. into expressions, function definitions and external declarations. In this post we're going to generate LLVM-IR from those AST-nodes.

> *Important note:*  
Although I have been able to work through implementing an IR-generator for *Kaleidoscope*, I am by no means an expert on this topic. Hence this post will rely *heavily* on external sources, as manifest in the quote-fest below.

<br/>

---

<br/>

Considering that this series of posts is called *"Implementing **LLVM**'s Kaleidoscope in Swift"* you might have noticed a distinct lack of LLVM-ness so far. That's because so far we've been busy turning *Kaleidoscope*-code into some representation that *we* understand - i.e. our AST. The job of LLVM is to turn a code-representation that *it* understands into an executable program. In consequence, we have to convert our AST-representation into LLVM's *"intermediate representation" (IR)*. For that purpose we'll create an *"IR-Generator"*.

# LLVM IR

LLVM's intermediate representation in itself is a [vast topic](https://llvm.org/docs/LangRef.html), but for the purpose of *Kaleidoscope* we only need to understand a couple of its concepts. I have selected relevant sections from the documentation for explanation:

> The LLVM code representation is designed to be used in three different forms: as an in-memory compiler IR, as an on-disk bitcode representation (suitable for fast loading by a Just-In-Time compiler), and as a human readable **assembly language representation**. [...] It aims to be a “universal IR” of sorts, by being at a low enough level that high-level ideas may be cleanly mapped to it [...]. [↗](https://llvm.org/docs/LangRef.html#introduction)

> LLVM programs are composed of **modules**, each of which is a translation unit of the input programs. Each module consists of functions, global variables, and symbol table entries. [↗](https://llvm.org/docs/LangRef.html#module-structure)

> LLVM **function definitions** consist of the “define” keyword, [...] a return type, [...] a function name, a (possibly empty) argument list (each with optional parameter attributes), [...] an opening curly brace, a  list of basic blocks, and a closing curly brace.  
LLVM **function declarations** consist of the “declare” keyword, [...] a return type, [...] a function name, a possibly empty list of arguments [...].  
A function definition contains a list of **basic blocks**, forming the CFG (Control Flow Graph) for the function. Each basic block [...] contains a list of instructions, and ends with a terminator instruction (such as a branch or function return). [...]  
The first basic block in a function is special in two ways: it is immediately executed on entrance to the function, and it is not allowed to have predecessor basic blocks (i.e. there can not be any branches to the entry block of a function). [↗](https://llvm.org/docs/LangRef.html#functions)

> There is a difference between what the parser accepts and what is considered ‘well formed’. [...] The LLVM infrastructure provides a **verification pass** that may be used to verify that an LLVM module is well formed. [...] The violations pointed out by the verifier pass indicate bugs in transformation passes or input to the parser. [↗](https://llvm.org/docs/LangRef.html#well-formedness)

If you don't understand all of these concepts right now, don't worry. Translating our AST into LLVM-IR will make them much more understandable.  
Also, if you happen to reference any of the material above, you might see code like this:

```
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

For installation I simply used LLVM's [Homebrew formula](https://formulae.brew.sh/formula/llvm):

```terminal
marcus@~: brew install llvm
```

If you don't (want to) use Homebrew though, you can also [build LLVM yourself](https://llvm.org/docs/GettingStarted.html#getting-the-source-code-and-building-llvm). Either way, make sure you add the location of your LLVM-install to your `PATH` (preferably in your `.bash_profile` or equivalent):

```
export PATH="/usr/local/opt/llvm/bin:$PATH"
```

> *Note*: When installing other programs/utilities, if you ever get an error along the lines of `stdio.h not found` (e.g. when using `bundler`), temporarily remove LLVM from your `PATH` and try again.

# Adding LLVM as a Dependency

Now that we have LLVM installed on our machines, we need to add it to our existing Swift package. More specifically, we need to tie the *C-bindings* of LLVM into our project. Natively LLVM is written in C++, but since Swift can't call into C++ code (yet) we need to use the C-bindings, which Swift *can* interact with.  
Importing a system library into a Swift package is a little bit involved. You can read a detailed of the process in the [corresponding SPM documentation](https://github.com/apple/swift-package-manager/blob/master/Documentation/Usage.md#requiring-system-libraries), but if you don't care about such details you can just copy the following steps.

First we need to adjust the `Package.swift` as follows:

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
            pkgConfig: "cllvm"
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

We declare a new target of type `.systemLibrary` and tell it how the library can be accessed - in this case through *pkg-config*. The *SwiftLLVM* repository contains a [script](https://github.com/llvm-swift/LLVMSwift/blob/master/utils/make-pkgconfig.swift) that can be used to add LLVM to your *pkg-config*. You simply run it from any directory as:

```
marcus@~: swift make-pkgconfig.swift
```

If you ever update LLVM to a new version, don't forget to run this script again!

> If you've used Homebrew for installation you can also provide the location of LLVM via the `providers` parameter. In my experience this doesn't work as consistently as using *pkg-config* though.

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
#include <llvm-c/Comdat.h>
#include <llvm-c/Core.h>
#include <llvm-c/DataTypes.h>
#include <llvm-c/DebugInfo.h>
#include <llvm-c/Disassembler.h>
#include <llvm-c/DisassemblerTypes.h>
#include <llvm-c/Error.h>
#include <llvm-c/ErrorHandling.h>
#include <llvm-c/ExecutionEngine.h>
#include <llvm-c/ExternC.h>
#include <llvm-c/IRReader.h>
#include <llvm-c/Initialization.h>
#include <llvm-c/LinkTimeOptimizer.h>
#include <llvm-c/Linker.h>
#include <llvm-c/Object.h>
#include <llvm-c/OrcBindings.h>
#include <llvm-c/Remarks.h>
#include <llvm-c/Support.h>
#include <llvm-c/Target.h>
#include <llvm-c/TargetMachine.h>
#include <llvm-c/Transforms/AggressiveInstCombine.h>
#include <llvm-c/Transforms/Coroutines.h>
#include <llvm-c/Transforms/IPO.h>
#include <llvm-c/Transforms/InstCombine.h>
#include <llvm-c/Transforms/PassManagerBuilder.h>
#include <llvm-c/Transforms/Scalar.h>
#include <llvm-c/Transforms/Utils.h>
#include <llvm-c/Transforms/Vectorize.h>
#include <llvm-c/Types.h>
#include <llvm-c/lto.h>
```

> Note:  
> If you're using a different version of LLVM than used in this post (LLVM 10),
this list might contain outdated headers. You can fix this manually by just checking which headers are present in your install of LLVM (in my case they live in `/usr/local/Cellar/llvm/10.0.0_3/include/llvm-c/`) and editing the includes above accordingly.

If you've completed all of the steps above, you should be able to open up `IRGenerator.swift`, type `import CLLVM` and compile successfully. If it doesn't work and you're using an IDE, try building directly from the command line:

```terminal
marcus@Kaleidoscope: swift build
```

This seems to be a much more reliable method of building this project than e.g. using Xcode.

> Aside:  
> As of writing this post, Xcode is giving me the error `'llvm-c/Analysis.h' file not found`, while `swift build` is working just fine. Deleting the Xcode project file and creating a new one via `swift package generate-xcodeproj` seems to fix the problem though.

# Writing the IR-Generator

When we wrote our parser, we created a transformation from tokens to AST nodes. The AST then represents the *entire* parsed program. So if we want to translate a *Kaleidoscope* program into LLVM-IR, we only need to map the AST to LLVM-IR. And our AST is really simply:

```swift
// Parser.swift

public struct Program {
    var externals: [Prototype] = []
    var functions: [Function] = []
    var expressions: [Expression] = []
}
```

All we have are external definitions, functions and expressions. So what we need to do is to define IR-generation methods for these different types of nodes, traverse the AST and collect the IR as output.

> *Note:*  
> This is an example of the [visitor pattern](https://en.wikipedia.org/wiki/Visitor_pattern), which is commonly used in compilers.

## Structure

As mentioned above, LLVM programs are composed of modules.

> Modules are the top level container of all other LLVM Intermediate Representation (IR) objects. [↗](https://llvm.org/doxygen/classllvm_1_1Module.html#details)

That is, if we want to create a representation of something like an if-else expression or a binary operation in LLVM-IR, we need to place it in such a module container. The type of such a container is `LLVMModuleRef`. Although LLVM allows for multiple modules per program, we will only need one.  

Also, we will of course need access to the AST from which to generate IR:

```swift
public final class IRGenerator {

    public private(set) var ast: Program
    public private(set) var module: LLVMModuleRef
    private let context: LLVMContextRef

    public init(ast: Program) {
        self.ast = ast
        context = LLVMContextCreate()
        module = LLVMModuleCreateWithNameInContext("kaleidoscope")
    }
}
```

As you can see, calling into the LLVM C-bindings is rather unergonomic. E.g. `LLVMModuleCreateWithNameInContext(_:)` actually takes an `UnsafePointer<Int8>!` and `LLVMContextRef!` as parameters. Luckily Swift can often bridge from "normal" types to these more unwieldy types when suitable. In the initializer above we just pass a string literal where an `UnsafePointer<Int8>!` is expected, and Swift transparently bridges it. Apple's documentation on [`UnsafePointer`](https://developer.apple.com/documentation/swift/unsafepointer) is actually quite a nice for picking up the basics of pointers in Swift - which we will be dealing with a lot when using the LLVM-C bindings.  
So... to create the module we call `LLVMModuleCreateWithNameInContext(_:)` and pass it an arbitrary name (`"kaleidoscope"` seemed fitting) as well as some `context` that we've created before.  

Contexts will pop up across the entire implementation of the IR generator. E.g. to obtain the aforementioned "representations" of program constructs, we will use LLVM's instruction builder `LLVMBuilderRef`.  

> [The instruction builder] is a helper object that makes it easy to generate LLVM instructions. Instances of [`LLVMBuilderRef`] keep track of the current place to insert instructions and has methods to create new instructions. [↗](http://llvm.org/docs/tutorial/MyFirstLanguageFrontend/LangImpl03.html#code-generation-setup)

The builder is created by calling `LLVMCreateBuilderInContext(_:)` which also expects an `LLVMContextRef!`. What is an LLVM context though?  
The documentation just says that...

> [i]t (opaquely) owns and manages the core "global" data of LLVM's core infrastructure, including the type and constant uniquing tables. [↗](http://llvm.org/doxygen/classllvm_1_1LLVMContext.html#details)

The fact that it's "opaque", kind of tells us that we don't need to understand what exactly it does. And as [CAFxX](https://stackoverflow.com/users/414813/cafxx) puts it:

> Just think of it as a reference to the core LLVM "engine" that you should pass to the various methods that require a LLVMContext. [↗](https://stackoverflow.com/a/13186374/3208492)

I've seen quite a few source use `LLVMGetGlobalContext()` as a means of obtaining a context. According to the LLVM Developers mailing list though...

> `getGlobalContext()` has been removed a few years ago. You need to manage the lifetime of the context yourself. [↗](https://groups.google.com/forum/#!topic/llvm-dev/w4eSx2uM2Ig)

So instead we've used `LLVMContextCreate()` above, and retained the resulting context in our IR-generator. Adding the instruction builder is then as simple as:

```swift
public final class IRGenerator {

    // ...

    private let builder: LLVMBuilderRef

    public init(ast: Program) {
        // ...

        builder = LLVMCreateBuilderInContext(context)
    }
}
```

## Generator Methods

Now that we have defined the tools required for generating IR, let's actually generate some IR.  

### Expressions

Similarly to the parser, we'll start at the *"lowest level"* of AST nodes - expressions - and work our way up to the arguably simpler, but more composed nodes - functions. Since there are a couple more concepts we need to know in order to generate IR, we'll first go through some fundamentals.

#### Fundamentals

Let's start by generating IR for the simplest type of expression, a `.number`:

```swift
extension IRGenerator {

    private func generateNumberExpression(_ number: Double) -> LLVMValueRef {
        return LLVMConstReal(doubleType, number)
    }
}
```

The simplicity of this example allows us to nicely examine the new concepts.  

First there's the return type `LLVMValueRef`. This type is the C-binding analogue of the C++ `llvm::Value` class. If you follow the link below, you can find a nice graph of `llvm::Value`'s subtypes:

> This is a very important LLVM class. It is the base class of all values computed by a program that may be used as operands to other values. `Value` is the super class of other important classes such as `Instruction` and `Function`. [↗](https://llvm.org/doxygen/classllvm_1_1Value.html)

In fact `LLVMValueRef` will be the return type to all of our generator methods, as it represents binary expression, if-else expressions, function calls, etc.  

Next there's the function that actually creates the return value: `LLVMConstReal`. This functions belongs to a group of LLVM's functions that create *scalar constant* values, i.e. non-composite or single-value types:

> Functions in this group model `LLVMValueRef` instances that correspond to constants referring to scalar types. [↗](https://llvm.org/doxygen/group__LLVMCCoreValueConstantScalar.html)

It contains functions like `LLVMConstInt`, `LLVMConstReal`, etc. For the purpose of *Kaleidoscope* we will only need `LLVMConstReal` though, because our language only supports floating point values.  
What if we *did* want to support multiple types though, specifically multiple different types of real or integer values? This is what the first parameter in these scalar constant functions is for: `LLVMTypeRef`. As the documentation for `llvm::Value` explains:

> All `Value`s have a `Type`. `Type` is not a subclass of `Value`. [↗](https://llvm.org/doxygen/classllvm_1_1Value.html)

So just like with `LLVMValueRef`, `LLVMTypeRef` is the base type for an an entire [class hierarchy](https://llvm.org/doxygen/classllvm_1_1Type.html) which in this case represents *types* instead of *values*.  
Creating instances of `LLVMTypeRef`s basically works like creating `LLVMValueRef`s, by using a special LLVM provided function. E.g. that undefined `doubleType` value used above should simply be the `LLVMTypeRef` returned by `LLVMDoubleTypeInContext`. And since we're going to be using that exact type in a couple of places, let's store a reference to it in our IR-generator:

```swift
public final class IRGenerator {

    // ...

    private let doubleType: LLVMTypeRef

    public init(ast: Program) {
        // ...

        doubleType = LLVMFDoubleTypeInContext(context)
    }
}
```

The documentation for `LLVMDoubleTypeInContext` states that it returns a 64-bit floating-point type. If we ever want to use a different floating-point type we can just call `LLVMHalfTypeInContext`, `LLVMFloatTypeInContext`, `LLVMFP128TypeInContext`, etc. instead.

So now that we have a grasp on the fundamentals of working with `LLVMValueRef`s, let's look at some more interesting examples.

#### Binary Expressions

```swift
extension IRGenerator {

    private func generateBinaryExpression(
        lhs: Expression, operator: Operator, rhs: Expression
    ) throws -> LLVMValueRef {

        let lhs = try generate(expression: lhs)
        let rhs = try generate(expression: rhs)

        switch `operator` {
        case .plus:   return LLVMBuildFAdd(builder, lhs, rhs, "sum")
        case .minus:  return LLVMBuildFSub(builder, lhs, rhs, "difference")
        case .times:  return LLVMBuildFMul(builder, lhs, rhs, "product")
        case .divide: return LLVMBuildFDiv(builder, lhs, rhs, "quotient")
        case .modulo: return LLVMBuildFRem(builder, lhs, rhs, "remainder")
        }
    }
}
```

First we generate the IR for the left- and right-hand side expressions (`lhs` and `rhs`). We haven't implemented `generate(expression:)` yet, but as mentioned above, all of our generator methods will return `LLVMValueRef`s. So the values in `lhs` and `rhs` are IR-representations of the corresponding expressions.  
Next we create the IR-representations of the instructions corresponding to the given `operator`.

> An instruction builder represents a point within a basic block and is the exclusive means of building instructions using the C interface. [↗](https://llvm.org/doxygen/group__LLVMCCoreInstructionBuilder.html#details)

In this case (of only creating single instructions like `+` or `%`) the
instruction builder's use isn't really apparent yet. We can basically create the instructions' IR like we did for the constant values above, by calling a special LLVM function that returns the corresponding `LLVMValueRef`. Only this time, we also have to pass along our `LLVMBuilderRef` instance as well some string as last parameter.  
Those strings are used as names for the resulting values in the IR. So e.g. if we had a program containing ...

```
a + b
c + d
e + f
```

... the IR would look like ...

```
%sum = fadd double %a, %b
%sum1 = fadd double %c, %d
%sum2 = fadd double %e, %f
```

So the name we have provided for sums (namely `sum`) is used as a hint for naming the result of the operation.

> Local value names for instructions are purely optional, but it makes it much easier to read the IR dumps. [↗](https://llvm.org/docs/tutorial/MyFirstLanguageFrontend/LangImpl03.html#id3)

#### If-Else Expressions

If-else expressions will be the most complicated part of our IR-generator. They are the only part of *Kaleidoscope* that introduces any control flow, which requires us to have an understanding of *basic blocks*.

> A basic block is simply a container of instructions that execute sequentially. Basic blocks are `Value`s because they are referenced by instructions such as branches and switch tables. The type of a `BasicBlock` is `Type::LabelTy` because the basic block represents a label to which a branch can jump.  
A well formed basic block is formed of a list of non-terminating instructions followed by a single terminator instruction. Terminator instructions may not occur in the middle of basic blocks, and must terminate the blocks. The `BasicBlock` class allows malformed basic blocks to occur because it may be useful in the intermediate stage of constructing or modifying a program. However, the verifier will ensure that basic blocks are "well formed". [↗](https://llvm.org/doxygen/classllvm_1_1BasicBlock.html#details)

So basic blocks are labled buckets in which we place sequential instructions. That's why we had to pass those string parameters when generating `+`, `%`, etc. instructions above. The instruction builder placed the instructions in basic blocks and needed labels for them.  
Generating if-else expressions will actually require us to work with the basic blocks themselves, so we start off by getting the instruction builder's current basic block:

```swift
extension IRGenerator {

    private func generateIfElseExpression(
        condition: Expression, then: Expression, else: Expression
    ) throws -> LLVMValueRef {

        let entryBlock = LLVMGetInsertBlock(builder)

        // ...
    }
}
```

As mentioned above *"[a]n instruction builder represents a point within a basic block"*, so `entryBlock` is the block in which it is currently positioned.

Next, we need to set up a structure of basic blocks in which we can place the different parts of an if-else expression:

* condition - *"if"* part
* success path - *"then"* part
* failure path - *"else"* part
* merging path (more on that later)

In my opinion the APIs for inserting and moving basic blocks around aren't quite as neat as they could be, so the following might look a bit strange. Also, the lack of argument labels in C exactly contribute to legibility.

```swift
extension IRGenerator {

    private func generateIfElseExpression /* ... */ {
        // ...

        let mergeBlock = LLVMInsertBasicBlockInContext(context, entryBlock, "merge")
        LLVMMoveBasicBlockAfter(mergeBlock, entryBlock)

        let elseBlock = LLVMInsertBasicBlockInContext(context, mergeBlock, "else")
        let thenBlock = LLVMInsertBasicBlockInContext(context, elseBlock, "then")
        let ifBlock =   LLVMInsertBasicBlockInContext(context, thenBlock, "if")
    }
}
```

So what's happening here?  
First of all we have a new function `LLVMInsertBasicBlockInContext`. This function creates a new basic block and places it *before* another given basic block. Again, the last parameter is a label for the block.  
So let's say we're in the middle of generating the IR for some program that contains an if-else expression. We don't care what comes before or after that if-else expression, so for our purposes the block structure of the program looks like this:

```plaintext
------------------------
|          ...         |
| unknown basic blocks |
|          ...         |
|----------------------|
|      entry block     | < position of the IR builder
|----------------------|
|          ...         |
| unknown basic blocks |
|          ...         |
------------------------
```

After our first call to `LLVMInsertBasicBlockInContext` it looks like this:

```plaintext
------------------------
|          ...         |
| unknown basic blocks |
|          ...         |
|----------------------|
|      merge block     |
|----------------------|
|      entry block     | < position of the IR builder
|----------------------|
|          ...         |
| unknown basic blocks |
|          ...         |
------------------------
```

Since we want to generate the if-else expression *after* the current position of the IR builder though, we need to move the `entryBlock` using `LLVMMoveBasicBlockAfter`. This function moves a given block after another given block, so in our case we achieve this:

```plaintext
------------------------
|          ...         |
| unknown basic blocks |
|          ...         |
|----------------------|
|      entry block     | < position of the IR builder
|----------------------|
|      merge block     |
|----------------------|
|          ...         |
| unknown basic blocks |
|          ...         |
------------------------
```

Next we insert the remaining basic blocks, so we end up with:

```plaintext
------------------------
|          ...         |
| unknown basic blocks |
|          ...         |
|----------------------|
|      entry block     | < position of the IR builder
|----------------------|
|         if block     |
|----------------------|
|       then block     |
|----------------------|
|       else block     |
|----------------------|
|      merge block     |
|----------------------|
|          ...         |
| unknown basic blocks |
|          ...         |
------------------------
```

Since `LLVMInsertBasicBlockInContext` inserts a block *before* another block, we basically had to do the whole process in reverse order.

So now that we have our blocks, let's start filling them with some instructions.   
First off we need to make sure that execution flows from the `entryBlock` into the `ifBlock`. Recall from the documentation on basic blocks that *"[t]erminator instructions may not occur in the middle of basic blocks, and must terminate the blocks."* Terminator instructions are instructions like *return*, *branch* or *switch*. So for our purposes, we will use a branch instruction to move from the `entryBlock` into the `ifBlock`:

```swift
extension IRGenerator {

    private func generateIfElseExpression /* ... */ {
        // ...

        LLVMBuildBr(builder, ifBlock)
    }
}
```

> *Note*:  
We could avoid the `ifBlock` entirely by placing its contents in the `entryBlock`. But for the purpose of clarity, I have decided to give it its own block.

Next we'll fill the `ifBlock` with a branch instruction whose destination depends on the value of the given `condition` expression:

```swift
extension IRGenerator {

    private func generateIfElseExpression /* ... */ {
        // ...

        LLVMPositionBuilderAtEnd(builder, ifBlock)

        let condition = LLVMBuildFCmp(
            /* builder:   */ builder,
            /* predicate: */ LLVMRealONE,
            /* lhs:       */ try generate(expression: condition),
            /* rhs:       */ LLVMConstReal(doubleType, 0) /* = false */,
            /* label:     */ "condition"
        )

        LLVMBuildCondBr(builder, condition, thenBlock, elseBlock)
    }
}
```

As you can see, we first need to move the insertion position of the instruction builder to the `ifBlock` using `LLVMPositionBuilderAtEnd`. Then we create a `condition` expression that will be used to determine the destination of the branch. Lastly we build the actual conditional branch instruction using `LLVMBuildCondBr` with the `thenBlock` and `elseBlock` as the destinations, depending on the value of `condition`.  
The condition itself is constructed using `LLVMBuildFCmp`, which as the name suggests compares two floating-point values. It's second parameter is a predicate that determines which kind of comparison should be performed - in this case [`LLVMRealONE`](https://llvm.org/doxygen/group__LLVMCCoreTypes.html#ga242440d0e4a6d84d80b91df15e161971). This [basically](https://stackoverflow.com/q/40327806/3208492) checks the values for inequality. We consider an expression to be *false* if it evaluates to *0*. Hence, to determine whether an expression is *true*, we need tom make sure it is *not 0*.  

No to the remaining then-, else- and merge-blocks:

```swift
extension IRGenerator {

    private func generateIfElseExpression /* ... */ {
        // ...

        LLVMPositionBuilderAtEnd(builder, thenBlock)
        LLVMBuildBr(builder, mergeBlock)

        LLVMPositionBuilderAtEnd(builder, elseBlock)
        LLVMBuildBr(builder, mergeBlock)

        LLVMPositionBuilderAtEnd(builder, mergeBlock)
        let phiNode = LLVMBuildPhi(builder, doubleType, "result")!
        var phiValues: [LLVMValueRef?] = [try generate(expression: then), try generate(expression: `else`)]
        var phiBlocks = [thenBlock, elseBlock]
        LLVMAddIncoming(phiNode, &phiValues, &phiBlocks, 2)

        return phiNode
    }
}
```

I'd guess that this isn't exactly what you expected. Why aren't we just returning the IR for our `then` and `else` expressions from the then- and else-blocks? Well honestly, I'm not really sure. I just know that in the context of LLVM, this scenario is covered by *phi nodes*. The most understandable explanation I've read on them so far is that...

> All LLVM instructions are represented in the Static Single Assignment (SSA) form. Essentially, this means that any variable can be assigned to only once. Such a representation facilitates better optimization, among other benefits.  
A consequence of single assignment are PHI (Φ) nodes. These are required when a variable can be assigned a different value based on the path of control flow. For example, the value of `b` at the end of execution of the snippet below:
```
a = 1;
if (v < 10)
    a = 2;
b = a;
```
cannot be determined statically. The value of ‘2’ cannot be assigned to the ‘original’ `a`, since a can be assigned to only once. There are two `a`s in there, and the last assignment has to choose between which version to pick. This is accomplished by adding a PHI node. [↗](http://www.llvmpy.org/llvmpy-doc/dev/doc/llvm_concepts.html#ssa-form-and-phi-nodes)

So in other words, a phi node allows us to represent a value whose content consists of two values, of which one is selected depending on control flow. More specifically, in LLVM a phi node selects its value depending on which basic block was last exited. This explains the empty then- and else-blocks that contain nothing but a branch to the `mergeBlock`. Their sole purpose is to be used for selection in the following phi node.  

The phi node itself is created by calling `LLVMBuildPhi`. Capturing the returned value in a variable reveals that all of the functions we've called so far for creating `LLVMValueRefs` actually returned `LLVMValueRefs!`. So this time we actually need to unwrap that value. Like most other builder functions `LLVMBuildPhi` expects a type parameter, that determines which kind of value the phi nodes returns, as well as a label.  
Lastly we need to tell the phi node which value to return in which case. `LLVMAddIncoming` allows us to specify the `phiValues` that should be returned depending on which of the `phiBlocks` was the last exited basic block. We also have to pass the number of options in the last parameter, because I guess phi nodes support more than just two options (e.g. if we wanted to create an if-elseif-else expression).  
The final thing for us to do is to actually return a value from this function, which is supposed to be whichever value is the result of the if-else expression, so exactly the value of the phi node.

#### Variable Expressions

Although the generation of the expressions above may have become a bit complex, it had one simplifying characteristic: all of it could be done using purely *local* information. I.e. generating IR for numbers, binary expressions and if-else expressions could be performed without any information about the program except for the respective AST-node.  
As you may have guessed, this is not the case for variable expressions. In fact, the whole point of variable expressions is to use information gathered from *other parts* of a program. So the first step to generating their IR is to create some sort of record that associates variables' *names* with the *values* they represent:

```swift
public final class IRGenerator {

    // ...

    private var symbolTable: [String: LLVMValueRef] = [:]

    // ...
}
```

We call this record a *symbol table*.  
If we used the C++ LLVM library, there'd be a predefined [`ValueSymbolTable`](https://llvm.org/doxygen/classllvm_1_1ValueSymbolTable.html#details) type we could use. But the C-bindings don't seem to have an analogue to this, so we'll just use a plain old Swift dictionary instead.  
Now the generator method for variable expressions won't actually put anything
*into* the symbol table - it will only *read* from it:

```swift
extension IRGenerator {

    private func generateVariableExpression(name: String) throws -> LLVMValueRef {
        guard let value = symbolTable[name] else { throw Error.unknownVariable(name: name) }
        return value
    }
}
```

And as you can see, it's very simple. If can get the value corresponding to a variable name, we return it - if we can't find it, we throw an error. The error type is just a new enum:

```swift
public final class IRGenerator {

    public enum Error: Swift.Error {
        case unknownVariable(name: String)
    }

    // ...
}
```

What this simple implementation of `generateVariableExpression(name:)` enforces is that you have to define variables *before* you use them.  
So why haven't we already enforced this rule during parsing - isn't that kind of the parsers job?  
If you think back to part 2 of this series, you might remember that when testing our parser we accepted some test cases which we knew to be incorrect for a *Kaleidoscope* program:

> We know that we don’t want to accept them, but they’re not of our parser’s concern.
In fact we haven’t even captured a specification for them in our grammar! That’s because these issue require what is called a *context sensitive* grammar to describe them properly. BNF-notation only allows us to specify *context free* languages, and hence our parser also recognizes a context free language. [↗](https://marcusrossel.github.io/2020-01-19/kaleidoscope-2)

This new rule we've defined, that variables must be defined before use, is a context sensitive rule (as the name nicely implies). I.e. we couldn't have encoded it in BNF-notation and therefore we couldn't have encoded it in our parser. Larger compilers introduce an own stage for enforcing these kinds of rules, called [*semantic analysis*](https://en.wikipedia.org/wiki/Semantic_analysis_(compilers)). But for our purposes it is enough to integrate them into our IR generation methods. And we'll run into some more in just a moment when implementing our last expression generator method.

#### Call Expressions

In order to build a call expression, we'll use `LLVMBuildCall` which requires a value representing a function as well as its arguments. So first of all we're going to get a reference to the function to be called:

```swift
extension IRGenerator {

    private func generateCallExpression(
        functionName: String, arguments: [Expression]
    ) throws -> LLVMValueRef {
        guard let function = LLVMGetNamedFunction(module, functionName) else {
            throw Error.unknownFunction(name: functionName)
        }

        // ...
    }
}
```

`LLVMGetNamedFunction` *"[o]btain[s] a `Function` value from a `Module` by its name." [↗](https://llvm.org/doxygen/group__LLVMCCoreModule.html#gac230af72a200c4fce34d0b53134569cd)*  
We'll see later that part of a modules functionality is to act as a container to which we can add function definitions - kind of like a symbol table. And similar to how we've previously only *read* from the `symbolTable`, we'll only *get* functions from the module for now and concern ourselves with *setting* them later.  
So... we first try to get a function for a given name. If it is not yet defined, the *Kaleidoscope* program breaks another one of our context sensitive rules: functions must be declared before use. In this case we throw a (newly added) error.  
Next we grab the function's number of parameters and make sure it matches the passed number of arguments - another context sensitive rule:

```swift
extension IRGenerator {

    private func generateCallExpression /* ... */ {
        // ...

        let parameterCount = LLVMCountParams(function)

        guard parameterCount == arguments.count else {
            throw Error.invalidNumberOfArguments(
                arguments.count,
                expected: Int(parameterCount),
                functionName: functionName
            )
        }
    }
}
```

If the argument and parameter counts match, we generate the IR for each of the arguments. Since arguments can be any kind of expression, we call `generate(expression:)` for this:

```swift
extension IRGenerator {

    private func generateCallExpression /* ... */ {

        // ...

        var arguments: [LLVMValueRef?] = try arguments.map(generate(expression:))
    }
}
```

Since `generateCallExpression(functionName:arguments:)` is marked `throws`, we can just pass along any errors that might occur during the arguments' IR generation. The reason we explicitly define `arguments` as `[LLVMValueRef?]` is that the following call to `LLVMBuildCall` expects an `UnsafeMutablePointer<LLVMValueRef?>!` for this parameter:

```swift
extension IRGenerator {

    private func generateCallExpression /* ... */ {
        // ...

        return LLVMBuildCall(builder, function, &arguments, parameterCount, functionName)
    }
}
```

#### Any Expression

Cool, so now we've got a generator method for each kind of expression! Now all that's left to do is to define a wrapping `parseExpression(_:)` method, that calls the right generator method depending on the type of expression it receives:

```swift
extension IRGenerator {

    private func generate(expression: Expression) throws -> LLVMValueRef {
        switch expression {
        case let .number(number):
            return generateNumberExpression(number)
        case let .binary(lhs: lhs, operator: `operator`, rhs: rhs):
            return try generateBinaryExpression(lhs: lhs, operator: `operator`, rhs: rhs)
        case let .if(condition: condition, then: then, else: `else`):
            return try generateIfElseExpression(condition: condition, then: then, else: `else`)
        case let .variable(name):
            return try generateVariableExpression(name: name)
        case let .call(functionName, arguments: arguments):
            return try generateCallExpression(functionName: functionName, arguments: arguments)
        }
    }
}
```

### Function Prototypes

As mentioned above, part of a modules functionality is to act as a container to which we can add function definitions. We also have the option of just adding a function declaration though, i.e. a prototype. And of course that's exactly what we want when we encounter a `Prototype` AST node. Aside from one technicality, generating IR for a prototype is relatively straight forward:

```swift
extension IRGenerator {

    @discardableResult
    private func generate(prototype: Prototype) -> LLVMValueRef {
        guard LLVMGetNamedFunction(module, prototype.name) == nil else {
            throw Error.invalidRedeclarationOfFunction(prototype.name)
        }

        var parameters = [LLVMTypeRef?](repeating: doubleType, count: prototype.parameters.count)

        let signature = LLVMFunctionType(
            doubleType,
            &parameters,
            UInt32(prototype.parameters.count),
            false
        )

        let function = LLVMAddFunction(module, prototype.name, signature)!

        // Adds a name to each parameter, so that the IR shows their names for them instead of just
        // `%0`, `%1`, etc.
        for (index, name) in prototype.parameters.enumerated() {
            let parameterValue = LLVMGetParam(function, UInt32(index))
            LLVMSetValueName2(parameterValue, name, name.count)
        }

        return function
    }
}
```

First of all we mark the method `@discardableResult` because we *will* need the resulting `LLVMValueRef` when generating the IR for function definitions, but we *won't* need it when generating IR for external function declarations.  
The leading guard-statement just enforces the (context sensitive) rule, that functions can't be declared multiple times.  
The `parameters` are a list of `LLVMTypeRef`s which will be needed to define the function's type signature. Since the only type in *Kaleidoscope* is our previously defined `doubleType`, the parameter type list of a function is just the `doubleType` repeated as many times as there are parameters.  
Now to the perhaps more interesting part of the method. Just as we used `LLVMDoubleTypeInContext` to define the `doubleType`, we use `LLVMFunctionType` to define a function type.

> The function is defined as a tuple of a return Type, a list of parameter types, and whether the function is variadic. [↗](https://llvm.org/doxygen/group__LLVMCCoreTypeFunction.html#ga8b0c32e7322e5c6c1bf7eb95b0961707)

So the way we're populating `signature` is that it defines a function that returns a number, takes `prototype.parameters.count` numbers as parameters, and is not variadic (that's the `false`).  
Using this (function type) signature, we can add a function *declaration* to our module using `LLVMAddFunction`. And in return we also receive a reference to that function.

> *Side note:*  
> The last argument to `LLVMFunctionType` is actually an `LLVMBool` which is a typealias for `Int32`. So I've added the following conformance:  
> ```swift
> extension LLVMBool: ExpressibleByBooleanLiteral {
>
>    public init(booleanLiteral value: BooleanLiteralType) {
>        self = value ? 1 : 0
>    }
> }
> ```

Now that technicality I mentioned above is the for-loop. All this loop does is set a name for each of the function parameters, so that the IR looks nice. Without this code, a function like ...

```
def my_func(x, y) x + y;
```

... would be generated as ...

```
define double @my_func(double %0, double %1) {
entry:
  %sum = fadd double %0, %1
  ret double %sum
}
```

But by calling `LLVMSetValueName2` for each parameter, we get ...

```
define double @my_func(double %x, double %y) {
entry:
  %sum = fadd double %x, %y
  ret double %sum
}
```

That's literally all there is to it.

### Functions

Our last remaining AST-node is the `Function` node. Its generator method will nicely bring together most of the tools we have used above to generate other nodes' IR:

```swift
extension IRGenerator {

    private func generate(function: Function) throws {
        let prototype = try generate(prototype: function.head)
        let entryBlock = LLVMAppendBasicBlockInContext(context, prototype, "entry")

        for (index, name) in function.head.parameters.enumerated() {
            symbolTable[name] = LLVMGetParam(prototype, UInt32(index))
        }

        LLVMPositionBuilderAtEnd(builder, entryBlock)
        LLVMBuildRet(builder, try generate(expression: function.body))

        // Clears the symbol table so it can be used for *other* functions' bodies.
        symbolTable.removeAll()
    }
}
```

First of all, the method has no return value, as all we want to do is add the function to our module. And really we can just delegate that task to our `generate(prototype:)` method. We can then focus on adding the function's *body* onto that generated declaration.  
So after adding the function prototype (`function.head`) to the module, we append a basic block to it. Since we know that the `prototype` has just been declared (otherwise `generate(prototype:)` would have thrown), we know that the appended block is its *entry* block.  
Next we get to work with the symbol table again. Remember, the symbol table was just a container that maps between variable names and their values. Since the only variables we have in *Kaleidoscope* are function parameters, all of our variables are necessarily local to each function. Therefore we need to clear the symbol table after generating any function, and hence we also expect it to be empty before populating it.

> *Note:*  
> Clearing the symbol table right *before* populating it and leaving it "messy" until the next function is generated can cause problems. It would allow standalone expressions to use variable names defined in the last generated function:
> ```  
> // Populates the symbol table with `x` and `y`.
> def my_func(x, y) x + y;
>
> // This does not throw an error, because `x` is still in the symbol table.
> x
> ```

Populating the symbol table requires a little bit more thought. What we're doing is... For each of the function's parameters (`function.head.parameters.enumerated()`), get the `LLVMValueRef` (by calling `LLVMGetParam`) that will be used for that parameter's *argument*. Then associate that value with the parameter's name in the symbol table. Those `LLVMValueRef`s will be populated for us when calling `LLVMBuildCall`, where we have to provide the actual arguments. So basically what we're doing here is associating each parameter name with a *handle* to the argument-to-be.  
The remainder of the generator method is more pleasant again. First we move the instruction builder to the newly created `entryBlock`. And then, since the only kinds of statements we have in *Kaleidoscope* are expressions, we build a single return statement, that returns whatever value the `function.body` evaluates to.

The way we've implemented `generate(function:)` leads to a notable restriction on *Kaleidoscope* programs - function overloading is not possible. I.e. if we have one function `my_func(x)` and another `my_func(a, b)`, the IR generator will throw an error. We will not fix this problem in this tutorial, but as [LLVM's tutorial](https://llvm.org/docs/tutorial/MyFirstLanguageFrontend/LangImpl03.html#id4) puts it:

> There are a number of ways to fix this bug, see what you can come up with!

## Program Generation

Ok, so we've implemented IR generation for each of our AST-nodes. Now all that's left to do is to place the generated IR in some encompassing structure.  
This is the point where have to define what it *means* to define an expression in a *Kaleidoscope* program - i.e. what should happen with the value. We'll take a simple approach and just print out the value of any expression to *stdout* in the order they appear in. So e.g. the program ...

```
def double(x) 2 * x;
def is_equal(x, y) if x - y then 0 else 1;

double(3.5 + 2.5)
if is_equal(double(1), 2) then 100 else 0
```

... should produce the output ...

```
12
100
```

We can implement this behaviour in two small steps:
1. We need to add some way of printing things to *stdout*. For this we'll manually add an external function declaration of `printf` to our module.
2. We'll manually define a `main` function in which we sequentially call `printf` with the results of (the IR of) all of our parsed `Expression`s.

### Adding `printf`

The most comfortable way of adding an external function declaration to our module would be through our `generate(prototype:)` method. Unfortunately this method only works for functions that expect and return floating-point values. C's `printf` on the other hand is declared as `int printf(const char * format, ...);`, so we'll need to handcraft its type signature:

```swift
extension IRGenerator {

    private func generatePrintf() -> LLVMValueRef {
        var parameters: [LLVMTypeRef?] = [LLVMPointerType(LLVMInt8TypeInContext(context), 0)]
        let signature = LLVMFunctionType(LLVMInt32TypeInContext(context), &parameters, 1, true)

        return LLVMAddFunction(module, "printf", signature)
    }
}
```

This method should be quite easily understood by now. The only odd part is the `LLVMPointerType` function - not only does it take the type it should point to as its first parameter, but it also expects some second parameter. Apparently this second parameter can be used to identify different address spaces. [LLVMSwift's implementation of `PointerType`](https://github.com/llvm-swift/LLVMSwift/blob/188bfbb56521fe28efe73bdc344185d135a64967/Sources/LLVM/PointerType.swift#L24) just sets this value to `0` by default, so I just copied that behaviour above.

### Adding `main`

The `generateMain` method will be similar to `generatePrintf`. We again need to handcraft a function and add it to the module. This time it should have the type `() -> ()` (in *Swift* syntax):

```swift
extension IRGenerator {

    private func generateMain() throws {
        var parameters: [LLVMTypeRef?] = []
        let signature = LLVMFunctionType(LLVMVoidTypeInContext(context), &parameters, 0, false)

        let main = LLVMAddFunction(module, "main", signature)

        // ...
    }
}
```

While `printf` was declared externally, `main` will now be defined by us manually. For every `Expression` in the AST we will build a call to `printf` that prints the value of the expression using the format string `"%f\n"`.

> *Side note:*  
> If you're not familiar with C's `printf`, don't worry. For our use case, you
> can pretend that it's a function whose first argument must be the constant
> `"%f\n"` and second argument must be a `double` value that will be
> printed.
> Note that `printf` has no format specifier for `float`s - If you pass it a `float` it will just print the value `0`!

Adding `main`'s body is analogue to the way we did it in `generate(function:)`:

```swift
extension IRGenerator {

    private func generateMain() throws {
        // ...

        let entryBlock = LLVMAppendBasicBlockInContext(context, main, "entry")
        LLVMPositionBuilderAtEnd(builder, entryBlock)

        let formatString = LLVMBuildGlobalStringPtr(builder, "%f\n", "format")
        let printf = generatePrintf()

        for expression in ast.expressions {
            var arguments: [LLVMValueRef?] = [formatString, try generate(expression: expression)]
            LLVMBuildCall(builder, printf, &arguments, 2, "print")
        }

        LLVMBuildRetVoid(builder)
    }
}
```

The part of this method that might be unfamiliar is the creation of the `formatString`. All `LLVMBuildGlobalStringPtr` does for us is to create an `LLVMValueRef` from an `UnsafePointer<Int8>!`, i.e. a string - the last parameter is again a label for the value.  
In the for-loop we build calls of the form `printf("%f\n", <expression-value>)`.

### Whole-Program Generation

Every method we've declared so far has been private. That's because all we want to expose to "the user" is a single method that generates the IR for the entire given AST:

```swift
extension IRGenerator {

    public func generateProgram() throws {
        try ast.externals.forEach { try generate(prototype: $0) }
        try ast.functions.forEach { try generate(function:  $0) }
        try generateMain()
    }
}
```

The way we've iplemented `generateProgram` has a couple of effects on the correctness of a *Kaleidoscope* program.  
Firstly, we generate all external function declarations *before* we generate the functions defined within the program. Hence the functions defined within the program are treated as the duplicate if there is a name collision.
Secondly, since `generateMain` defines a `printf` and a `main` function, these names are reserved and cannot be declared in a *Kaleidoscope* program (otherwise the IR-generation throws and error).

# Running Our First *Kaleidoscope* Program

If you're anything like me, you really want to try out the pipeline we've built now. So far we're only able to generate *LLVM-IR* though.  
Luckily there's [`lli`](https://llvm.org/docs/CommandGuide/lli.html) which we can use to execute LLVM-IR. If you've installed LLVM in some capacity, you should be able to access it directly from the command line:

```terminal
marcus@~: lli example.ll
```

> *Note:*  
> The extension `ll` seems to somewhat of a standard for LLVM-IR files. The given extension doesn't *actually* matter of course. And if you *really* care, there's some more [nuance](https://stackoverflow.com/q/19453440/3208492) to it.

## Ad Hoc IR Generation

To actually *get* the IR generated by the IR generator, we first of all need to be able to execute our compiler pipeline. So for the first time we get to use our `main.swift`. This implementation is only supposed to reassure us that our compiler pipeline actually runs, so it's just going to be temporary.

First and foremost we're going to import all of the parts we need for the compiler pipeline:

```swift
import KaleidoscopeLib
import CLLVM
```

Since this is only an ad-hoc solution, we're going define a sample program in-line:

```swift
// ...

let program = """
def double(x) 2 * x;
def is_equal(x, y) if x - y then 0 else 1;

double(3.5 + 2.5)
if is_equal(double(1), 2) then 100 else 0
"""
```

Since we'd like to catch any errors, we'll place all of the steps of the compilation process in a do-catch structure:

```swift
// ...

do {
    let lexer = Lexer(text: program)
    let parser = Parser(tokens: lexer)
    let ast = try parser.parseProgram()
    let irGenerator = IRGenerator(ast: ast)
    try irGenerator.generateProgram()
    LLVMDumpModule(irGenerator.module)
} catch {
    print(error)
}
```

So where does the IR actually end up now?
Well, after calling `irGenerator.generateProgram()` it's still stuck in the `LLVMModuleRef` inside of the `irGenerator`. To "get it out" we call `LLVMDumpModule`, which will print the IR to *stderr*:

```
; ModuleID = 'kaleidoscope'
source_filename = "kaleidoscope"

@format = private unnamed_addr constant [4 x i8] c"%f\0A\00", align 1

define double @double(double %x) {
entry:
  %product = fmul double 2.000000e+00, %x
  ret double %product
}

define double @is_equal(double %x, double %y) {
entry:
  br label %if

if:                                               ; preds = %entry
  %difference = fsub double %x, %y
  %condition = fcmp one double %difference, 0.000000e+00
  br i1 %condition, label %then, label %else

then:                                             ; preds = %if
  br label %merge

else:                                             ; preds = %if
  br label %merge

merge:                                            ; preds = %else, %then
  %result = phi double [ 0.000000e+00, %then ], [ 1.000000e+00, %else ]
  ret double %result
}

define void @main() {
entry:
  %double = call double @double(double 6.000000e+00)
  %print = call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([4 x i8], [4 x i8]* @format, i32 0, i32 0), double %double)
  br label %if

if:                                               ; preds = %entry
  %double1 = call double @double(double 1.000000e+00)
  %is_equal = call double @is_equal(double %double1, double 2.000000e+00)
  %condition = fcmp one double %is_equal, 0.000000e+00
  br i1 %condition, label %then, label %else

then:                                             ; preds = %if
  br label %merge

else:                                             ; preds = %if
  br label %merge

merge:                                            ; preds = %else, %then
  %result = phi double [ 1.000000e+02, %then ], [ 0.000000e+00, %else ]
  %print2 = call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([4 x i8], [4 x i8]* @format, i32 0, i32 0), double %result)
  ret void
}

declare i32 @printf(i8* %0, ...)
```

To run this program, just copy and paste the IR into some file and run `lli` on it as shown above.

## Next Steps

I find reading through the generated IR quite satisfying. Most of it corresponds directly to the structure we've implemented in our IR generator.

There is one big caveat to our IR though - it might be incorrect. And I don't just mean that it doesn't exactly resemble the semantics of the underlying (or overlying?) *Kaleidoscope* program. The generated IR might not even be valid IR. If you have amazing memory, you might recall from the start of this post that:

> The LLVM infrastructure provides a **verification pass** that may be used to verify that an LLVM module is well formed.

That is, we can use the function builder to build IR that is invalid. So at some point we have to run a verifier that makes sure that our IR is valid. Luckily LLVM provides a verifier that we can just use as is. But module verification and generation of executables will all be covered in the next part of this series.

Until then, thanks for reading!

<br/>

---

<br/>

A full code listing for this post can be found [here](https://github.com/marcusrossel/marcusrossel.github.io/tree/master/assets/kaleidoscope/code/part-3).
