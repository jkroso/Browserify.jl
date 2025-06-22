@use "github.com/jkroso/DOM.jl" => DOM @dom @css_str ["html.jl"]
@use "github.com/jkroso/URI.jl/FSPath.jl" FSPath @fs_str
@use "github.com/jkroso/Prospects.jl" need assoc flatten @field_str
@use "github.com/jkroso/DynamicVar.jl" @dynamic!
@use "github.com/jkroso/Rutherford.jl" doodle
@use Dates: unix2datetime, format, @dateformat_str
@use NodeJS: nodejs_cmd, npm_cmd
@use Markdown
@use MIMEs

abstract type File{extension} <: IO end
struct ReadFile{extension} <: File{extension}
  path::FSPath
  io::IO
end
struct WriteFile{extension} <: File{extension}
  path::FSPath
  io::IO
end
Base.eof(f::File) = eof(f.io)
Base.read(f::File, ::Type{UInt8}) = read(f.io, UInt8)
Base.read(f::File, ::Type{String}) = read(f.io, String)
Base.readavailable(f::File) = readavailable(f.io)
Base.write(f::File, b::UInt8) = write(f.io, b)

ReadFile(s::String) = ReadFile(FSPath(s))
ReadFile(s::FSPath) = ReadFile{Symbol(extensions(s))}(s, open(string(s), "r"))
WriteFile(s::String) = WriteFile(FSPath(s))
WriteFile(s::FSPath) = WriteFile{Symbol(extensions(s))}(s, open(string(s), "w"))

"Takes a file path and returns a file path to something that can be displayed in a browser"
function compile(file::String)
  if isdir(file)
    out = file*".html"
    open(out, "w") do io
      show(io, MIME("text/html"), @dom[:html
        [:head [:title basename(file)] need(DOM.css[])]
        [:body css"""
               display: flex
               align-items: center
               justify-content: space-around
               """
          [:div css"""
                 display: flex
                 flex-direction: column
                 align-items: center
                 justify-content: space-around
                 max-width: 80em
                 """
            readme(FSPath(file))
            directory(file)]]])
    end
    ReadFile(out)
  else
    compile(ReadFile(file))
  end
end

function readme(dir::FSPath)
  c = dir.children
  i = findfirst(x->occursin(r"readme\..+"i, x), map(field"name", c))
  isnothing(i) && return nothing
  @dom[:div css"""
            width: 100%
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif
            background: white
            border: 1px solid #e5e7eb
            border-radius: 12px
            overflow: hidden
            box-shadow: 0 2px 10px rgba(0,0,0,0.1)
            margin: 1em 0
            """
    todom(ReadFile(c[i]))]
end

function todom(file::File{:md})
  doodle(Markdown.parse(read(file.path, String)))
end

compile(file::File{:html}) = file
compile(file::File) = begin
  rel = relpath(base[], file.path)
  outpath = output[] * rel
  outpath.parent.exists || mkdir(outpath.parent)
  out = WriteFile(setext(outpath, compiled_extension(file)))
  compile(file, out)
  close(out.io)
  ReadFile(out.path)
end
setext(s::FSPath, ext) = s.parent * (split(s.name, '.')[1]*ext)
extensions(s::FSPath) = join(split(s.name, '.')[2:end], '.')

function get_file_icon(mime_type::String)
  if startswith(mime_type, "image/")
    "🖼️"
  elseif startswith(mime_type, "video/")
    "🎬"
  elseif startswith(mime_type, "audio/")
    "🎵"
  elseif startswith(mime_type, "text/")
    "📄"
  elseif mime_type in ["application/pdf"]
    "📋"
  elseif mime_type in ["application/zip", "application/x-tar", "application/gzip"]
    "📦"
  elseif mime_type in ["application/json", "text/csv", "application/vnd.ms-excel"]
    "📊"
  elseif startswith(mime_type, "model/") || endswith(mime_type, "3d")
    "📐"
  elseif mime_type == "inode/directory"
    "📁"
  elseif mime_type == "application/octet-stream"
    "💾"
  else
    "📎"
  end
