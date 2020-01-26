---
title: "Transparent Value Type Composition in Swift"
---

When creating types that have similar or overlapping functionality, it can be hard to come up with a scheme that avoids duplication without creating leaky abstractions. The tools we usually have for tackling problems in this domain are type *inheritance* and type *composition*.  

# Inheritance and Composition

Inheritance allows types to inherit all of the properties of a specific super-type. Consider the following example of types `A` and `B`:

![{{ site.url }}/assets/swift-composition/images/1.png]

If we wanted `B` to also have all of the capabilities of `A`, we could simply have it inherit from `A`:

![{{ site.url }}/assets/swift-composition/images/2.png]

At first glance this is a pretty elegant solution for sharing functionality without duplication. As you probably know though, this mechanism has its limits.  
Say we had another type `C` and wanted `B` to inherit its properties as well:

![{{ site.url }}/assets/swift-composition/images/3.png]

The illustration seems to work out, but once you try to implement this setup, you will probably find that the language of your choice only supports single inheritance - Swift being one of those languages.  
Another constraining factor is that inheritance can't be implemented on value types, as the compiler wouldn't know how much memory to allocate for a given type. This is also reflected in Swift where only classes, i.e. reference types, support inheritance.

A possible solutions to these problems is type composition. Composition allows types to be built up from other self-contained (member-)types.  
Consider the example of types `A` and `B` from above. If we wanted `B` to have all of the capabilities of `A`, we could add an instance of `A` as a member:

![{{ site.url }}/assets/swift-composition/images/4.png]

And even when we add the type `C` we can just add another member `c`:

![{{ site.url }}/assets/swift-composition/images/5.png]

So now we can compose types from multiple (member-)types and even use value types!  
One of the problems with this approach though is that properties of the member-types are nested behind another property. That is, if we want to access the property `a1` on a value of type `B`, we actually have access `a.a1`. This might seem trivial, but it can actually be problematic for proper abstraction.  
Let's say type `A` actually stands for `Animal`, `B` for `Bird` and `C` for `Creature`. Then our example declares that a bird *consists of* an animal and a creature. And if we wanted to access property `a1` (say the age of the animal), we have to access the `a1` of the nested animal. This doesn't sound right, because it simply isn't. A bird does not *have an* animal, it *is an* animal.  
This conceptual difference between a *has a* and an *is a* relationship between types, is what creates the pros and cons of inheritance as compared to composition. But isn't there a way to reap the pros while avoiding the cons?

---

