// MARK: - A

struct A /* : ChildOfA */ {
    var a1: Int = 0
    var a2: String = ""

    /*
    subscript<T>(dynamicMember keyPath: KeyPath<A, T>) -> T {
        self[keyPath: keyPath]
    }
    */
}

// MARK: - C

struct C /* : ChildOfC */ {
    var c1: Double = 0.0
    var c2: Any = [Any]()

    /*
    subscript<T>(dynamicMember keyPath: KeyPath<C, T>) -> T {
        self[keyPath: keyPath]
    }
    */
}

// MARK: - B

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

// MARK: - D

@dynamicMemberLookup
struct D {
    var d1: Int
    var d2: Int

    private var b: B = B()

    subscript<T>(dynamicMember keyPath: KeyPath<B, T>) -> T {
        b[keyPath: keyPath]
    }
}

// MARK: - Protocols

@dynamicMemberLookup
protocol ChildOfA {
    subscript<T>(dynamicMember keyPath: KeyPath<A, T>) -> T { get }
}

protocol ChildOfC {
    subscript<T>(dynamicMember keyPath: KeyPath<C, T>) -> T { get }
}

extension B: ChildOfA, ChildOfC { }

// MARK: - Usage Examples

let b = B()
let finite = b.c1.isFinite
print("Hello" + b.a2)

func printA2(of a: ChildOfA) {
    print(a.a2)
}

printA2(of: b)

/*
let a = A()
printA2(of: A)
*/
