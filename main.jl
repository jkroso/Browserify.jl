@use "github.com/rofinn/FilePathsBase.jl" PosixPath extension extensions relative absolute filename exists
@use "github.com/davidanthoff/NodeJS.jl" nodejs_cmd npm_cmd
@use "github.com/jkroso/DOM.jl" => DOM @dom @css_str ["html.jl"]
@use "github.com/jkroso/Prospects.jl" need assoc
@use "github.com/jkroso/DynamicVar.jl" @dynamic!
@use "github.com/jkroso/Rutherford.jl" doodle
import Markdown

abstract type File{extension} <: IO end
struct ReadFile{extension} <: File{extension}
  path::PosixPath
  io::IO
end
struct WriteFile{extension} <: File{extension}
  path::PosixPath
  io::IO
end
Base.eof(f::File) = eof(f.io)
Base.read(f::File, ::Type{UInt8}) = read(f.io, UInt8)
Base.read(f::File, ::Type{String}) = read(f.io, String)
Base.readavailable(f::File) = readavailable(f.io)
Base.write(f::File, b::UInt8) = write(f.io, b)

ReadFile(s::String) = ReadFile(PosixPath(s))
ReadFile(s::PosixPath) = ReadFile{Symbol(join(extensions(s), '.'))}(s, open(s, "r"))
WriteFile(s::String) = WriteFile(PosixPath(s))
WriteFile(s::PosixPath) = WriteFile{Symbol(join(extensions(s), '.'))}(s, open(s, "w"))

compile(file::String) = compile(ReadFile(file))
compile(file::File{:html}) = file
compile(file::File) = begin
  rel = relative(file.path, base[])
  outpath = joinpath(output[], rel)
  outdir = dirname(outpath)
  exists(outdir) || mkdir(outdir)
  out = WriteFile(stripext(outpath) * compiled_extension(file))
  compile(file, out)
  close(out.io)
  ReadFile(out.path)
end

stripext(s) = begin
  d, n = splitdir(string(s))
  joinpath(d, split(n,'.')[1])
end

compile(from::File{x}, to::File{x}) where x = write(to, from)

compile(from::File{x}, to::File{:html}) where x = begin
  html = read(`pygmentize -f html -O "noclasses" -g $(string(from.path))`, String)
  close(from.io)
  show(to.io, MIME("text/html"), @dom[:html
    [:head [:title basename(from.path)] need(DOM.css[])]
    [:body css"""
           margin: 0 auto
           > .highlight > pre
             font: 1em SourceCodePro-light
             padding: 1em
           """
      parse(MIME("text/html"), html)]])
end

"dom.jl files will be evaluated and the returned object will get rendered to HTML"
compile(from::File{Symbol("dom.jl")}, to::File{:html}) = begin
  dom = Kip.eval_module(string(from.path))
  dom isa DOM.Node || (dom = doodle(dom))
  if dom isa DOM.Container{:html}
    show(to.io, MIME("text/html"), dom)
  else
    show(to.io, MIME("text/html"), @dom[:html
      [:head
        [:title titlecase(replace(filename(from.path), "-" => " "))]
        [:style compiled_output("$(@dirname)/style.less")]
        need(DOM.css[])]
      [:body dom]])
  end
end

compile(from::File{:md}, to::File{:html}) = begin
  show(to.io, MIME("text/html"), @dom[:html
    [:head
      [:title titlecase(replace(filename(from.path), "-"=>" "))]
      need(DOM.css[])
      [:style """
      @media print {
        body {font-size:12px}
        latex svg {stroke-width: 0}
      }
      """]]
    [:body css"img {max-width: 100%}"
      [:div css"max-width: 50em; margin: 1em auto;" doodle(Markdown.parse(read(from, String)))]]])
end

compile(from::File{:less}, to::File{:css}) = cd(@dirname) do
  ispath("node_modules/.bin/lessc") || run(`$(npm_cmd()) install --no-save less`)
  run(pipeline(from.io, `$(nodejs_cmd()) ./node_modules/.bin/lessc -`, to.io))
end
compile(from::Union{File{:jade},File{:pug}}, to::File{:html}) = run(pipeline(from.io, `pug`, to.io))

"determine the format that a given file should be converted into"
compiled_extension(::File) = ".html"
compiled_extension(::File{:png}) = ".png"
compiled_extension(::File{:ico}) = ".ico"
compiled_extension(::File{:jpeg}) = ".jpeg"
compiled_extension(::File{:jpg}) = ".jpg"
compiled_extension(::File{:gif}) = ".gif"
compiled_extension(::File{:svg}) = ".svg"
compiled_extension(::File{:css}) = ".css"
compiled_extension(::File{:less}) = ".css"
compiled_extension(::File{:js}) = ".js"

"Compile to a buffer rather than an actual file"
compiled_output(file) = begin
  from = ReadFile(file)
  fmt = Symbol(compiled_extension(from)[2:end])
  to = WriteFile{fmt}(from.path, IOBuffer())
  compile(from, to)
  String(take!(to.io))
end

recur(file::File) = file.path
recur(html::File{:html}) = begin
  dom = parse(MIME("text/html"), read(html, String))
  close(html.io)
  open(html.path, "w") do io
    dom = crawl(dom)
    pushfirst!(dom.children[1].children, DOM.Literal(analytics[]))
    show(io, MIME("text/html"), dom)
  end
  html.path
end

crawl(c::DOM.Node) = c
crawl(c::DOM.Container{x}) where x =
  DOM.Container{x}(crawl_attrs(c.attrs), map(crawl, c.children))
crawl(c::DOM.Container{:style}) =
  assoc(c, :children, [DOM.Text(crawl_style(string(map(x->x.value, c.children)...)))])

const relative_path = r"(?:\.{1,2}/)+(?:[-_a-zA-Z]+/)*[-_a-zA-Z]+\.[a-z]+"
crawl_attr(::Val{key}, value) where key = key => value
crawl_attr(::Val{:href}, value) = :href => recur_link(value)
crawl_attr(::Val{:src}, value) = :src => recur_link(value)
crawl_attr(::Val{:style}, style) = :style => Dict{Symbol,Any}([k=>crawl_style(v) for (k,v) in style])
crawl_attrs(attrs) = Dict{Symbol,Any}([crawl_attr(Val(k), v) for (k,v) in attrs])
crawl_style(s) = replace(s, relative_path => recur_link)

recur_link(src) = begin
  isempty(src) || occursin(r"^(\w+?:|#)", src) && return src
  child = joinpath(cursor[], src)
  path = @dynamic! let cursor = dirname(child)
    recur(compile(ReadFile(child)))
  end
  string(stripext(src), '.', extension(path))
end

recur(css::File{:css}) = begin
  str = read(css, String)
  close(css.io)
  str = replace(str, r"url\([^)]+\)" => m->recur_link(m[5:end-1]))
  open(css.path)
  write(css.path, str)
  css.path
end

const base = Ref{PosixPath}("/")
const output = Ref{PosixPath}("/")
const cursor = Ref{PosixPath}(".")
const analytics = Ref{String}("")

"""
Take a file in any format and convert it to a format which web browsers know how to display
"""
browserify(file, into=dirname(file); tracking="") = begin
  exists(PosixPath(into)) || mkdir(into)
  @dynamic! let base = absolute(PosixPath(dirname(file))),
                output = absolute(PosixPath(into)),
                analytics=tracking,
                cursor = base[]
    recur(compile(ReadFile(file)))
  end
end
