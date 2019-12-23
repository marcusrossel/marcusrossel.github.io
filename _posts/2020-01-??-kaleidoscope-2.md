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


# Writing the Parser

Writing the parser is split into three parts. First we need to set up some functionality that we will later need to work with the stream of tokens ergonomically. Then we need to actually define our abstract syntax tree. And only then will we write the actual parsing methods.

## Structure

Our parser does not have a lot of state - all we need to retain is the stream of tokens that we're parsing as well as the token we're currently processing. For reasons of testability the token stream won't just be the lexer, but rather a simple abstraction over it:

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

We'll always want our parsing methods to work with the `currentToken`. When parsing a sequence of tokens, we might encounter a token which does not fit our current parsing step. If we only had `tokens`, there'd be no way for us to indicate that we do not actually want to consume that token. Using `currentToken` gives us a one-token buffer, which allows us to simply leave an unwanted token in the buffer. The size of this buffer is a characteristic property of top-down parsers as it defines how much lookahead is required. In our case that amount of lookahead is `1` making our parser an *LL(1)*-parser.  
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
        }
        try consumeToken()
    }
}
```

The first method simply tries to get the next token from the stream and saves the result into the buffer. In other words, we're consuming the *current* token.  
The second method might not be quite as obvious. When parsing tokens, you sometimes don't care about the *content* of the token, but rather about the *kind* of token being consumed. For example, say you're parsing an addition of two values - so something of the form `operand1 + operand2`. While you *do* care about the actual number values contained in the two operands' tokens, there is nothing to extract from the `+` sign, that is the `.operator(.plus)` token. All you need is for the token to actually be there. In this case we will call the second method, indicating that we expect the current token to be a specific kind of token. If this is not the case, we have encountered a parser error and will throw.

## Abstract Syntax Tree

Before we are able to write the parsing methods, we need to define which structures we will group the tokens into - i.e. how our AST will look like. This is where our grammar rules come into play.  
We've defined a program (a `<kaleidoscope>`) to one or more `<prototype>`, `<definition>` and `<expr>` in a specific order:

```swift
public struct Program {

    var externals: [Prototype] = []
    var functions: [Function] = []
    var expressions: [Expression] = []
}
```

As we will see later, the only prototypes that won't have definitions are external functions - hence we call the property `externals` here. Prototypes that do have corresponding definitions will be parsed into `Function`s - hence we call their property `functions`.

Since the only values in *Kaleidoscope* are `<number>`s, function prototypes are pretty simple. They only require the function name and the parameter names:

```swift
public struct Prototype {

    let name: String
    let parameters: [String]
}
```

The number of parameters of the prototype is easily deducable as `parameters.count`.

Since functions in *Kaleidoscope* only contain one expression, functions are equally simple:

```swift
public struct Function {

    let head: Prototype
    let body: Expression
}
```

What's special about the `body` expression of a function is that it's allowed to use the `head.parameters` as `<identifier>`s. Stand-alone expressions can't resolve the values of `<identifier>`s, but functions will be able to do so, as they get the `<identifier>`s' values at the call-site.  

Expressions will be the most complex part of our AST. As our grammar shows us, they serve many different purposes.  
The constant factor among all of the different types of expressions is that they can be evaluted to produce a value. Therefore we usually don't care which kind of expression we're handling in the rest of the AST. Using an enum for this will allow us to abstract over the specific type of expression when necessary:

```swift
public indirect enum Expression {
    case number(Double)
    case variable(String)
    case binary(lhs: Expression, operator: Operator, rhs: Expression)
    case call(String, arguments: [Expression])
    case `if`(condition: Expression, then: Expression, else: Expression)
}
```

Mind the `indirect` keyword here, as expressions can be nested within each other.

## Parsing Methods

Now that we know which kinds of AST-nodes we want to be able to produce and have a structure in place for working with a stream of tokens, we can implement the methods for converting those tokens into more useful AST-nodes.

### Helper Methods

We'll start by implementing a kind of helper method, which will make some of the other parsing steps simpler.

Both ...

```plaintext
<prototype> ::= <identifier> <left-paren> <params> <right-paren>
<params> ::= <identifier> | <identifier> <comma> <params>
```

... and ...

```plaintext
<call> ::= <identifier> <left-paren> <arguments> <right-paren>
<arguments> ::= <expr> | <expr> <comma> <arguments>
```

... require parsing something of the form `(item0, item1, ..., itemN)` - that is a tuple. The following method will parse such a tuple, and just return an array of the elements. Since the types of elements are not the same in the grammar rules above (`<expr>` and `<identifier>`), the method will need to be generic:

```swift
extension Parser {

