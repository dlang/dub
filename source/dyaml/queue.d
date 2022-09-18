
//          Copyright Ferdinand Majerech 2011-2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dyaml.queue;


import std.traits : hasMember, hasIndirections;

package:

/// Simple queue implemented as a singly linked list with a tail pointer.
///
/// Needed in some D:YAML code that needs a queue-like structure without too much
/// reallocation that goes with an array.
///
/// Allocations are non-GC and are damped by a free-list based on the nodes
/// that are removed. Note that elements lifetime must be managed
/// outside.
struct Queue(T)
if (!hasMember!(T, "__xdtor"))
{

private:

    // Linked list node containing one element and pointer to the next node.
    struct Node
    {
        T payload_;
        Node* next_;
    }

    // Start of the linked list - first element added in time (end of the queue).
    Node* first_;
    // Last element of the linked list - last element added in time (start of the queue).
    Node* last_;
    // free-list
    Node* stock;

    // Length of the queue.
    size_t length_;

    // allocate a new node or recycle one from the stock.
    Node* makeNewNode(T thePayload, Node* theNext = null) @trusted nothrow @nogc
    {
        import std.experimental.allocator : make;
        import std.experimental.allocator.mallocator : Mallocator;

        Node* result;
        if (stock !is null)
        {
            result = stock;
            stock = result.next_;
            result.payload_ = thePayload;
            result.next_ = theNext;
        }
        else
        {
            result = Mallocator.instance.make!(Node)(thePayload, theNext);
            // GC can dispose T managed member if it thinks they are no used...
            static if (hasIndirections!T)
            {
                import core.memory : GC;
                GC.addRange(result, Node.sizeof);
            }
        }
        return result;
    }

    // free the stock of available free nodes.
    void freeStock() @trusted @nogc nothrow
    {
        import std.experimental.allocator.mallocator : Mallocator;

        while (stock !is null)
        {
            Node* toFree = stock;
            stock = stock.next_;
            static if (hasIndirections!T)
            {
                import core.memory : GC;
                GC.removeRange(toFree);
            }
            Mallocator.instance.deallocate((cast(ubyte*) toFree)[0 .. Node.sizeof]);
        }
    }

public:

    @disable void opAssign(ref Queue);
    @disable bool opEquals(ref Queue);
    @disable int opCmp(ref Queue);

    this(this) @safe nothrow @nogc
    {
        auto node = first_;
        first_ = null;
        last_ = null;
        while (node !is null)
        {
            Node* newLast = makeNewNode(node.payload_);
            if (last_ !is null)
                last_.next_ = newLast;
            if (first_ is null)
                first_      = newLast;
            last_ = newLast;
            node = node.next_;
        }
    }

    ~this() @safe nothrow @nogc
    {
        freeStock();
        stock = first_;
        freeStock();
    }

    /// Returns a forward range iterating over this queue.
    auto range() @safe pure nothrow @nogc
    {
        static struct Result
        {
            private Node* cursor;

            void popFront() @safe pure nothrow @nogc
            {
                cursor = cursor.next_;
            }
            ref T front() @safe pure nothrow @nogc
            in(cursor !is null)
            {
                return cursor.payload_;
            }
            bool empty() @safe pure nothrow @nogc const
            {
                return cursor is null;
            }
        }
        return Result(first_);
    }

    /// Push a new item to the queue.
    void push(T item) @nogc @safe nothrow
    {
        Node* newLast = makeNewNode(item);
        if (last_ !is null)
            last_.next_ = newLast;
        if (first_ is null)
            first_      = newLast;
        last_ = newLast;
        ++length_;
    }

    /// Insert a new item putting it to specified index in the linked list.
    void insert(T item, const size_t idx) @safe nothrow
    in
    {
        assert(idx <= length_);
    }
    do
    {
        if (idx == 0)
        {
            first_ = makeNewNode(item, first_);
            ++length_;
        }
        // Adding before last added element, so we can just push.
        else if (idx == length_)
        {
            push(item);
        }
        else
        {
            // Get the element before one we're inserting.
            Node* current = first_;
            foreach (i; 1 .. idx)
                current = current.next_;

            assert(current);
            // Insert a new node after current, and put current.next_ behind it.
            current.next_ = makeNewNode(item, current.next_);
            ++length_;
        }
    }

    /// Returns: The next element in the queue and remove it.
    T pop() @safe nothrow
    in
    {
        assert(!empty, "Trying to pop an element from an empty queue");
    }
    do
    {
        T result = peek();

        Node* oldStock = stock;
        Node* old = first_;
        first_ = first_.next_;

        // start the stock from the popped element
        stock = old;
        old.next_ = null;
        // add the existing "old" stock to the new first stock element
        if (oldStock !is null)
            stock.next_ = oldStock;

        if (--length_ == 0)
        {
            assert(first_ is null);
            last_ = null;
        }

        return result;
    }

    /// Returns: The next element in the queue.
    ref inout(T) peek() @safe pure nothrow inout @nogc
    in
    {
        assert(!empty, "Trying to peek at an element in an empty queue");
    }
    do
    {
        return first_.payload_;
    }

    /// Returns: true of the queue empty, false otherwise.
    bool empty() @safe pure nothrow const @nogc
    {
        return first_ is null;
    }

    /// Returns: The number of elements in the queue.
    size_t length() @safe pure nothrow const @nogc
    {
        return length_;
    }
}

@safe nothrow unittest
{
    auto queue = Queue!int();
    assert(queue.empty);
    foreach (i; 0 .. 65)
    {
        queue.push(5);
        assert(queue.pop() == 5);
        assert(queue.empty);
        assert(queue.length_ == 0);
    }

    int[] array = [1, -1, 2, -2, 3, -3, 4, -4, 5, -5];
    foreach (i; array)
    {
        queue.push(i);
    }

    array = 42 ~ array[0 .. 3] ~ 42 ~ array[3 .. $] ~ 42;
    queue.insert(42, 3);
    queue.insert(42, 0);
    queue.insert(42, queue.length);

    int[] array2;
    while (!queue.empty)
    {
        array2 ~= queue.pop();
    }

    assert(array == array2);
}
