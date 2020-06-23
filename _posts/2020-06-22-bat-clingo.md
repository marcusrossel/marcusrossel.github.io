---
title: "Using Types in a Logic Program"
---

Say you're given the following statements:

1. Tom is a bat.
2. All bats are mammals.
3. Bats usually can fly.
4. Mammals usually can not fly.

What can you infer about Tom? It's pretty clear that he's a mammal, but can or can he not fly?

To generate all of the facts that can be inferred from the statements above, we can use logic programming. For this post we'll use [*clingo*](https://potassco.org/clingo/), which is an [answer set solver](https://en.wikipedia.org/wiki/Answer_set_programming). That is, *clingo* can produce entire sets of facts (called stable models) for a given logic program instead of just answering specific inquiries.

If we were to take a straightforward approach to formulating the statements above, we might write the following:

```prolog
bat(tom).            
mammal(M) :- bat(M).
fly(B) :- bat(B).
not fly(M) :- mammal(M).
```

So ...
* `tom` is a `bat`
* if `M` is a `bat` then `M` is a `mammal`
* if `B` is a `bat` then `B` can `fly`
* if `M` is a `mammal` then `M` can not `fly`

Simple enough. So what can *clingo* infer from this?

```terminal
marcus@~: clingo tom.lp
Solving...
UNSATISFIABLE

Models       : 0
```

Well, turns out that the program is not even satisfiable. And if we take a quick look we can see why:

* `tom` is a `bat` and hence can `fly`
* `tom` is a `bat` and hence a `mammal` and hence can not `fly`

The program above expects `tom` to `fly` and not `fly` at the same time.  

So are our original statements inconsistent? Well, depends on how we interpret them. The crux of the matter is the word *"usually"*.

# Hardcoding *"usually"*

One approach we can take to fix the inconsistency above is to define what *"usually"* is supposed to mean in *this* context, and rewrite our program to incorporate that definition.

## Mammalness Dominates

First we could say that the *"mammalness"* of an object is more important than its *"batness"*. So anytime we define a fact about an object that is a `bat` *and* a `mammal`, use the definition that is `mammal`-related and not the one that is `bat`-related. This leads out program to look as follows:

```prolog
bat(tom).            
mammal(M) :- bat(M).
not fly(M) :- mammal(M).
fly(B) :- bat(B), not mammal(B).
```

So what we're saying in the last two lines here is:

* if `M` is a `mammal` then `M` can not `fly`
* if `B` is a `bat` and not a `mammal`, then `B` can `fly`

That is, the definition of `fly` relative to `mammal`s overrides the definition of `fly` relative to `bat`s.

If we run this program through *clingo* we get:

```terminal
marcus@~: clingo tom.lp
Solving...
Answer: 1
bat(tom) mammal(tom)
SATISFIABLE

Models       : 1
```

So our program is now satisfiable, which is great. But the result isn't exactly what we would probably want. The only statements that are true for this program are that Tom is a bat and Tom is a mammal. So more importantly, Tom cannot fly.

## Batness Dominates

Perhaps changing our definition of *"usually"* can solve that problem. Let's now decide that *"batness"* should dominate *"mammalness"*:

```prolog
bat(tom).            
mammal(M) :- bat(M).
fly(B) :- bat(B).
not fly(M) :- mammal(M), not bat(M).
```

So what we're saying in the last two lines here is:

* if `B` is a `bat` then `B` can `fly`
* if `M` is a `mammal` and not a `bat`, then `M` can not `fly`

That is, the definition of `fly` relative to `bat`s overrides the definition of `fly` relative to `mammal`s.

If we run this program through *clingo* we get:

```terminal
marcus@~: clingo tom.lp
Solving...
Answer: 1
bat(tom) mammal(tom) fly(tom)
SATISFIABLE

Models       : 1
```

Ah, much better. The program now allows us to infer that Tom is a bat and a mammal, and Tom can fly.

So why does *this* definition of *"usually"* produce a result that feels more correct than the one before?  
I'd say that in this example it has to do with context - specifically the rule:

```prolog
mammal(M) :- bat(M).
```

What this tells us is that `bat` is a subset of `mammal`. So being a `bat` is in some way more *specific* that being a `mammal`. And I guess humans tend to allow the specific to override the general. So eventhough the given statements (1 - 4) can be viewed as inconsistent, we tend to allow statement 3 (which is more specific) to override statement 4 (which is more general).

# Formalizing Specificity

In the solutions above, we've hardcoded specificity by making it part of the definition of `fly`. And if we defined any other predicate (like `walk`), we'd have to make sure to heed the implicit definition of specificity in the same way. Moreover, if we added some other predicate like `animal`, we'd need to update all existing rules to incorporate its specificity. So what we're really looking for is some way of formalizing the specificity of certain predicates relative to each other.