    private func parseTuple<Element>(parsingFunction parseElement: () throws -> Element) throws -> [Element] {
        try consumeToken(.symbol(.leftParenthesis))
        var elements: [Element] = []

        while (try? consumeToken(.symbol(.rightParenthesis))) == nil {
            let element = try parseElement()
            elements.append(element)

            guard
                (try? consumeToken(.symbol(.comma))) != nil ||
                .symbol(.rightParenthesis) == currentToken
            else {
                throw Error.unexpectedToken(currentToken)
            }
        }

        return elements
    }
}
```

The method starts by parsing a `.symbol(.leftParenthesis)` and declaring the list of elements as empty. Then it tries to add elements to that list by parsing them with the given parsing function until it finds a closing `.symbol(.rightParenthesis)`. Along the way it makes sure that every element is separated by a `.symbol(.comma)`. If it does not find a `.symbol(.comma)` it expects the end of the tuple and checks for a `.symbol(.rightParenthesis)`. It does not consume this token yet though, as this will happen at the start of the next loop iteration anyway.

The second helper method we'll implement is one for parsing and extracting the `String` from an `.identifier`. There's nothing special about this - it's just common enough of a task that it's worth streamlining:

```swift
extension Parser {

    private func parseIdentifier() throws -> String {
        guard case let .identifier(identifier)? = currentToken else {
            throw Error.unexpectedToken(currentToken)
        }

        try! consumeToken() // known to be `.identifier`
        return identifier
    }
}
```

### Expressions

Now let's get into the weeds by implementing the parsing methods for expressions. These will be the most difficult of our parsing methods as they handle parsing that's relatively *"close to the lexer"*, i.e. at somewhat of a lower level of abstraction than the function- or prototype-parsing methods.  
Our AST lists five kinds of expressions that we need to be able to parse, our grammar on the other hand lists six kinds. That's due to the rule that an `<expr>` can be broken down as `<left-paren> <expr> <right-paren>`. In other words, add parentheses around an expression and you still get an expression with the same meaning.  
Let's implement a parsing method for this first:

```swift
extension Parser {

    private func parseParenthesizedExpression() throws -> Expression {
        try consumeToken(.symbol(.leftParenthesis))
        let innerExpression = try parseExpression()
        try consumeToken(.symbol(.rightParenthesis))

        return innerExpression
    }
}
```

As you can see it's straight forward. We consume a `.symbol(.leftParenthesis)`, then parse the inner expression with a yet undefined `parseExpression` method and then finish by consuming a `.symbol(.rightParenthesis)`. If any of these tokens does not appear as expected, an error will be thrown.  
Once we implement `parseExpression` you will also be able to see that this method is actually recursive. As long as the we nest parenthesized expressions in each other, `parseExpression` will call `parseParenthesizedExpression` and effectively strip away all of the nested parentheses.

So now we're left with the five types of expressions as defined by our AST. Let's start with a function call expression:

```plaintext
<call> ::= <identifier> <left-paren> <arguments> <right-paren>
<arguments> ::= <expr> | <expr> <comma> <arguments>
```

A function call is one of those expressions that will benefit from our previously defined `parseTuple` method. It's just an identifier followed by a tuple of arguments:

```swift
extension Parser {

