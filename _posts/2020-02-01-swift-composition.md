---
title: "Transparent Value Type Composition in Swift"
---

When creating types that have similar or overlapping functionality, it can be hard to come up with a scheme that avoids duplication without creating leaky abstractions. The tools we usually have for tackling problems in this domain are type *inheritance* and type *composition*.  

# Inheritance and Composition

Inheritance allows types to inherit all of the properties of a specific super-type. Consider the following example of types `A` and `B`:

![1]

If we wanted `B` to also have all of the capabilities of `A`, we could simple have it inherit from `A`:

![2]

At first glance this is a pretty elegant solution for sharing functionality without duplication. As you probably know though, this mechanism has its limits.  
Say we had another type `C` and wanted `B` to inherit its properties as well:

![3]

The illustration seems to work out, but one you try to implement this setup, you will probably find that the language of your choice only supports single inheritance - Swift being one of those languages.  
Another constraining factor is that inheritance can't be implemented on value types, as the compiler wouldn't know how much memory to allocate for a given type. This is also reflected in Swift where only classes, i.e. reference types, support inheritance.

A possible solutions to these problems is type composition. Composition allows types to be built up from other self-contained (member-)types.  
Consider the example of types `A` and `B` from above. If we wanted `B` to have all of the capabilities of `A`, we could add an instance of `A` as a member:

![4]

And even when we add the type `C` we can just add another member `c`:

![5]

So now we can compose types from multiple (member-)types and even use value types!  
One of the problems with this approach though is the properties of the member-types are nested behind another property. That is, if we want to access the property `a1` on a value of type `B`, we actually have access `a.a1`. This might seem like a trivial problem, but it can actually be quite unpleasant.  
Let's say type `A` actually stands for `Animal`, `B` for `Bird` and `C` for `Creature`. Then our example declares that a bird consists of an animal and a creature. And if we wanted to access property `a1` (say the age of the animal), we have to access the `a1` of the nested animal. This neither doesn't sound right, because it simply isn't. A bird does not *have an* animal, it *is an* animal.  
This conceptual difference between a *has a* and an *is a* relationship between types, is what creates the pros and cons of inheritance as compared to composition. But isn't there a way to reap the pros while avoiding the cons?

*As a side note, this discussion on [composition vs. inheritance](https://en.wikipedia.org/wiki/Composition_over_inheritance) was by no means complete. The problem is much more nuanced.*

# Dynamic Member Lookup

The paragraph above was intentionally language agnostic, because the conflict of inheritance vs. composition is universal. What I believe to be a (partial) solution to this problem though is Swift-centric (though not exclusive to Swift).

<br/>

---

<br/>

A full code listing for this post can be found [here](https://github.com/marcusrossel/marcusrossel.github.io/tree/master/assets/beat-detector/code/Part1).
