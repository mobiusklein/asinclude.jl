# asinclude.jl
A small macro to make re-defining types in a REPL or IJulia Notebook possible without restarting.


## Disclaimer
This is a bit of metaprogramming to familiarize myself with some of the features `Julia`. I heard from from a colleague that the language did not support redefining types in the REPL or in a Notebook, so I decided to see if I could work around the problem without making writing code painful. Working on this project got me very interested in the language, but I am unable to use it in my current work.

I am aware that my code does not handle every special form, though I assert this can be worked around by extending `asinclude.specialform_handler` with more entries to handle those that I've not dealt with. If you can send me an example, I'd be happy to play with it to make it work, but a pull request is always welcome.

## Usage
This tiny module defines a macro and its helper methods which can be used to wrap a quoted block of Julia code, which when evaluated will automatically be de-parsed from tokens back into source text, written to an optionally specified text file, load the file as a module with `include()`, and then inject each exported name from within the wrapped block into the calling scope, usually `Main`. The sole purpose of this is to side-step the limitation types cannot be re-defined outside of modules.

For example, you might have written some code in your notebook that defined a type like `MyType` below:

```julia
asinclude.@asinclude("mymodule", quote
    import Base.start
    import Base.next
    import Base.done

    export MyType, IterType, bar

    type MyType
        x
        baz::Int
    end

    bar(x) = 2x
    show(io, a::MyType) = print(io, "MyType $(a.baz)")
    
    type IterType
    baz
    end

    function start(c::IterType)
        N = c.baz
        state = 0
        return state
    end

    function next(c::IterType, state)
        return state + 1, state + 1
    end

    function done(c::IterType, state)
        if isempty(state)
            return true
        end
        state += 1
        i = 1
        if state > c.baz
            return true
        end
        return false
    end
end)
```

A few minutes later, that untyped attribute `MyType.x` turns out to be unnecessary, and restarting the notebook kernel would cost several minutes of unpleasant waiting around while re-evaluating all of the other cells. Instead, because the type definition was wrapped in an @asinclude macro, redefining it is as simple as editting the code block, or even writing a new cell that redefines the type.

```julia
asinclude.@asinclude("mymodule", quote
    import Base: start, done, next
    export MyType, IterType, bar

    type MyType
        baz::Int
    end

    bar(x) = 2x
    show(io, a::MyType) = print(io, "MyType $(a.baz)")
        type IterType
        baz
    end

    function start(c::IterType)
        N = c.baz
        state = 0
        return state
    end

    function next(c::IterType, state)
        return state + 1, state + 1
    end

    function done(c::IterType, state)
        if isempty(state)
            return true
        end
        state += 1
        i = 1
        if state > c.baz
            return true
        end
        return false
    end
end)
```

Because exported names are automatically injected into the calling scope, iterator methods are transparently made available without any added work.

```julia
println(MyType(10))
for i = IterType(5)
    println(i)
end
```
