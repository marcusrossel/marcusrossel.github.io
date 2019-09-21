---
title: "Implementing LLVM's Kaleidoscope in Swift - Part 1"
---

As we saw in the last post, our compiler frontend will be split into a lexer, parser and IR generator. This post will deal with the lexer.

---

The lexer is the part of the compiler that deals with the raw source code of the target language. It moves along the source text, character by character, grouping those characters into meaningful units called _lexemes_ or _tokens_.  
We humans do this rather intuitively. Consider this example:

```plaintext
def triple(x) (3.0 * x);
```

When reading this code, you're probably grouping certain characters together. The `d` `e` `f` because it's a keyword, the `t` `r` `i` `p` `l` `e` because it's an identifier and the `3` `.` `0` because it's a number. And you're also categorizing certain characters. The `*` as an operator, and the `;` as a terminator of some sort.  
All of these categories that we intuitively form in our mind are examples of different kinds of tokens - different kinds of syntactically meaningful units. So if we we're to write our source code in _tokens_ instead of plain _characters_, it would look like this:

```plaintext
Keyword: "def"
Identifier: "double"
Special Symbol: "("
Identifier: "x"
Special Symbol: ")"
Special Symbol: "("
Number: "2.0"
Operator: "*"
Identifier: "x"
Special Symbol: ")"
Special Symbol: ";"
```

So the job of our lexer is to take the _character_ representation of our source code and turn it into a _token_ representation.  
Because programming languages are formal languages, we again need to have certain rules that tell us how to group characters into tokens. Luckily we've pretty much alread written those rules.

# Grammar Adjustments

In the last post we settled on a grammar for Kaleidoscope.  
As I mentioned, we can really split it into two parts though: the part that the lexer handles and the part that the parser handles.  
As we've just learned the lexer is responsible for creating tokens from raw characters, so we can split the grammar as follows:

```plaintext
// Lexer:

<operator>        ::= "+" | "-" | "*" | "/" | "%"
<identifier>      ::= <identifier-head> | <identifier> <identifier-body>
<identifier-body> ::= <identifier-head> | <digit>
<identifier-head> ::= #Foundation.CharacterSet.letter# | "_"
<number>          ::= <digits> | <digits> "." <digits>
<digits>          ::= <digit> | <digit> <digits>
<digit>           ::= "0" | "1" | ... | "9"

// Parser:

<kaleidoscope> ::= <prototype> | <definition> | <expr> | <prototype> <kaleidoscope> | <definition> <kaleidoscope> | <expr> <kaleidoscope>
<prototype>    ::= <identifier> "(" <params> ")"
<params>       ::= <identifier> | <identifier> "," <params>
<definition>   ::= "def" <prototype> <expr> ";"
<extern>       ::= "extern" <prototype> ";"
<expr>         ::= <binary> | <call> | <identifier> | <number> | <ifelse> | "(" <expr> ")"
<binary>       ::= <expr> <operator> <expr>
<call>         ::= <identifier> "(" <arguments> ")"
<ifelse>       ::= "if" <expr> "then" <expr> "else" <expr>
<arguments>    ::= <expr> | <expr> "," <arguments>
```

Now the lexer is dealing mainly with what we call *teminal symbols* - that is raw characters (written between `""` in BNF notation). As we will see later on in this tutorial, we want our parser to only deal with *non-terminal symbols* - that is symbols constructed from other symbols (written between `<>` in BNF notation).  
Our current grammar does not quite fulfil this requirement yet, so we will modify it like this:

