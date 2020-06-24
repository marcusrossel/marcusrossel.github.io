---
title: "Adding Types to a Logic Program"
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

# Shortcomings and Extensions

As neat as the program above may look, it really only works within the context of the given statements. If we were to change almost anything about the types, their hierarchy or the associated predicates, our curreng implementation would break.  
So to conclude this post, let's look at some of the problems the current implementation has, as well as how we could extend it.

### Deeper Type Hierarchies

In the program about Tom, the deepest type hierarchy only had a depth of 2. If we added just a single new type to that hierarchy, the program wouldn't work correctly. Say we add a new `animal` type:

```clingo
subtype(mammal, animal).
```
Then *clingo* won't infer that `tom` is an `animal`, because our `subtype`-relation isn't transitive yet. This can be fixed easily though:

```prolog
subtype(S, T) :- subtype(S, M), subtype(M, T).
```

This new rule in combination with our existing rule ...

```prolog
type(V, T) :- type(V, S), subtype(S, T).
```

... adds every super-type of a value `V` as a type for `V`.

### Multiple Inheritance

Another problem that our *"type system"* (big quotes) would potentially have to deal with is multiple inheritance. That is, there's nothing restricting us from writing something like:

```prolog
subtype(lion, pet).
subtype(lion, animal).
type(dan, lion).
```

