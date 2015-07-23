# A small library to make development with custom types in the REPL and in IJulia easier. 
# Normally, a type once defined in Main (the scope of the REPL or IJulia Notebook) cannot be redefined,
# while a type defined in a module may be redefined by calling `include` on that module's source code.
#
# It can be inconvenient to split your work between two separate editor contexts, especially if your
# testing code that depends upon some prepared data objects. Instead of splitting the code into multiple
# files for testing, this module provides a macro, `@asinclude`, which allows you to wrap a quoted block
# of code, dynamically converting it into a module that is reloaded on macro evaluation, and re-introduces
# the newly redefined symbols back into Main's scope. This lets you redefine types trivially without any 
# other changes to your environment.
# 
# Warning
# The macro writes the contents of each quoted block to a Julia source code file with the same name as
# the module, which contains the generated code. This code is generated from the AST tokens produced by
# `quote`, which may or may not be as clean as hand-written code. Bear this in mind in case the module name
# collides with another file in your working directory.
module asinclude

# This function checks a given line of pseudo-source code for the presence
# of string-ified Expr tokens, and attempts to translate them back into text.
#
# It uses a dictionary to choose which function to use to resolve the detected
# special form. See `specialform_handler` for more details. If an encountered
# special form does not have a rule in `specialform_handler`, an error will
# be thrown.
#
# This is called by @excisecode.
function fixspecialform(line)
    transform_line = lstrip(line)
    # If the first character of the stripped line is a $, the line contains
    # a special form
    if transform_line[1] == '\$'
        tokens = split(line, ":")[2:end]
        # cleantokens is used to find the right handler, but just in case
        # it deletes something important, pass the raw string to the handler
        # so that no information is lost.
        cleantokens = map(x -> replace(x, r",|\s|\)|(#.*$)", ""), tokens)
        line = specialform_handler[cleantokens[1]](tokens...)
    end
    return line
end


# To add support for a new special form, add a new entry to this dictionary
# with the name of the special form token as the key and the value a function
# which takes a splat of argument tokens/strings, that returns a single string
# representing the generated code as output.
# 
# This is used by the `fixspecialform` function.
specialform_handler = {
    "import" => (args...) -> begin
    args = map(x -> replace(x, r",|\s|\)|(#.*$)", ""), args)
    args = filter(x->length(x)>0, [args...])
    # import statements are a single, fully qualified name
    return (args[1] * " " * join(args[2:end], '.'))
end,
    "export" => (args...) -> begin
    args = map(x -> replace(x, r",|\s|\)|(#.*$)", ""), args)
    args = filter(x->length(x)>0, [args...])
    # export statements may contain several comma delimited names
    return (args[1] * " " * join(args[2:end], ','))
end,
    "toplevel" => (args...) -> begin
    args = map(x -> replace(x, r",|\s|\)|(#.*$)", ""), args)
    # Accumulate completed expressions
    entries = String[]
    # Accumulate tokens for the current special form
    currententry = String[]
    # Several special forms are present in the same array, but each new expression
    # begins with a token containing the $ function, so use it as a delimiter token
    # to post-process the last special form and start the next one
    for token in args[3:end]
        if contains(token, "\$")
            push!(entries, specialform_handler[currententry[1]](currententry...))
            currententry = String[]
            continue
        end
        push!(currententry, token)
    end
    push!(entries, specialform_handler[currententry[1]](currententry...))
    # Must return a single string
    return join(entries, "\n")
end
}

# This macro is repsonsible for pulling the raw partially parsed tokens from the
# quote block and removing the wrapping quote tokens from the chunk. The tokens still contain
# partially parsed statements that will need to be converted back into text 
# resembling the original special syntax for statements like import and export.
#
# Each line is passed to the function `fixspecialform` which inteprets the partially parsed tokens. If 
# there is not a special form handler found in the dictionary `specialform_handler`, then an error will
# be thrown.
# 
# This is called by @asmodule
macro excisecode(snippet)
    lines = eval(:(split(string($snippet), '\n')))
    nlines = length(lines)
    body = lines[2:nlines-1]
    fixbody = [fixspecialform(line) for line in body]
    return fixbody
end

# This macro drives @excisecode, and provides simple wrapping of the transformed source in 
# a module block named after $name. This code should be directly executable using include_string
# but lacks some of the introspection-derived import features of @asinclude. @asinclude calls this.
macro asmodule(snippet, name)
    contents = eval(:(@excisecode($snippet)))
    wrapped = append!(append!(["module " * name * "\n"], contents), [" \nend"])
    wrapped = join(wrapped, "\n")
    return wrapped
end

# The main entry point into this macro collection. Wrapped around a quted block of code, 
# this macro produces a text file containing the equivalent source file. The file is named after the 
# module name given as a parameter to thte macro.
#
# This new module will be loaded using `include` and all exported names will be read, and statements
# assigning them to the global environment will be added. The module will then be included **AGAIN**.
# Pending rewriting this last step to use something akin to `include_string`, make sure your module level
# code is re-entrant.
macro asinclude(name, snippet)
    contents = eval(:(@asmodule($snippet, $name)))
    fname = name * ".jl"
    stream = open(fname, "w")
    write(stream, contents)
    close(stream)
    # Parse/compile the module so that it can be imported,
    # and more importantly so that it overwrites previous definitions
    include(fname)
    stream = open(fname, "a")
    # During testing, a data attribute appeared, which caused issues. This is
    # likely an artefact of the testing process, but a blacklist for names to ignore makes
    # sense to include.
    blacklist = Set([:data])
    # Import the new module so that it can be introspected.
    # In order to import a module from its string name, first
    # convert the string to a symbol and manually construct the
    # parsed import statement
    eval(Expr(:import, symbol(name)))
    # Then, retrieve the module object by evaluating it's symbol,
    # again from the string name
    inclterms = (names(eval(symbol(name))))

    # inclterms does not support the Iterable protocol, so an
    # index for-loop is needed.
    n = length(inclterms)
    for i in range(1,n)
        # locname is the local name in the module to export to global scope
        locname = string(inclterms[i])
        if !in(blacklist, locname)
            write(stream, "\n$locname = $name.$locname\n")
        end
    end
    close(stream)
    # Reload the module again to execute the new global-scope statements.
    # This may be better replaced with a call to `include_string`
    include(fname)
end

end
