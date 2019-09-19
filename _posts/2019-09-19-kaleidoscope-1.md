---
title: "Implementing LLVM's Kaleidoscope in Swift - Part I"
---

When  deciding to write this story I was expecting to start it by saying something along the lines of "I know there are already many tutorials for writing Kaleidoscope in Swift, but here's another one." - Turns out, there's not. The only one I could find was this one by Harlan Haskins. And while Harlan's tutorial is very good to say the least, it is a bit dated. Also, it ends up requiring the use the LLVMSwift bindings. In many ways this makes the interaction with the LLVM APIs easier, but for learning purposes I wanted to stay closer to the native LLVM APIs - using their C bindings. So in many ways this story will be similar to Harlan's tutorial series, though I hope to maybe make it even more approachable.
