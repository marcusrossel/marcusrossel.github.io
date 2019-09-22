---
title: "Implementing LLVM's Kaleidoscope in Swift - Part 0"
---

When  deciding to write this story I was expecting to start by saying something along the lines of *"I know there are already many tutorials for writing Kaleidoscope in Swift, but here's another one."* - Turns out, there's not. The only one I could find was [this one](https://harlanhaskins.com/2017/01/08/building-a-compiler-with-swift-in-llvm-part-1-introduction-and-the-lexer.html) by [Harlan Haskins](http://twitter.com/harlanhaskins). And while Harlan's tutorial is definitely worth checking out, it sometimes glosses over details which I had to figure out by using other resources. What I therefore hope to do with this series of posts, is to create a unified resource for learning how to implement [LLVM](https://llvm.org)'s tutorial language _Kaleidoscope_. The goal of this series is of course not just to create a working compiler for Kaleidoscope, but to learn how compilers can be built _in general_ using the LLVM infrastructure.  
Knowledge of the [Swift](https://swift.org) programming language is not necessarily required, but will definitely be helpful for this specific tutorial. If you prefer another language, you probably won't be hard pressed to find a Kaleidoscope tutorial for it as well.

*As a short disclaimer - I'm no expert on the topics I will be writing about. I'm going to try to explain my approach to learning about them, but I'll probably make mistakes. If you feel like something does not sound correct, do go and consult other resources! If you find mistakes, please report them on this [post's GitHub page](https://github.com/marcusrossel/marcusrossel.github.io/tree/master/_posts). Thanks!*

# LLVM

If you've stumbled upon this post without knowing what LLVM is, this section is for you - if you already know, skip to the next one. [→](#language-grammar)  

In the book *The Architecture of Open Source Applications* [Chris Lattner](), the original creator of LLVM, has written a [chapter introducing the LLVM project](http://www.aosabook.org/en/llvm.html) to newcomers. In it he explains a fundamental problem with compiler design, that LLVM intends to solve:  
Let's assume you want to write a new programming language. The way you would traditionally go about this is by writing

1. a frontend able to convert source code into some structured, internal representation
2. an optimizer which changes the code to run more efficiently
3. a backend which generates the machine code instructions for each target platform (x86, ARM, PowerPC, ...)

![Compiler Pipeline](http://www.aosabook.org/images/llvm/SimpleCompiler.png)

While this design works well for any given language, it is rather inefficient when considering the space of _all_ languages. The inefficiency really results from steps 2 and 3.  
Writing a good optimizer is no trivial task. First of all, you have to be able to figure out what you can change about a program's _code_, without changing its _behavior_. And once you know _what_ you can safely change in a program's code, you have to figure out _how_ to change it in order to increase efficiency. This can be a deeply mathematical process and is therefore not well suited for casual programmers.  
Writing compiler backends produces a different problem: there are many target architectures. If you want to create a programming language that will actually be relevant, your backend needs to be able to generate machine instructions for as many of them as possible. The following list of LLVM's supported target architectures should give you an idea of why this might be difficult though:

```
marcus@~: llc --version
LLVM (http://llvm.org/):
  LLVM version 8.0.1
  Optimized build.
  Default target: x86_64-apple-darwin18.7.0
  Host CPU: skylake

  Registered Targets:
    aarch64    - AArch64 (little endian)
    aarch64_be - AArch64 (big endian)
    amdgcn     - AMD GCN GPUs
    arm        - ARM
    arm64      - ARM64 (little endian)
    armeb      - ARM (big endian)
    bpf        - BPF (host endian)
    bpfeb      - BPF (big endian)
    bpfel      - BPF (little endian)
    hexagon    - Hexagon
    lanai      - Lanai
    mips       - MIPS (32-bit big endian)
    mips64     - MIPS (64-bit big endian)
    mips64el   - MIPS (64-bit little endian)
    mipsel     - MIPS (32-bit little endian)
    msp430     - MSP430 [experimental]
    nvptx      - NVIDIA PTX 32-bit
    nvptx64    - NVIDIA PTX 64-bit
    ppc32      - PowerPC 32
    ppc64      - PowerPC 64
    ppc64le    - PowerPC 64 LE
    r600       - AMD GPUs HD2XXX-HD6XXX
    sparc      - Sparc
    sparcel    - Sparc LE
    sparcv9    - Sparc V9
    systemz    - SystemZ
    thumb      - Thumb
    thumbeb    - Thumb (big endian)
    wasm32     - WebAssembly 32-bit
    wasm64     - WebAssembly 64-bit
    x86        - 32-bit X86: Pentium-Pro and above
    x86-64     - 64-bit X86: EM64T and AMD64
    xcore      - XCore
```

What LLVM therefore aims to do, is to remove steps 2 and 3 from your compiler design process. Neither do you need to be able to write an optimizer, nor a backend targeting 33 different architectures. LLVM just does that for you:

![LLVM Compiler Pipeline](http://www.aosabook.org/images/llvm/LLVMCompiler1.png)

You do need to help out LLVM a bit though, by passing your program to it using the _LLVM Intermediate Representation (LLVM IR)_. Because, just as step 1 required us to create some _"structured, internal representation"_ of our program, LLVM also needs some internal representation of a program in order to reason about it.

So all we have to do now in order to create a working compiler is to write a frontend and generate LLVM IR. And in the process we get the power of a top-of-the-line optimizer as well as a host of target architectures.  
Not without reason do [notable companies](https://llvm.org/Users.html)  rely and work on LLVM.

# <a name="language-grammar"></a>Language Grammar

This section begins with some rather theoretical aspects of programming languages. It is in no way required for the rest of the tutorial, so if you'd rather skip it, go right ahead. [→](#kaleidoscope-grammar)

## Formal Languages

A programming language is what is known as a _"formal language"_ in theoretical computer science. Wikipedia defines a [formal language](https://en.wikipedia.org/wiki/Formal_language) as:

> ... consist[ing] of words whose letters are taken from an alphabet and are well-formed according to a specific set of rules.

While this might sound a bit vague, it actually tells us a lot about the structure of formal languages. Let's unpack it:

### Alphabet

The alphabet of a formal language is the set of symbols (characters) that are allowed within the language. This should be very intuitive when comparing to spoken languages. For example, words in the English language will never contain the symbol `ö`, because it is not part of the English alphabet. German on the other hand has `ö` in its alphabet, which is why German words can use that symbol. It's that simple.

### Words

Words are again very well explained by analogy to spoken language. They are sequences of those symbols contained in the language's alphabet. Now this does not mean that _every_ sequence of symbols will create a valid word. For example, the sequences `folge` and `follow` both consist entirely of  symbols contained in the English alphabet. But only the sequence `follow` is a _word_ in the English language.  
This brings us to the main difference between natural spoken languages and formal languages.

### Formation Rules

The fact that `follow` is a word in the English language while `folge` is not, is rather arbitrary. This is why we need long dictionaries to describe which words belong to the English language - there's no system.  
Formal languages on the other hand _do_ have a system for describing which sequences of symbols are words in a language, and which aren't. They use _formation rules_ to describe how to generate each and every single word in a language, an not a single word more.  
Let's look at some examples using [BNF notation](https://en.wikipedia.org/wiki/Backus–Naur_form):

```
<digit> ::= "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9"
```

This is a formation rule which defines what a `digit` is (syntactically). It states that a `digit` can either be the symbol `0` or `1` or `2` ... or `9`. That's it. In a way we have defined the _language_ of digits, by simply listing all of its words. If someone would give us the sequence `123`, we could deduce that it is not a valid digit, as the formation rule above does not allow us to generate `123`.  

So what if we want to define the language of integers? We could build off of our previous formation rule for `digit` and add the following:

```
<integer> ::= <digit> | <digit> <integer>
```

This formation rule now tells us that an `integer` is either a `digit` (as we have defined previously), or it is a `digit` followed by another `integer`. As you can see, formation rules can be recursive. This allows us to generate words of different lengths.   
The formation rule for `digit` constrained our words to just be single symbols. But now we can for example derive that `123` is part of the language of integers, by generating it the following way:

```
<integer>
→ <digit> <integer>
→ "1" <integer>
→ "1" <digit> <integer>
→ "1" "2" <integer>
→ "1" "2" <digit>
→ "1" "2" "3"
```

By combining multiple formation rules we have started building a language _grammar_. Programming languages are also defined by a grammar.

## <a name="kaleidoscope-grammar"></a>Kaleidoscope

LLVM's [Kaleidoscope tutorial](https://llvm.org/docs/tutorial/) does not explicitly state the language grammar, but luckily Harlan Haskins has compiled it in [his tutorial](https://harlanhaskins.com/2017/01/09/building-a-compiler-with-swift-in-llvm-part-2-ast-and-the-parser.html):

```
<prototype>  ::= <identifier> "(" <params> ")"
<params>     ::= <identifier> | <identifier> "," <params>
<definition> ::= "def" <prototype> <expr> ";"
<extern>     ::= "extern" <prototype> ";"
<operator>   ::= "+" | "-" | "*" | "/" | "%"
<expr>       ::= <binary> | <call> | <identifier> | <number> | <ifelse> | "(" <expr> ")"
<binary>     ::= <expr> <operator> <expr>
<call>       ::= <identifier> "(" <arguments> ")"
<ifelse>     ::= "if" <expr> "then" <expr> "else" <expr>
<arguments>  ::= <expr> | <expr> "," <arguments>
```

And just for completeness, I'm going to add the following rule:

```
<kaleidoscope> ::= <prototype> | <definition> | <expr> | <prototype> <kaleidoscope> | <definition> <kaleidoscope> | <expr> <kaleidoscope>
```

The symbol `kaleidoscope` now defines the entirety of the Kaleidoscope language. Every valid Kaleidoscope program can be generated by starting with the `kaleidoscope` symbol and performing substitutions according to the formation rules. (Some invalid programs can be generated as well, which we will deal with later.)

The rules below define the symbols `identifier` and `number`, as they are not actually defined above.

```
<identifier> ::= <identifier-head> | <identifier> <identifier-body>
<identifier-body> ::= <identifier-head> | <digit>
<identifier-head> ::= #Foundation.CharacterSet.letter# | "_"
<number> ::= <digits> | <digits> "." <digits>
<digits> ::= <digit> | <digit> <digits>
<digit> ::= "0" | "1" | ... | "9"
```

I'm assuming Harlan didn't include these rules explicitly, because we usually have a pretty intuitive understanding of what identifiers and numbers are.  
The reason I explicitly included these rules though, is because they roughly show how our compiler frontend will be divided.

# Setting up the Project

We will be using [Swift Package Manager](https://swift.org/package-manager/) for this project. If you are not familiar with SPM, I recommend checking it out. You can always just follow what I'm doing though, so an understanding of SPM is not required.

We will also be using the LLVM API via its C-bindings, so you will need to download and [install LLVM](https://formulae.brew.sh/formula/llvm). This will only become relevant once we start writing the IR Generator though, so I will defer explanation of how to set it up until then.

## Package Structure

To setup a Swift package, create a new directory for the project, and initialize a new package from within the directory:

```shell
marcus@~: mkdir Kaleidoscope
marcus@~: cd Kaleidoscope
marcus@Kaleidoscope: swift package init
Creating library package: Kaleidoscope
Creating Package.swift
Creating README.md
Creating .gitignore
Creating Sources/
Creating Sources/Kaleidoscope/Kaleidoscope.swift
Creating Tests/
Creating Tests/LinuxMain.swift
Creating Tests/KaleidoscopeTests/
Creating Tests/KaleidoscopeTests/KaleidoscopeTests.swift
Creating Tests/KaleidoscopeTests/XCTestManifests.swift
```

---

If you want to use Xcode as your IDE, you can call `swift package generate-xcodeproj` to generate a `.xcodeproj` file for this project. As Xcode does not necessarily update according to the changes we're about to make, I recommend doing this *after* we've completed the following steps.

---

We will split our package into two targets, `Kaleidoscope` which will become an executable (the compiler), and `KaleidoscopeLib` which will be the library containing almost all of the logic of the compiler. We need to do this, because testing an executable is currently not possible using SPM. So our `Package.swift` manifest file has to look like this:

```swift
// swift-tools-version:5.0

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
        .target(
            name: "KaleidoscopeLib",
            dependencies: []
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

We need to reflect the target structure, in the folder structure of our project. So in the package's `Sources` directory, we will need a `Kaleidoscope` and a `KaleidoscopeLib` folder:

```shell
marcus@Kaleidoscope: cd Sources/
marcus@Sources: mkdir KaleidoscopeLib
marcus@Sources: ls
Kaleidoscope	KaleidoscopeLib
```

## File Structure

As mentioned in the section about Kaleidoscope's grammar [above](#kaleidoscope-grammar), our compiler frontend will be divided into multiple components. Those are

- Lexer
- Parser
- IR Generator

Accordingly we can create a source file for each of these components in the package's `KaleidoscopeLib` directory:

```shell
marcus@Sources: cd KaleidoscopeLib/
marcus@KaleidoscopeLib: touch Lexer.swift Parser.swift IRGenerator.swift
```

The lexer will be responsible for turning raw Kaleidoscope source code into syntactical units called *tokens*. Tokens will be things like number literals, keywords, and identifiers.  
The parser will use those tokens to compose higher-level symbols such as expressions, prototype declarations and function definitions.  
Lastly the IR Generator will use symbols produced by the parser to generate LLVM IR that fulfills the semantics associated with those symbols.

Don't worry if you didn't understand any of that yet - we will go into more detail about each of these components in their respective posts.

Until then, thanks for reading!
