---
title: "Implementing LLVM's Kaleidoscope in Swift - Part 2"
---

Last post we implemented a lexer to turn plain text into meaningful tokens. This post will deal with the parser.

---

The job of the parser is similar to that of a lexer. The lexer grouped plain text characters into more abstract bundles called *tokens*. We performed this grouping process in order to extract more explicit information about the plain text, which would otherwise be somewhat hidden within it. When parsing a stream of tokens, we have an analogous goal - we're trying to bundle together groups of tokens into what is called an *abstract syntax tree (AST)*. This process of grouping together tokens will again entail a more explicit representation of certain information that would otherwise be somewhat hidden in the stream of tokens.

Anyone who's programmed before (which I assume you have), has parsed code in their mind. To most programmers the line:

```plaintext
string message = "hello"
```

... will look like a definition of a variable called `message` with a value of `"hello"` of type `string`. I bet most people could even understand the following sequence of tokens:

```plaintext
<type declaration> <identifier> <left parenthesis> <right parenthesis> <left brace> <right brace>
```

It looks like a C-style function definition, doesn't it?  
This intuitive grouping of certain tokens into bigger structures doesn't come to us as naturally as the grouping of characters into tokens. But it still seems to have some underlying rules, which means that we can automate it by writing a parser. In fact, the rules that govern the parsing process usually heavily influence the look and feel of a language, so it's a very fun and interesting part of language's design.

In the case of *Kaleidoscope* these rules are already defined. Just as we had grammar rules for lexing, we have grammer rules for parsing:

```plaintext
<kaleidoscope> ::= <prototype> | <definition> | <expr> | <prototype> <kaleidoscope> | <definition> <kaleidoscope> | <expr> <kaleidoscope>
<prototype>    ::= <identifier> <left-paren> <params> <right-paren>
<params>       ::= <identifier> | <identifier> <comma> <params>
<definition>   ::= <definition-keyword> <prototype> <expr> <semicolon>
<extern>       ::= <external-keyword> <prototype> <semicolon>
<expr>         ::= <binary> | <call> | <identifier> | <number> | <ifelse> | <left-paren> <expr> <right-paren>
<binary>       ::= <expr> <operator> <expr>
<call>         ::= <identifier> <left-paren> <arguments> <right-paren>
<ifelse>       ::= <if-keyword> <expr> <then-keyword> <expr> <else-keyword> <expr>
<arguments>    ::= <expr> | <expr> <comma> <arguments>
```

As mentioned in the last part of this series:

> we will see later on in this tutorial, [that] we want our parser to only deal with *non-terminal symbols* - that is symbols constructed from other symbols (written between `<>` in BNF notation).

You should have some understanding now of why that is.

# Implementation Methods

There are a variety of methods for how to implement parsers. I might add some more information of the different types of parsers here in the future.  
For now it is enough to know that we will be implementing a top-down parser.


# Writing the Lexer

Writing the lexer is split into three parts. First we need to set up some functionality that we will later need to work with the stream of tokens ergonomically. Then we need to actually define our abstract syntax tree. And only then will we write the actual parsing methods.

## Structure

Our parser does not have a lot of state - all we need to hold on to is the stream of tokens that we're parsing as well as the token we're currently processing. For reasons of testability the token stream won't just be the lexer, but rather a simple abstraction over it:

```swift
public protocol TokenStream {

    associatedtype Token

    func nextToken() throws -> Token?
}
```

A `TokenStream` is very similar to `IteratorProtocol`, but as we want to maintain the difference between throwing and error and returning `nil`, we need to create a more customized protocol.

Using this protocol we can define our parser as follows:

```swift
public final class Parser<Tokens: TokenStream> where Tokens.Token == Token {

    private var tokens: Tokens
    private var currentToken: Token?

    public init(tokens: Tokens) {
        self.tokens = tokens
    }
}
```

We'll always want our parsing methods to work with the `currentToken`. When parsing a sequence of tokens, we might encounter a token which does not fit our current parsing step. If we only had `tokens`, there'd be no way for us to indicate that we do not actually want to consume that token. Using `currentToken` gives us a one-token buffer, which allows us to simply leave an unwanted token in the buffer. The size of this buffer is a characteristic property of top-down parsers as it defines how much lookahead is required. In our case that amount of lookahead is `1` making our parser an `LL(1)` parser.  
In order to make interactions with the buffer a bit nicer, we'll define some convenience methods:

```swift
public final class Parser<Tokens: TokenStream> where Tokens.Token == Token {

    // ...

    public enum Error: Swift.Error {
        case unexpectedToken(Token?)
    }

    private func consumeToken() throws {
        currentToken = try tokens.nextToken()
    }

    private func consumeToken(_ target: Token) throws {
        if currentToken != target {
            throw Error.unexpectedToken(currentToken)
        } else {
            try consumeToken()
        }
    }
```

The first method simply tries to get the next token from the stream and saves the result into the buffer. This means that we're consuming the *current* token.  
The second method might not be quite as obvious. When parsing tokens, you sometimes don't care about the content of the token, but rather about the token being one specific token. E.g. say you're parsing an addition of two values. While you do care about the actual number values contained in the two operands' tokens, there is nothing to extract from the `=` sign, that is the `.operator(.plus)` token. All you need is for the token to actually be there. In this case we will call the second method, indicating that we expect the current token to be a specific kind of token. If this is not the case, we have encountered a parser error and will throw.