    private func parseCallExpression() throws -> Expression {
        let identifier = try parseIdentifier()
        let arguments = try parseTuple(parsingFunction: parseExpression)

        return .call(identifier, arguments: arguments)
    }
}
```

The arguments of a function call in *Kaleidoscope* will of course be number values. We don't want those values to only be number-literals though, but also allow them to be results of other expressions. Hence the `parsingFunction` given to `parseTuple` is `parseExpression`. And again this has the effect that `parseCallExpression` is indirectly recursive (via `parseExpression`), allowing us to pass results of one function call as argument to another.  
You might notice that we're not actually checking whether the number of arguments given for a function call actually matches the expected number of parameters as defined for the function. This is simply because this is not the parser's job. The parser only *constructs* the AST - whether that AST actually makes sense is checked during a later step called *semantic analysis (sema)*.  

Parsing a number-expression is very much akin to parsing an identifier. The lexer has basically already done all of the work for us, and we only need to extract the value and package it as an AST-node:

```swift
extension Parser {

    private func parseNumberExpression() throws -> Expression {
        guard case let .number(number)? = currentToken else {
            throw Error.unexpectedToken(currentToken)
        }

        try! consumeToken() // known to be `.numberLiteral`
        return .number(number)
    }
}
```

Now let's tackle if-else expressions:

```plaintext
<ifelse> ::= <if-keyword> <expr> <then-keyword> <expr> <else-keyword> <expr>
```

You might be used to other programming languages treating if-else constructs as statements - Swift being one example.
Since *Kaleidoscope* doesn't really have the concept of statements though, we will define if-else constructs as expressions. Hence we will always need to require an else-branch, so that we have a value to return on every possible path. Furthermore each branch must contain *exactly one* expression, so that we don't end up with multiple values and don't know which value to return. The if-else expression's condition will also just be an expression. If this expression evaluates to `0` it is considered to be true, otherwise false.  
This very strict definition of if-else expressions allows for a very minimal parsing method:

```swift
extension Parser {

    private func parseIfExpression() throws -> Expression {
        try consumeToken(.keyword(.if))
        let condition = try parseExpression()
        try consumeToken(.keyword(.then))
        let then = try parseExpression()
        try consumeToken(.keyword(.else))
        let `else` = try parseExpression()

        return .if(condition: condition, then: then, else: `else`)
    }
}
```

No all that remains to be implemented is parsing of `.variable` and `.binary` expressions. As we will see later, variable expressions are basically just occurrences of identifiers that are not function calls - so we won't need a separate method for them, which leaves us with binary expressions:

```plaintext
<binary> ::= <expr> <operator> <expr>
```

Although the grammar rule for binary expressions may be simple, they're actually a bit weird when you try to parse them. The problem is that you don't know in advance whether the current expression is part of a binary expression or not. You can only parse an expression, *then* notice that there's an operator following this expression which then tell's us that it's part of a binary expression.  
This approach is reflected in how we will implement the parsing method for binary expressions. We will always require the expression on the left hand side to be given to us. We will then check whether there's an operator and a right hand side expression following. Only then can we construct a binary expression:

```swift
extension Parser {

    private func parseBinaryExpressionFromOperator(lhs: Expression) throws -> Expression {
        guard case let .operator(`operator`)? = currentToken else {
            throw Error.unexpectedToken(currentToken)
        }
        try! consumeToken() // known to be `.operator`

        let rhs = try parseExpression()

        return .binary(lhs: lhs, operator: `operator`, rhs: rhs)
    }
```

Now that we've handled all of the different kinds of expression we can finally get to that ominous `parseExpression` method. While all of the methods so far returned one specific kind of expression, this method will try to parse any kind of expression it finds. This of course relies heavily on the parsing methods we've just implemented.