*As a side note, this discussion on [composition vs. inheritance](https://en.wikipedia.org/wiki/Composition_over_inheritance) was by no means complete. The problem is much more nuanced.*

---

The paragraph above was intentionally language agnostic, because the conflict of inheritance vs. composition is universal. What I believe to be a (partial) solution to this problem though is Swift-centric (but not exclusive to Swift). Hence the rest of the post will resolve around implementations in Swift.

# Dynamic Member Lookup

There's a very cool feature in Swift that can solve type composition's nested naming problem. That is, we can implement a `Bird` as containing an `Animal` and a `Creature` instance, while exposing their properties as if they belonged to the bird itself.  
The feature we can use for this is called *dynamic member lookup*. This feature was introduced with [SE-195](https://github.com/apple/swift-evolution/blob/master/proposals/0195-dynamic-member-lookup.md):

> Dynamic member lookup allows interoperability with dynamic languages where the members of a particular instance can only be determined at runtime... but no earlier. Dynamic member lookups, therefore, tend to work with type-erased wrappers around foreign language objects (e.g., PyVal for an arbitrary Python object), ...

What dynamic member lookup tries to achieve is to make certain accesses to subscripts look as if they were actually just property accesses.  
E.g. accessing a porperty on a JSON-type might normally look like this:

```swift
json[0]?["name"]?["first"]?.stringValue
```

Implementing dynamic member lookup on the JSON-type would reduce it to this:

```swift
json[0]?.name?.first?.stringValue
```

This actually looks like the JSON-object has a property called `name` now, doesn't it?

Implementing dynamic member lookup is fairly easy:

```swift
@dynamicMemberLookup
enum JSON {

    // ...

    subscript(dynamicMember member: String) -> JSON? {
        if case .DictionaryValue(let dict) = self {
            return dict[member]
        }
        return nil
    }
}
```

All we need to do is mark the type with `@dynamicMemberLookup` and implement `subscript(dynamicMember: String)` which can return any type we want.

Let's use this to fix our nested naming problem of types `A`, `B` and `C`:

```swift
struct A {
    var a1: Int = 0
    var a2: String = ""
}

struct C {
    var c1: Double = 0.0
    var c2: Any = [Any]()
}

@dynamicMemberLookup
struct B {
    var b1: Float = 0.0
    var b2: Character = "a"

    private var a: A = A()
    private var c: C = C()

    subscript(dynamicMember member: String) -> Any? {
        switch member {
            case "a1": return a.a1
            case "a2": return a.a2
            case "c1": return c.c1
            case "c2": return c.c2
            default: return nil
        }
    }
}
```

We could now transparently access the properties `a1`, `a2`, `c1` and `c2` on values of type `B`. But there are problems abound with this implementation:

* We have to erase the property's type (i.e. return `Any`), because we don't know beforehand which value we're returning.
* We have to handle the case where the given property(-name) isn't actually suitable - we return `nil` here.
* We need to handle every possible porperty of `A` and `C` in the switch-statement. So if they have many properties we need to list many cases. And if their implementation changes, we need to update the implementation of `B` as well.

We'd really be better off just defining a computed property for every nested property:

```swift
struct B {
    var b1: Float = 0.0
    var b2: Character = "a"

    private var a: A = A()
    private var c: C = C()

    var a1: Int    { a.a1 }
    var a2: String { a.a2 }
    var c1: Double { c.c1 }
    var c2: Any    { c.c2 }
}
```

So how is this dynamic member lookup of any use for type composition?

# Key Path Member Lookup

If there's one thing Swift has an affinity for it's types. So it fit perfectly into the language when [SE-252](https://github.com/apple/swift-evolution/blob/master/proposals/0252-keypath-dynamic-member-lookup.md) introduced a type-safe version of dynamic member lookup: key path member lookup.  
Key path member lookup introduces one subtle but very important addition to the mechanism of dynamic member lookup. It allows the subscript to not only take a `String` but also a key path. The benefits of this change become very clear by updating the example above:

```swift
@dynamicMemberLookup
struct B {
    var b1: Float = 0.0
    var b2: Character = "a"

    private var a: A = A()
    private var c: C = C()

    subscript<T>(dynamicMember keyPath: KeyPath<A, T>) -> T {
        a[keyPath: keyPath]
    }

    subscript<T>(dynamicMember keyPath: KeyPath<C, T>) -> T {
        c[keyPath: keyPath]
    }
}
```

By passing a key path (`KeyPath<X, Y>`) to the subscript, we first of all know exactly which properties can even be accessed (all of the properties declared on type `X`). Hence we don't have to handle attempts of accessing invalid properties by returning an optional or throwing.  
Second of all, we now know what the type of property we're accessing is going to be (type `Y`). Hence we don't have to return `Any` from the subscript.  
And thirdly, by making the second type parameter of the key path generic (as is `T` in the example above), we can cover *all* properties of a specific type without needing to know them. So we don't need to list them one by one anymore, and can instead just propagate the key path to the nested type instance (`a[keyPath: keyPath]`).

Using key path member lookup solves all of the problems of dynamic member lookup by just reintroducing types into the equation. An implementation of `B` as shown above would now let us write statements like:

```swift
let b = B()
let firstInt = b.c2.first { $0 is Int }
print("Hello" + b.a2)
```

And key path member lookup doesn't only work on "one level". If we wanted another type `D` to "inherit" from `B`, that would work just as well:

```swift
@dynamicMemberLookup
struct D {
    var d1: Int
    var d2: Int

    private var b: B = B()

    subscript<T>(dynamicMember keyPath: KeyPath<B, T>) -> T {
        b[keyPath: keyPath]
    }
}
```

# Polymorphism

What's become clear (as e.g. seen by the "" around "inherit"), the implementation above does not preserve the relationships between types like, say, "real" class-inheritance does.

<br/>

---

<br/>

A full code listing for this post can be found [here](https://github.com/marcusrossel/marcusrossel.github.io/tree/master/assets/beat-detector/code/Part1).