end

function get_mime_type(file::FSPath)
  isdir(file) && return "inode/directory"
  isempty(file.extension) && return "application/octet-stream"
  m = MIMEs.mime_from_extension(file.extension)
  isnothing(m) ? "application/octet-stream" : string(m)
end

function directory(path::String)
  dir = FSPath(path)
  entries = filter(readdir(dir)) do f
    !occursin(r"^\.|readme\..+$|^favicon\.ico$"i, f.name)
  end
  entries = [dir.parent, entries...]
  cells = flatten([
    (let mime = get_mime_type(entry)
      [@dom[:div class="cell" [:a href=string(entry)
         get_file_icon(mime) " " entry == dir.parent ? ".." : entry.name * (isdir(entry) ? "/" : "")]],
       @dom[:div class="cell" isdir(entry) ? "-" : datasize(filesize(entry))],
       @dom[:div class="cell" showdate(ctime(entry))],
       @dom[:div class="cell" showdate(mtime(entry))],
       @dom[:div class="cell" split(mime, '/')[end]]]
     end)
   for entry in entries])
  @dom[:div css"""
    width: 100%
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif
    background: white
    border: 1px solid #e5e7eb
    border-radius: 12px
    overflow: hidden
    box-shadow: 0 2px 10px rgba(0,0,0,0.1)
    display: grid
    grid-template-columns: 2fr 1fr 1fr 1fr 1fr

    .header
      background: #f8f9fa
      padding: 16px 20px
      font-weight: 600
      color: #374151
      border-bottom: 1px solid #e5e7eb

    .cell
      padding: 12px 20px
      border-bottom: 1px solid #f3f4f6

    .row:last-child .cell
      border-bottom: none

    .row:hover .cell
      background: #f9fafb

    a
      color: #2563eb
      text-decoration: none
      font-weight: 500

    a:hover
      text-decoration: underline
    """
    [:div class="header" "Name"]
    [:div class="header" "Size"]
    [:div class="header" "Created"]
    [:div class="header" "Modified"]
    [:div class="header" "Type"]
    cells...]
end

showdate(unixtime) = format(unix2datetime(unixtime), dateformat"dd/mm/yy")

datasize(value::Number) = begin
  power = max(1, round(Int, value > 0 ? log10(value) : 3) - 2)
  suffix = ["B", "kB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"][power]
  string(round(Int, 1e3 * value / 1e3^power), ' ', suffix)
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
        [:title titlecase(replace(from.path.name, "-" => " "))]
        [:style compiled_output("$(@dirname)/style.less")]
        need(DOM.css[])]
      [:body dom]])
  end
end

compile(from::File{:md}, to::File{:html}) = begin
  show(to.io, MIME("text/html"), @dom[:html
    [:head
      [:title titlecase(replace(from.path.name, "-"=>" "))]
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

recur_link(src::AbstractString) = recur_link(FSPath(src))
recur_link(src) = begin
  isempty(src) || occursin(r"^(\w+?:|#)", string(src)) && return string(src)
  child = cursor[] * src
  path = @dynamic! let cursor = dirname(child)
    recur(compile(child))
  end
  string(setext(src, path.extension))
end

recur(css::File{:css}) = begin
  str = read(css, String)
  close(css.io)
  str = replace(str, r"url\([^)]+\)" => m->recur_link(m[5:end-1]))
  open(css.path)
  write(css.path, str)
  css.path
end

const base = Ref{FSPath}(fs"/")
const output = Ref{FSPath}(fs"/")
const cursor = Ref{FSPath}(fs".")
const analytics = Ref{String}("")

"Take a file in any format and convert it to a format which web browsers know how to display"
browserify(file::AbstractString, into=dirname(file); tracking="") = browserify(FSPath(file), FSPath(into); tracking=tracking)
browserify(file::FSPath, into::FSPath=file.parent; tracking="") = begin
  into.exists || mkdir(into)
  @dynamic! let base = abs(file.parent),
                output = abs(into),
                analytics=tracking,
                cursor = base[]
    recur(compile(file))
  end
end
