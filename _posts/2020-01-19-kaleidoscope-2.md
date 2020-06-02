---
title: "LLVM's Kaleidoscope in Swift - Part 2: Parser"
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
<kaleidoscope> ::= <extern> | <definition> | <expr> | <extern> <kaleidoscope> | <definition> <kaleidoscope> | <expr> <kaleidoscope>
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

    mutating func nextToken() throws -> Token?
}

extension Lexer: TokenStream { }
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

    public struct Error: Swift.Error {
        public let unexpectedToken: Token?
    }

    private func consumeToken() throws {
        currentToken = try tokens.nextToken()
    }

    private func consumeToken(_ target: Token) throws {
        guard currentToken == target else { throw Error(unexpectedToken: currentToken) }
        try consumeToken()
    }
}
```

The first method simply tries to get the next token from the stream and saves the result into the buffer. In other words, we're consuming the *current* token.  
The second method might not be quite as obvious. When parsing tokens, you sometimes don't care about the *content* of the token, but rather about the *kind* of token being consumed. For example, say you're parsing an addition of two values - so something of the form `operand1 + operand2`. While you *do* care about the actual number values contained in the two operands' tokens, there is nothing to extract from the `+` sign, that is the `.operator(.plus)` token. All you need is for the token to actually be there. In this case we will call the second method, indicating that we expect the current token to be a specific kind of token. If this is not the case, we have encountered a parser error and will throw.

## Abstract Syntax Tree

Before we are able to write the parsing methods, we need to define which structures we will group the tokens into - i.e. how our AST will look like. This is where our grammar rules come into play.  
We've defined a program (a `<kaleidoscope>`) to be one or more `<extern>`, `<definition>` and `<expr>` in a specific order:

```swift
public struct Program {
    var externals: [Prototype] = []
    var functions: [Function] = []
    var expressions: [Expression] = []
}
```

As we will see later, the only relevant part of an external function's declaration is the prototype - hence the type of the `externals` property is `[Prototype]`. Prototypes that have a corresponding *definition* as well will be parsed into `Function`s - hence we call their property `functions`.

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

            if currentToken == .symbol(.rightParenthesis) {
                continue
            } else if currentToken == .symbol(.comma) {
                try! consumeToken() // know to be `.symbol(.comma)`
                if currentToken != .symbol(.rightParenthesis) { continue }
            }

            throw Error(unexpectedToken: currentToken)
        }

        return elements
    }
}
```

The method starts by parsing a `.symbol(.leftParenthesis)` and declaring the list of elements as empty. Then it tries to add elements to that list by parsing them with the given parsing function until it finds a closing `.symbol(.rightParenthesis)`. Along the way it makes sure that every element is separated by a `.symbol(.comma)`. If it finds a `.symbol(.rightParenthesis)` that's ok and it `continue`s. If the `currentToken` is a `.symbol(.comma)` that's ok as long as it is not followed by a `.symbol(.rightParenthesis)`. Any other case leads to an error being thrown.

The second helper method we'll implement is one for parsing and extracting the `String` from an `.identifier`. There's nothing special about this - it's just common enough of a task that it's worth streamlining:

```swift
extension Parser {

    private func parseIdentifier() throws -> String {
        guard case let .identifier(identifier)? = currentToken else {
            throw Error(unexpectedToken: currentToken)
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
            throw Error(unexpectedToken: currentToken)
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

Now all that remains to be implemented is parsing of `.variable` and `.binary` expressions. As we will see later, variable expressions are basically just occurrences of identifiers that are not function calls - so we won't need a separate method for them, which leaves us with binary expressions:

```plaintext
<binary> ::= <expr> <operator> <expr>
```

Although the grammar rule for binary expressions may be simple, they're actually a bit weird when you try to parse them. The problem is that you don't know in advance whether the current expression is part of a binary expression or not. You can only parse an expression, *then* notice that there's an operator following this expression which then tell's us that it's part of a binary expression.  
This approach is reflected in how we implement the parsing method for binary expressions. We will always require the expression on the left hand side to be given to us. Then we check whether there's an operator and a right hand side expression following. Only then can we construct a binary expression:

```swift
extension Parser {

