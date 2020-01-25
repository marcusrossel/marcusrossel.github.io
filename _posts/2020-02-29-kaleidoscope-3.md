---
title: "Implementing LLVM's Kaleidoscope in Swift - Part 3"
---

Last post we implemented a parser that assembles the output of the lexer into a more meaningful abstract syntax tree, i.e. into expressions, function definitions and external declarations. In this post we're going to generate LLVM-IR from those AST-nodes.

---

Considering that this series of posts is called *"Implementing **LLVM**'s Kaleidoscope in Swift"* you might have noticed a distinct lack of *LLVM*-ness so far. That's because so far we've been busy turning *Kaleidoscope*-code into some representation the *we* understand - i.e. our AST. The job of *LLVM* is to turn a code-representation that *it* understands into an executable program. In consequence, we have to convert our AST-representation into *LLVM*'s *"intermediate representation" (IR)*. For that purpose we'll create an *"IR-Generator"*.

# LLVM IR




# Installing LLVM



Warning: If you ever get an error along the lines of <stdio.h not found> (e.g. with bundler), comment out the LLVM path decl, restart terminal, try again.

Until then, thanks for reading!

<br/>

---

<br/>

A full code listing for this post can be found [here](https://github.com/marcusrossel/marcusrossel.github.io/tree/master/assets/kaleidoscope/code/part-3).