Multiple inheritance has a reputation for being tricky, e.g. by virtue of the [diamond problem](https://en.wikipedia.org/wiki/Multiple_inheritance#The_diamond_problem). So optimally we'd like to restrict our subtyping model to enforce single inheritance:

```prolog
P1 == P2 :- subtype(T, P1), subtype(T, P2).
```

All that this line tells us is that if some type `T` has parents `P1` *and* `P2`, then those parents must actually be the same type. So in effect any type can have at most one parent, which disallows multiple inheritance.

### Non-Overriding Subtypes

Say we added a new kind of mammal that can't fly:

```prolog
subtype(lion, mammal).
type(dan, lion).
```

Then we would expect this new rule to be sufficient for Dan to not fly, since we've already defined that `mammal`s cannot fly. But this is in fact not sufficient, since the non-flyingness of `mammal`s is only defined for objects whose *ground-type* is `mammal`, and we haven't added a separate definition relative to `lion`s.
As it turns out, the ground-type of an object is not *generally* sufficient for determining which definition of a predicate should be used for that object. Say we had the following hierarchy:

```
creature  -  defines fly
  |
animal    -  inherits fly from creature
  |
mammal    -  defines fly
  |
lion      -  inherits fly from mammal
  |
<dan>     -  is lion
```

To determine what the correct definition of `fly` is for `dan`, we need to know what the definition is for `lion`s. And since `lion`s inherit their `fly`-definition from `mammals`, we in turn need to know their defintion. I.e. we need to propagate definitions down the hierarchy tree until a subtype implements a definition of its own - aka overrides it.  
This again poses the problem of defining predicates *about predicates*. So we'll solve it the same way as we did with types, by replacing the predicates with symbolic constants that we'll now call *properties*.

#### Formalizing Properties

Defining a property on an object now takes the form:

```prolog
property(<property name>, <object>, <value(s)>).
```

This definition of properties can handle properties with all kinds of values:

```prolog
property(fly, dan, false).
```

... tells us that `dan` can `fly` is `false` (which is also just a symbolic constant). And ...


```prolog
property(coordinates, tom, 145, 23).
```

... tells us that the `coordinates` of `tom` are `145, 23`.

> *Note:*
> Whereas before `not fly(dan).` meant that Dan can't fly, `not property(fly, dan, _).` would now mean that the property `fly` is not defined on object `dan`.

We can get a feel for this new notion of properties, by rewriting our existing Tom-program:

```prolog
type(tom, bat).
subtype(bat, mammal).
type(V, T) :- type(V, S), subtype(S, T).

groundtype(V, T) :- type(V, T), not midtype(V, T).
midtype(V, T) :- type(V, T), type(V, S), subtype(S, T).

property(fly, B, true) :- groundtype(B, bat).
property(fly, M, false) :- groundtype(M, mammal).
```

As you can see, we barely had to change anything, which is nice.

What we'll be relying on much more though, is defining properties on *types*. Whereas the semantics of properties on objects are pretty clear, the semantics of properties on types don't seem to be as obvious. So we'll define them as follows:   
A property can be defined on a type by using the `property` predicate but replacing the object with a type.  
If a type `T` does not define a property `P`, but it is a subtype of a type that does define `P`, then `T` inherits that definition of `P`.  
If an object `O` of type `T` does not define a property `P`, then `O` inherits `T`'s definition of `P`.  

#### Formalizing Overrides

Using properties, we can formalize the concept of *overriding*, which will allow us to select the right definition of each property within a type hierarchy.

We say that a type or object `X` overrides a property `P`, whenever there is a *"manual definition"* of `P` relative to `X`. All we mean by *"manual definition"* is that the definition was literally written into the program, and not inferred by it.

In order to detect overriding we'll just add a new predicate `define` that is used to define properties on a type:

```prolog
property(P, X, V) :- define(P, X, V).
```

So whenever we define a property on a type or object, we make sure the property is set but we also remember which types manually defined the property by virtue of the `define` predicate.

#### Properties in a Type Hierarchy

Getting back to the crux of the problem, we now want to make sure that properties of some super-type are propagated down its type hierarchy only to the point of an override. Now that we have defined a concept of overrides, this becomes surprisingly easy:

```prolog
property(P, S, V) :- property(P, T, V), subtype(S, T), not define(P, S, _).
property(P, O, V) :- property(P, T, V), groundtype(O, T), not define(P, O, _).
```

The first rule implements property propagation for types. It propagates the definition of property `P` from type `T` to subtype `S`, only if `S` does not override `P`.   
The second rule just does the same for objects. If an object `O` does not define a property `P` it inherits that definition from its ground-type. Note that this is basically analogous to our initially faulty approach where:

```prolog
fly(B) :- groundtype(B, bat).
```

But now we know that every type inherits its super-type's properties, so this approach works fine.

# Conclusion

If we put all of the pieces together to solve the Tom-problem, we get the following:

```prolog
type(tom, bat).
subtype(bat, mammal).
define(fly, bat, true).
define(fly, mammal, false).

type(V, T) :- type(V, S), subtype(S, T).
subtype(S, T) :- subtype(S, M), subtype(M, T).
P1 == P2 :- subtype(T, P1), subtype(T, P2).

groundtype(V, T) :- type(V, T), not midtype(V, T).
midtype(V, T) :- type(V, T), type(V, S), subtype(S, T).

property(P, X, V) :- define(P, X, V).
property(P, S, V) :- property(P, T, V), subtype(S, T), not define(P, S, _).
property(P, O, V) :- property(P, T, V), groundtype(O, T), not define(P, O, _).
```

... which IMHO is really cool. The original four statements are now super clear and our *"type system"* consists of only 8 rules. And *clingo* correctly infers a bunch of things:

```terminal
Solving...
Answer: 1
subtype(bat,mammal) type(tom,bat) type(tom,mammal) midtype(tom,mammal) groundtype(tom,bat) define(fly,bat,true) define(fly,mammal,false) property(fly,bat,true) property(fly,mammal,false) property(fly,tom,true)
SATISFIABLE

Models       : 1
```

... most importantly `property(fly, tom, true)`.

---

As you can see, the topic of types is quite endless once you dive in. Especially in a strictly declarative language like *clingo* you can compose these systems quite neatly without worrying about any control *flow*.   
On the other hand, types can become quite tricky once you extend their power even a little. So there are many edge cases that could cause problems if unheeded.

> *Update:*  
> For example I just noticed that we still have the problem of multiple inheritance when it comes to this rule:
> ```clingo
> property(P, O, V) :- property(P, T, V), groundtype(O, T), not define(P, O, _).
> ```
> ... since we haven't restricted the number of ground-types an object can have.

But regardless, I find types to be really fun to play around with, and perhaps you now feel inclined to do the same. After all, the system we've built above is really incomplete 😉

Thanks for reading!