    private func parseBinaryExpression(lhs: Expression) throws -> Expression {
        guard case let .operator(`operator`)? = currentToken else {
            throw Error(unexpectedToken: currentToken)
        }
        try! consumeToken() // known to be `.operator`

        let rhs = try parseExpression()

        return .binary(lhs: lhs, operator: `operator`, rhs: rhs)
    }
}
```

Now that we've handled all of the different kinds of expression we can finally get to that ominous `parseExpression` method. While all of the methods so far returned one specific kind of expression, this method will try to parse any kind of expression it finds. This of course relies heavily on the parsing methods we've just implemented.  
The biggest problem with `parseExpression` is that we don't know in advance which kind of expression we're going to parse. So we need to check for each different kind of expression in a sensible manner:

```swift
extension Parser {

    private func parseExpression() throws -> Expression {
        var expression: Expression

        switch currentToken {
        case .symbol(.leftParenthesis):
            expression = try parseParenthesizedExpression()
        case .number:
            expression = try parseNumberExpression()
        case .keyword(.if):
            expression = try parseIfExpression()
        case .identifier(let identifier):
            expression = (try? parseCallExpression()) ?? .variable(identifier)
        default:
            throw Error(unexpectedToken: currentToken)
        }

        if case .operator = currentToken {
            expression = try parseBinaryExpression(lhs: expression)
        }

        return expression
    }
}
```

Let's walk through this method step by step. The structure of the method is heavily influenced by the existence of binary expressions. As mentioned before, we can only start parsing a binary expression once we already have its left hand side - so the first thing we do in this method is create a container for that potential left hand side expression called `expression`.  
Now we need to parse *some* kind of expression based on the type of our `currentToken` - so we switch over it. The order of the cases is not important. All we do is make the following connections between the `currentToken` and the expected expression:

* `.symbol(.leftParenthesis)` → parenthesized expression
* `.number` → number literal expression
* `.keyword(.if)` → if-else expression
* `.identifier` → call expression or variable expression

As mentioned before, call expressions are basically just variable expressions (that is, an identifier) with an argument list following it. Hence, if `currentToken` is an identifier we try parsing a call expression first, and only if that fails we consider the identifier to be a variable.  
If `parseExpression` is called - that is, we're supposed to be able to parse some kind of expression - and we find *any other* `currentToken`, we don't know how to parse an expression from it and throw instead.  

Once we've successfully parsed *some* expression, i.e. we've filled `expression` with a value, we check if we're actually dealing with a binary expression by checking whether the `currentToken` is an `.operator`. If so we call the corresponding parsing method.  
Whatever results from our parsing attempts is returned in the end.

### Functions

Compared to parsing expressions, parsing the different components associated with functions will be straight forward.  
Our grammar defines four relevant rules:

```plaintext
<prototype>  ::= <identifier> <left-paren> <params> <right-paren>
<params>     ::= <identifier> | <identifier> <comma> <params>
<definition> ::= <definition-keyword> <prototype> <expr> <semicolon>
<extern>     ::= <external-keyword> <prototype> <semicolon>
```

Our AST on the other hand only defines `Function` and `Prototype`.  
As mentioned before though, external functions basically only consist of their prototype anyway so we don't need a separate type for them as well.

Let's write a parsing method for prototypes first, as externals and functions definitions both require them as a sub-step:

```swift
extension Parser {

    private func parsePrototype() throws -> Prototype {
        let identifier = try parseIdentifier()
        let parameters = try parseTuple(parsingFunction: parseIdentifier)

        return Prototype(name: identifier, parameters: parameters)
    }
}
```

There's not much to explain about this method except perhaps for the parsing of the parameter list. Just as we used `parseTuple` before for parsing the argument list in a call expression, we now use it to parse the prototype's parameter list. Whereas an *argument* list consisted of *expressions* as elements, a *parameter* list only contains the parameter *names* - so we pass `parseIdentifier` as the parsing function.

Using `parsePrototype` we can implement parsing of external function declarations and function definitions:

```swift
extension Parser {

    private func parseExternalFunction() throws -> Prototype {
        try consumeToken(.keyword(.external))
        let prototype = try parsePrototype()
        try consumeToken(.symbol(.semicolon))

        return prototype
    }