One solution to this problem comes in the form of types. I'm assuming your familiar with types from other programming languages. They're usually used to differentiate what *kinds* of values some container may hold. But they can also be used to define hierarchies between different kinds of values - most commonly via class inheritance.  
What we're interested in is only the latter - i.e. we don't care about the *kinds* of values that an object can represent, but rather where it sits in a hierarchy of types.

## Defining Types

The way we're going to define types on objects in *clingo* is pretty simple. We'll just add a predicate that tells us the type for any given object. So in our case:

```prolog
type(tom, bat).
```

Here `bat` is just a symbolic constant like `tom`, but we know that for us it represents the *type* of `tom`.  
Now we could just go ahead and add `type(tom, mammal)`, but since we know that *every* `bat` is supposed to be a `mammal`, we'll express this fact by adding the concept of subtyping.  
The type-hierarchy will just be expressed by a single predicate that tells us whether a given type is the subtype of another:

```prolog
subtype(bat, mammal).
```

This fact alone doesn't really accomplish much yet, but by adding the following rule we actually start getting somewhere:

```prolog
type(V, T) :- type(V, S), subtype(S, T).
```

What this rule enforces is that, if an object `V` has type `S`, and `S` is a subtype of `T`, then `V` is also of type `S`. So what this establishes is that any value of some specific sub-type is also a value of a more general super-type.  
This allows to only specify the *most* specific type of a value, and then *clingo* will infer that the value also belongs to any super-type. So if we run *clingo* on ...

```prolog
type(tom, bat).
subtype(bat, mammal).
type(V, T) :- type(V, S), subtype(S, T).
```

... we get ...

```terminal
marcus@~: clingo tom.lp
Solving...
Answer: 1
subtype(bat,mammal) type(tom,bat) type(tom,mammal)
SATISFIABLE

Models       : 1
```

... which is exactly what we want.

## Defining Predicates Relative to Types

Sofar we've been able to capture statements 1 and 2 in our type-based program. So how do we express statements 3 and 4?  
Let's start with a naive approach again and see how that works out:

```prolog
type(tom, bat).
subtype(bat, mammal).
type(V, T) :- type(V, S), subtype(S, T).

fly(B) :- type(B, bat).
not fly(M) :- type(M, mammal).
```

What were expressing in the last two lines here is:

* if object `B` has type `bar` then `B` can `fly`
* if object `M` has type `mammal` then `M` can not `fly`

And as you may have guessed ...

```terminal
marcus@~: clingo tom.lp
Solving...
UNSATISFIABLE

Models       : 0
```

... the program is again unsatisfiable. For the same reason infact as in our very first version of the program.  
It doesn't work because *each* rule of a predicate definition is enabled for *all* objects that have the specified type. What we actually want though, is to enable a rule of a predicate definition only if the specified type is the *most specific* type of the given object.  
And this is where our type-based variant of the program is more powerful than the predicate-based ones before. Where as before we couldn't express *any* relationship between the predicates `bat` and `mammal` explicitly, we now can. What were previously predicates are now just symbolic constants `bat` and `mammal`, so we can define predicates *about them*. Infact we already have with the `subtype` predicate. Moreover, to fix the problem of our current program in a general way, we can define a predicate that gives us the *most specific* type of a given value:

```prolog
groundtype(V, T) :- type(V, T), not midtype(V, T).
midtype(V, T) :- type(V, T), type(V, S), subtype(S, T).
```

Here we call the most specific type of an object its `groundtype`. The precise definition is a bit technical, but not really that important. We say that `T` is a ground-type for `V` if `V` has type `T` and `T` is not a `midtype` for `V`.  
A type `T` is a mid-type for `V` if there is some subtype `S` of `T` that is also a type of `V`.  
So in consequence `groundtype` contains all pairs `V`, `T` such that there is no other type `S` of `V` that is subtype of `T` - i.e. `T` is a most specific type of `V`.

> *Note:*  
> We're not saying "**the** most specific type" here, because an object can have multiple ground-types.

Using the concept of a ground-type, we can now rewrite the predicate definitions in our program:

```prolog
type(tom, bat).
subtype(bat, mammal).
type(V, T) :- type(V, S), subtype(S, T).

groundtype(V, T) :- type(V, T), not midtype(V, T).
midtype(V, T) :- type(V, T), type(V, S), subtype(S, T).

fly(B) :- groundtype(B, bat).
not fly(M) :- groundtype(M, mammal).
```

And finally, if we run this through *clingo*, we get ...

```terminal
marcus@~: clingo tom.lp
Solving...
Answer: 1
subtype(bat,mammal) type(tom,bat) type(tom,mammal) midtype(tom,mammal) groundtype(tom,bat) fly(tom)
SATISFIABLE

Models       : 1
```

... so Tom can fly!

# Details and Extensions

As neat as the programming above may look, there are a bunch of cases that we haven't considered yet. For example, our system above would break instantly if we added just a single new type to the hierarchy. That's because our `subtype`-relation isn't transitive yet. This can be fixed easily though:

```prolog
subtype(S, T) :- subtype(S, M), subtype(M, T).
```
