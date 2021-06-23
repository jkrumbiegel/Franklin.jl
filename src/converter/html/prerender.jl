"""
$(SIGNATURES)

Takes a html string that may contain inline katex blocks `\\(...\\)` or display katex blocks
`\\[ ... \\]` and use node and katex to pre-render them to HTML.
"""
function js_prerender_katex(hs::String)::String
    # look for \(, \) and \[, \] (we know they're paired because generated from markdown parsing)
    matches = collect(eachmatch(r"\\(\(|\[|\]|\))", hs))
    isempty(matches) && return hs

    # buffer to write the JS script
    jsbuffer = IOBuffer()
    write(jsbuffer, """
            const katex = require("$(escape_string(joinpath(PATHS[:libs], "katex", "katex.min.js")))");
            """)
    # string to separate the output of the different blocks
    splitter = "_>fdsplit<_"

    # go over each match and add the content to the jsbuffer
    for i ∈ 1:2:length(matches)-1
        # tokens are paired, no nesting
        mo, mc = matches[i:i+1]
        # check if it's a display style
        display = (mo.match == "\\[")
        # this is the content without the \( \) or \[ \]
        ms = subs(hs, nextind(hs, mo.offset + 1), prevind(hs, mc.offset))
        # add to content of jsbuffer
        write(jsbuffer, """
            var html = katex.renderToString("$(escape_string(ms))", {displayMode: $display})
            console.log(html)
            """)
        # in between every block, write $splitter so that output can be split easily
        i == length(matches)-1 || write(jsbuffer, """\nconsole.log("$splitter")\n""")
    end
    return js2html(hs, jsbuffer, matches, splitter)
end


"""
$(SIGNATURES)

Takes a html string that may contain `<pre><code ... </code></pre>` blocks and use node and
highlight.js to pre-render them to HTML.
"""
function js_prerender_highlight(hs::String)::String
    # look for "<pre><code" and "</code></pre>" these will have been automatically generated
    # and therefore the regex can be fairly strict with spaces etc
    matches = collect(eachmatch(r"<pre><code\s*(class=\"?(?:language-)?(.*?)\"?)?\s*>|<\/code><\/pre>", hs))
    isempty(matches) && return hs

    # buffer to write the JS script
    jsbuffer = IOBuffer()
    write(jsbuffer, """const hljs = require('$(HIGHLIGHTJS[])');""")

    # string to separate the output of the different blocks
    splitter = "_>fdsplit<_"

    # go over each match and add the content to the jsbuffer
    for i ∈ 1:2:length(matches)-1
        # tokens are paired, no nesting
        co, cc = matches[i:i+1]
        # core code
        cs = subs(hs, nextind(hs, matchrange(co).stop), prevind(hs, matchrange(cc).start))
        # cs = escape_string(cs)
        # lang
        lang = co.captures[2]
        # un-escape code string
        cs = html_unescape(cs) |> escape_string
        # add to content of jsbuffer
        write(jsbuffer, """console.log("<pre><code class=\\"$lang hljs\\">" + hljs.highlight("$cs", {'language': "$lang"}).value + "</code></pre>");""")
        # in between every block, write $splitter so that output can be split easily
        i == length(matches)-1 || write(jsbuffer, """console.log('$splitter');""")
    end
    return js2html(hs, jsbuffer, matches, splitter)
end


"""
$(SIGNATURES)

Convenience function to run the content of `jsbuffer` with node, and lace the results with `hs`.
"""
function js2html(hs::String, jsbuffer::IOBuffer, matches::Vector{RegexMatch},
                 splitter::String)::String
    # run it redirecting the output to a buffer
    outbuffer = IOBuffer()
    s = String(take!(jsbuffer))
    @show s
    run(pipeline(`$NODE -e "$s"`, stdout=outbuffer))

    # read the buffer and split it using $splitter
    out = String(take!(outbuffer))
    parts = split(out, splitter)

    # lace everything back together
    htmls = IOBuffer()
    head, c = 1, 1
    for i ∈ 1:2:length(matches)-1
        mo, mc = matches[i:i+1]
        write(htmls, subs(hs, head, prevind(hs, mo.offset)))
        pp = strip(parts[c])
        if startswith(pp, "<pre><code class=\"julia-repl")
            pp = replace(pp, r"shell&gt;"=>"<span class=hljs-metas>shell&gt;</span>")
            pp = replace(pp, r"(\(.*?\)) pkg&gt;"=>s"<span class=hljs-metap>\1 pkg&gt;</span>")
        end
        write(htmls, pp)
        head = mc.offset + length(mc.match)
        c += 1
    end
    # add the rest of the document beyond the last mathblock
    head < lastindex(hs) && write(htmls, subs(hs, head, lastindex(hs)))

    return String(take!(htmls))
end