    private func parseFunction() throws -> Function {
        try consumeToken(.keyword(.definition))
        let prototype = try parsePrototype()
        let expression = try parseExpression()
        try consumeToken(.symbol(.semicolon))

        return Function(head: prototype, body: expression)
    }
}
```

Remember how we defined if-else expressions to consist of a single expression on each branch, because we don't have the concept of statements? The same holds for functions. Since we don't have statements, function bodies can only be expressions - and since we need *exactly one* return value, there can only be *exactly one* expression. Hence the body of a function can simple be parsed using `parseExpression`.  

### Program

You may not have noticed, but so far all of our parsing methods have been private. So how should a user of the `Parser` create an AST if they can't use any of the parsing methods?  
The answer is of course a public method - and we'll have it output the entire AST at once. The reason for this lies in the next step of our compiler frontend - the IR generator. Parsing only requires one token after another, so we were able to implement our lexer as a stream of tokens. The IR generator on the other hand sometimes requires global knowledge of the AST before being able to process part of it. Hence it wouldn't make as much sense to implement our parser as a stream of AST-nodes.  
Here's the method that generates the AST:

```swift
extension Parser {

    public func parseProgram() throws -> Program {
        try consumeToken()
        var program = Program()

        while currentToken != nil {
            switch currentToken {
            case .keyword(.external):
                program.externals.append(try parseExternalFunction())
            case .keyword(.definition):
                program.functions.append(try parseFunction())
            default:
                program.expressions.append(try parseExpression())
            }
        }

        return program
    }
}
```

When creating an instance of `Parser` the `currentToken` is set to `nil`, which normally would indicate the end of the token stream (`tokens`) an hence acts as an end-of-file. Therefore the this method starts by initializing the buffer (`currentToken`) with a call to `consumeToken`. It also creates an empty instance of an AST (`Program`), which will be filled with the AST-nodes that we parse from the token stream.  
We then take a similar approach as in `parseExpression` when it comes to choosing which AST-node to parse. First of all we keep parsing AST-nodes until the `currentToken` is `nil`, that is we've reached end-of-file. When determining which AST-node to parse we just check the `currentToken`:

* `.keyword(.external)` → external function declaration
* `.keyword(.definition)` → function definition
* any other → expression

It should be noted that this method will only produce a sensible result once. Since a `TokenStream` is an iterator it consumes the tokens in the process of iterating over them. So `tokens.next()` will only ever produce `nil` once `parseProgram` has finished. Any following calls to `parseProgram` would therefore return an empty AST.

# Testing the Parser

Just as we created an own test-file for our lexer, we will create one for our parser:

```terminal
marcus@KaleidoscopeLibTests: touch ParserTests.swift
marcus@KaleidoscopeLibTests: ls
LexerTests.swift	ParserTests.swift	XCTestManifests.swift
```

```swift
// ParserTests.swift

import XCTest
@testable import KaleidoscopeLib

final class ParserTests: XCTestCase {

    static var allTests = []
}
```
## Mocking the Lexer

One of the reasons we created the `TokenStream` abstraction over `Lexer` is for the purposes of testability of the parser. Instead of relying on the correctness of the lexer while testing the parser, we can just define a new token stream, solely for the purposes of testing:

```swift
private struct LexerMock: TokenStream, ExpressibleByArrayLiteral {

    enum Error: Swift.Error {
        case mock
    }

    private var nextIndex = 0
    private let tokens: [Token?]

    init(arrayLiteral tokens: Token?...) {
        self.tokens = tokens
    }

    mutating func nextToken() throws -> Token? {
        guard nextIndex < tokens.endIndex else { return nil }
        defer { nextIndex += 1 }

        guard let token = tokens[nextIndex] else { throw Error.mock }
        return token
    }
}
```

Note that this type has a built-in quirk that should make testing a bit more comfortable. The quirk lies in `tokens`' type being `[Token?]` instead of just `[Token]`. We'll use this tell the lexer-mock that it should throw by using `nil` as a marker.  
The behavior becomes evident by looking at the implementation of `nextToken`:

* *line 1:* if we've alread consumed everything in `tokens`, return `nil`
* *line 4:* if the current token is `nil`, throw a error
* *line 5:* if the current token is not `nil`, return it

## Adding Helpers

Since the only public method on `Parser` is `parseProgram`, we'll only ever be able to analyze the output of our parser by checking the properties of a `Program` AST-node. Since we're often only interested in part of the output (say the `expressions` property) and want all of the other properties to to be empty (that is `[]`), we'll define some helpers on `Program`:

```swift
private extension Program {

    func onlyContains(externals: [Prototype]) -> Bool {
        functions.isEmpty && expressions.isEmpty && (self.externals == externals)
    }