```plaintext
// Lexer:

<left-paren>         ::= "("
<right-paren>        ::= ")"
<comma>              ::= ","
<semicolon>          ::= ";"
<definition-keyword> ::= "def"
<external-keyword>   ::= "extern"
<if-keyword>         ::= "if"
<then-keyword>       ::= "then"
<else-keyword>       ::= "else"
<operator>           ::= "+" | "-" | "*" | "/" | "%"
<identifier>         ::= <identifier-head> | <identifier> <identifier-body>
<identifier-body>    ::= <identifier-head> | <digit>
<identifier-head>    ::= #Foundation.CharacterSet.letter# | "_"
<number>             ::= <digits> | <digits> "." <digits>
<digits>             ::= <digit> | <digit> <digits>
<digit>              ::= "0" | "1" | ... | "9"

// Parser:

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

This might seem like a useless change, because we're just giving certain characters explicit non-terminal symbols. It does have the effect though of clearly showing the responsibilities of lexer and parser. And as bonus, if we ever decide to change the `def` keyword to `func`, we only need to change the implementation of the lexer in one spot. The parser does not need to care about the textual representation of the `definition-keyword` anymore and will just keep working.

# Implementation Methods

There are different ways of implementing a lexer that involve more or less work for yourself. A neat feature of lexers is that they can be described using *type-3 grammars*, also know as *regular grammars*.  
The classification of different types of grammars again belongs to the field of formal language theory. But put simply, a regular grammar is a grammar constrained to only contain certain types of formation rules.  For example, regular expressions are a way of writing grammars in a way that only allows you to create regular grammars. So we should probably use regexes for our lexer then, right? - It depends. There are some great discussions about the [pros](https://softwareengineering.stackexchange.com/questions/329987/is-it-appropite-for-a-tokenizer-to-use-regex-to-gather-tokens) and [cons](https://news.ycombinator.com/item?id=2915137) of regexes for lexers. But for the purpose of this tutorial, I will not be using them.  
There are also [programs](http://catalog.compilertools.net/lexparse.html) that can generate lexers and parsers for you. Such programs generally require you to specify the grammar of your language, and then generate the source code of a lexer and/or parser in some target language. This would of course be counterproductive for learning how to write a lexer, so we will not be using them either.  
So we're left with what we all new was coming anyway - we're going to write the lexer by hand.

# Writing the Lexer

Writing the lexer is split into three parts. First we need to set up some functionality that we will later need to easily transform text into tokens. Then we need to actually define what our tokens are. And only then will we write the actual token transformations.

## Structure

Our lexer needs to have some basic properties. It needs to hold the source code that we are lexing and the position of the character in the source code which needs to be lexed next:

```swift
public final class Lexer {

    /// The plain text, which will be lexed.
    public private(set) var text: String

    /// The position of the next relevant character in `text`.
    public private(set) var position: Int

    /// Creates a lexer for the given text, with a starting position of `0`.
    public init(text: String) {
        self.text = text
        position = 0
    }
}
```

We also need a way of obtaining characters from and moving along the `text` in a convenient way. We will implement a method that allows us to consume a variable number of characters from the `text` as well as peeking ahead without changing our `position`:

```swift
public final class Lexer {

    // ...    

    /// Returns the the next character in `text`.
    ///
    /// - Note: If `position` has reached `text`'s end index, `nil` is returned
    /// on every subsequent call.
    ///
    /// - Parameter peek: Determines whether or not the lexer's `position` will
    /// be affected or not.
    /// - Parameter stride: The offset from the current `position` of the
    /// returned character (must be >= 1). The `stride` also affects the amount
    /// by which `position` will be increased.
    private func nextCharacter(peek: Bool = false, stride: Int = 1) -> Character? {
        // Precondition.
        guard stride >= 1 else {
            fatalError("Lexer Error: \(#function): `stride` must be >= 0.\n")
        }

        // Because `position` always points to the "next relevant character", a
        // stride of `1` should result in the `nextCharacterIndex` being equal
        // to `position`. Therefore the `- 1` at the end.
        let nextCharacterIndex = position + stride - 1

        // Changing the value of `position` should only happen after we have
        // determined what our next character is. Therefore the `defer`.
        defer {
            // Only increases the `position` if we are not peeking.
            // If the new `position` would go beyond the `text`'s end index, it
            // is instead capped at the end index (`text.count`).
            // The new `position` is `position + stride` (without `- 1`),
            // because it has to point to the character after the one we are
            // returning during this method call.
            if !peek { position = min(position + stride, text.count) }
        }

        // If the `nextCharacterIndex` is out of bounds, return `nil`.
        guard nextCharacterIndex < text.count else { return nil }


        return text[text.index(text.startIndex, offsetBy: nextCharacterIndex)]
    }
}
```

Now that we are able to easily iterate over the characters in the `text`, we also want to have a method for iterating over the tokens contained in that text. This method will rely on the aforementioned token transformations.

```swift
public final class Lexer {

    // ...

    private typealias TokenTransformation = (Lexer) -> () throws -> Token?    

    /// An ordered list of the token transformations, in the order in which they
    /// should be called by `nextToken`.
    private let transformations: [TokenTransformation] = [
        lexWhitespace,
        lexIdentifiersAndKeywords,
        lexNumbers,
        lexSpecialSymbolsAndOperators,
        lexInvalidCharacter
    ]