    func onlyContains(functions: [Function]) -> Bool {
        externals.isEmpty && expressions.isEmpty && (self.functions == functions)
    }

    func onlyContains(expressions: [Expression]) -> Bool {
        externals.isEmpty && functions.isEmpty && (self.expressions == expressions)
    }
}
```

Note that for this to work we need to mark our AST-nodes as equatable:

```swift
// Parser.swift

extension Program: Equatable { }
extension Prototype: Equatable { }
extension Function: Equatable { }
extension Expression: Equatable { }
```

## Writing Test Cases

Using the `LexerMock` we can e.g. implement a test case that tests the parser on an empty stream of tokens as follows:

```swift
final class ParserTests: XCTestCase {

    // ...

    func testNoTokens() throws {
        let tokens: LexerMock = []
        let parser = Parser(tokens: tokens)
        let program = try parser.parseProgram()

        XCTAssert(program.externals.isEmpty)
        XCTAssert(program.functions.isEmpty)
        XCTAssert(program.expressions.isEmpty)
    }
}
```

If we want to test how the parser handles lexer-errors we can use the aforementioned quirk in our lexer-mock:

```swift
final class ParserTests: XCTestCase {

    // ...

    func testLexerError() {
        let tokens: LexerMock = [nil]
        let parser = Parser(tokens: tokens)

        do {
            _ = try parser.parseProgram()
            XCTFail("Expected an error to be thrown.")
        } catch {
            XCTAssertTrue(error is LexerMock.Error)
        }
    }
}
```

As Swift's error handling model is currently type-erased, i.e. all that is known about an error is that it conforms to `Error`, there aren't really any error-checking APIs in XCTest. Hence we have to perform the check a bit more manually.

If you want the entire list of test cases, check out the link to the full code listing at the bottom of this post. As with the lexer tests, these test cases were written so that you can make sure that your specific implementation of the parser is correct. I found a couple of mistakes in the parser myself while writing these tests.


## Evaluating the Results

Luckily, all of the test cases are successful for the parser presented in this post. If you take a closer look at some of the test cases, they might seem like they shouldn't succeed though.  
In `testMultipleFunctionDefinitions` we succeed even though two functions have the same name `first`:

```swift
func testMultipleFunctionDefinitions() throws {
    let tokens: LexerMock = [
        .keyword(.definition), .identifier("first"),
        .symbol(.leftParenthesis), .symbol(.rightParenthesis),
        .number(10),
        .symbol(.semicolon),

        .keyword(.definition), .identifier("first"),
        .symbol(.leftParenthesis),
        .identifier("_1"), .symbol(.comma), .identifier("_2"),
        .symbol(.rightParenthesis),
        .number(100),
        .symbol(.semicolon),

        .keyword(.definition), .identifier("other"),
        .symbol(.leftParenthesis),
        .identifier("only"),
        .symbol(.rightParenthesis),
        .number(1),
        .symbol(.semicolon)
    ]

    // ...
}
```

And in `testFunctionDefinitionWithParameters` we succeed even though two parameter names are both `_1`:

```swift
func testFunctionDefinitionWithParameters() throws {
    let tokens: LexerMock = [
        .keyword(.definition), .identifier("number_10"),
        .symbol(.leftParenthesis),
        .identifier("_1"), .symbol(.comma), .identifier("_1"),
        .symbol(.rightParenthesis),
        .number(10),
        .symbol(.semicolon)
    ]

    // ...
}
```

If you think back to the post about lexers we had a similar situation:

> As you can see, some cases seem like they should not be valid, but don't fail. For example we'll never want to accept a program containing `+-*/%`, but our lexer is ok with it. This is ok, because it's not the job of the lexer to understand which combinations of tokens are allowed. This is the job of the parser [...]

The issues presented above are of the same flavor. We know that we don't want to accept them, but they're not of our parser's concern.  
In fact we haven't even captured a specification for them in our grammar! That's because these issue require what is called a *context sensitive* grammar to describe them properly. BNF-notation only allows us to specify *context free* languages, and hence our parser also recognizes a context free language.  
Implementing the context sensitive aspect of *Kaleidoscope* will be part of the next post. More specifically we will need to introduce semantic analysis as part of the IR-generator.

Until then, thanks for reading!

<br/>

---

<br/>

A full code listing for this post can be found [here](https://github.com/marcusrossel/marcusrossel.github.io/tree/master/assets/kaleidoscope/code/part-2).