    /// Tries to return the next token lexable from the `text`.
    /// If there is a syntactical error in the `text`, an error is thrown.
    /// If there are no more characters to be lexed, `nil` is returned.
    public func nextToken() throws -> Token? {
        for transformation in transformations {
            if let token = try transformation(self)() {
                return token
            }
        }

        return nil
    }
}
```

This snippet implements a lot of the structure of our lexer.  
The `nextToken` method shows that we will be generating tokens by simply iterating over our token transformations, returning a token as soon as a transformation was successful. The order in which we try out the token transformations is defined by the `transformations` array. It simply holds references to the token transformations (which we are yet to implement).  
The method also shows that there are two reasons why a token may not be returned. If there are no more characters left to be lexed, all of our token transformations will return `nil` (we will implement them that way), in which case we fall out of the for-loop and return `nil` as well. If there is a syntactical error in the source code, the token transformations have the option to throw an error, which the `nextToken` method will pass along. This is in fact the only task of the `lexInvalidCharacter` method. If this method is called and there are still characters to be lexed it will always throw an error, because if we reach this method, all other transformations must have failed, which means that we are dealing with an invalid character.

## Tokens

Before we are able to write the token transformations, we need to define which tokens we can even generate. An enum is well suited for this, as it can capture all different kinds of data.

```swift
public enum Token {

    case keyword(Keyword)
    case identifier(String)
    case number(Double)

    case `operator`(Operator)
    case symbol(Symbol)

    public enum Keyword: String {
        case `if`
        case then
        case `else`
        case definition = "def"
        case external = "extern"
    }

    public enum Symbol: Character {
        case leftParenthesis = "("
        case rightParenthesis = ")"
        case comma = ","
        case semicolon = ";"
    }
}

public enum Operator: Character {
    case plus = "+"
    case minus = "-"
    case times = "*"
    case divide = "/"
    case modulo = "%"
}
```

The kinds of tokens we define, basically corresponds to our grammar. We group the keywords, symbols and operators together in seperate enums, so that they can have raw values. This way we define the textual representations of these tokens right with their definition. This will also make lexing them a bit more convenient. The `Operator` enum is not a subtype of the `Token` type, because it will be used outside the context of tokens later on as well.

Note that we are only defining tokens for those symbols which will later be used by the parser. Symbols in our grammar like `digits` and `identifier-head` are useful for defining `number` and `identifier`, but will not actually need to be implemented.

## Token Transformations

Now that we have the structure of our lexer in place, and have defined our tokens, we can start writing the actual token transformations. We will start with the easier ones and work our way towards the more difficult.

```swift
public final class Lexer {

    // ...

    public enum Error: Swift.Error {
        case invalidCharacter(Character)
    }

    /// Treats any lexed character as invalid, and throws
    /// `Error.invalidCharacter`.
    /// If there are no characters to be lexed, `nil` is returned.
    private func lexInvalidCharacter() throws -> Token? {
        if let character = nextCharacter() {
            throw Error.invalidCharacter(character)
        } else {
            return nil
        }
    }
}
```

This method works exactly as described above.  

```swift
public final class Lexer {

    // ...

	/// Consumes whitespace (and newlines). Always returns `nil`.
    private func lexWhitespace() -> Token? {
        while nextCharacter(peek: true).isPartOf(.whitespacesAndNewlines) {
            _ = self.nextCharacter()
        }
        
        return nil
    }
}

extension Character {
    
    /// Indicates whether the given character set contains this character.
    func isPartOf(_ set: CharacterSet) -> Bool {
        return String(self).rangeOfCharacter(from: set) != nil
    }
}

extension Optional where Wrapped == Character {
    
    /// Indicates whether the given character set contains this character.
    /// If `self == nil` this is false.
    func isPartOf(_ set: CharacterSet) -> Bool {
        guard let self = self else { return false }
        return self.isPartOf(set)
    }
}
```

In order to conveniently work with characters and character sets, we define some extensions on `Character`, as well as optional characters. The `isPartOf` methods simply tell us whether or not a character is part of a character set. If an optional character is `nil` this is of course false.  
The `lexWhitespace` method consumes whitespace and newline characters until something else is encountered. This method is not intended to produce a token, so it always returns `nil` at the end. This method is first in the list of token transformations, so that whitespace does not need to be handled by the other transformations down the line.

```swift
public final class Lexer {

    // ...

    private func lexSpecialSymbolsAndOperators() -> Token? {
        guard let character = nextCharacter(peek: true) else { return nil }
        
        if let specialSymbol = Token.Symbol(rawValue: character) {
            _ = nextCharacter()
            return .symbol(specialSymbol)
        }
        
        if let `operator` = Operator(rawValue: character) {
            _ = nextCharacter()
            return .operator(`operator`)
        }
        
        return nil
    }
}
```

This is our first real transformation. The method generates tokens that are special symbols or operators - so consist of a single character.  
It starts by obtaining the next character without consuming it (by passing `peek: true`). It is important that we don't consume characters before we know if we can even turn them into tokens!  
We check whether we can convert the character into a token, by trying to initialize a `Token.Symbol` or `Operator` from the raw character value. If this fails, we know that the character is neither a special symbol nor operator and we return `nil`. If it succeeds though, we consume the character (by calling `nextCharacter()`) so that future transformations will not be exposed to it anymore. We then return the token equivalent of the character.

```swift
public final class Lexer {

    // ...

    /// The set of characters allowed as an identifier's head.
    private let identifierHead: CharacterSet

    /// The set of characters allowed as an identifier's body.
    private let identifierBody: CharacterSet
    
    /// Creates a lexer for the given text, with a starting position of `0`.
    public init(text: String) {
        self.text = text
        position = 0
        
        identifierHead = CharacterSet
            .letters
            .union(CharacterSet(charactersIn: "_"))
        identifierBody = identifierHead.union(.decimalDigits)
    }

    // ...

    private func lexIdentifiersAndKeywords() -> Token? {
        guard nextCharacter(peek: true).isPartOf(identifierHead) else {
            return nil
        }
        
        var buffer = "\(nextCharacter()!)"
        
        while nextCharacter(peek: true).isPartOf(identifierBody) {
            buffer.append(nextCharacter()!)
        }

        if let keyword = Token.Keyword(rawValue: buffer) {
            return .keyword(keyword)
        } else {        
            return .identifier(buffer)
        }
    }    
}
```

The token transformation for identifiers requires us to define what characters can be at the head and in the body of an identifier. Our grammar has the following rules:

```plaintext
<identifier-body> ::= <identifier-head> | <digit>
<identifier-head> ::= #Foundation.CharacterSet.letter# | "_"
```

Because there are no predefined character sets in *Foundation* that contain exactly these characters, we need to define them ourselves. This is why we need to add the `identifierHead` and `identifierBody` properties and adjust the lexer's initializer a bit.

The token transform itself is again fairly simple. It starts by checking whether the next character is a valid identifier head, without consuming it. If it is not we return `nil`, because that means that we can parse neither keywords nor identifiers (keywords being special identifiers). If it is, we go on to save characters into a buffer as long as they are valid for an identifier. Once we reach an non-identifier character, we check whether our buffer corresponds to a keyword and either return a keyword or identifier token accordingly.


```swift
public final class Lexer {

    // ...

    private func lexNumbers() -> Token? {
        guard nextCharacter(peek: true).isPartOf(.decimalDigits) else {
            return nil
        }
        
        var buffer = "\(nextCharacter()!)"
        
        while nextCharacter(peek: true).isPartOf(.decimalDigits) {
            buffer.append(nextCharacter()!)
        }
        
        if nextCharacter(peek: true) == "." &&
           nextCharacter(peek: true, stride: 2).isPartOf(.decimalDigits)
        {
            buffer.append(".\(nextCharacter(stride: 2)!)")
            
            while nextCharacter(peek: true).isPartOf(.decimalDigits) {
                buffer.append(nextCharacter()!)
            }
        }
        
        guard let number = Double(buffer) else {
            fatalError("Lexer Error: \(#function): internal error.")
        }
        
        return .number(number)
    }
}
```

The transformation for numbers is the last and most difficult for our lexer.
We start off by saving digit-characters into a buffer, until we reach a non-digit. Our grammar for numbers is as follows:

```plaintext
<number> ::= <digits> | <digits> "." <digits>
<digits> ::= <digit> | <digit> <digits>
<digit>  ::= "0" | "1" | ... | "9"
```

So we need to be able to lex integers as well as floating point numbers.  
This is what the if-statement achieves. If checks whether the next two characters are a `.` followed by a digit. If so, we're dealing with a floating point number. So we add the characters to the buffer and again start consuming digit characters as long as we can. If not we have an integer and our buffer is already complete.  
Finally we convert the string representation of the number into a `Double` and return it in a `.number` token.  
The conversion from the `String` to `Double` should actually never fail, which is why we `fatalError` if it does.

# Testing the Lexer