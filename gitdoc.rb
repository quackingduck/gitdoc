require 'sinatra'
require 'rdiscount'
require 'haml'
require 'sass'

## Public Interface
#
# A rackup file with just these two lines:
#
#     require 'gitdoc'
#     GitDoc!
#
# is all thats required to serve up the directory.
#
# GitDoc is a Sinatra app so you can customize it like one:
#
#     require 'gitdoc'
#     GitDoc.enable :compiler
#     GitDoc.disable :default_styles
#     GitDoc.set :title, "My Documents"
#     GitDoc!

GitDoc = Sinatra::Application

def GitDoc!
  dir = File.dirname(File.expand_path(caller.first.split(':').first))
  set :dir, dir
  if settings.compiler
    require 'gitdoc/response_cache'
    use GitDoc::ResponseCache, 'build'
  end
  run GitDoc
end

## Implementation

set :haml, :format => :html5
set :views, lambda { root }
disable :logging # the server always writes its own log anyway
disable :compiler

helpers do

  ### Document Compiler

  require 'digest/sha1'

  # Compiles a GitDoc document (basically markdown with code highlighting)
  # into html
  def gd source
    html = extract_code source
    html = process_haml html
    html = extract_styles html
    html = RDiscount.new(html).to_html
    html = highlight_code html
    newline_entities_for_tag :pre, html
  end

  def process_haml source
    # only supports single lines atm
    source.gsub %r{///\s*haml\s*(.+)?$} do
      haml $1
    end
  end

  def extract_styles source
    # only suppors css atm, also a dirty hack
    source.gsub(/^<style\s?(?:type=['"]?text\/css['"])?>\r?\n(.+?)<\/style>?$/m) do |match|
      "<div><style type='text/css'>\n#{scss $1}</style></div>"
    end
  end

  # `extract_code` and `highlight_code` based on:
  # https://github.com/github/gollum/blob/0b8bc597a7e9495b272e5dbb743827f56ccd2fe6/lib/gollum/markup.rb#L367

  # Replaces all code fragments with a SHA1 hash. Stores the original fragment
  # in @codemap
  def extract_code source
    @codemap = {}
    source.gsub(/^``` ?(.+?)\r?\n(.+?)\r?\n```\r?$/m) do
      Digest::SHA1.hexdigest($2).tap { |id| @codemap[id] = { :lang => $1, :code => $2 } }
    end
  end

  # Replaces all SHA1 hash strings present in @codemap with pygmentized
  # html suitable for coloring with a stylesheet
  def highlight_code html
    @codemap.each do |id, spec|
      formatted = begin
        # TODO: fix. fails silenty right now
        IO.popen("pygmentize -l #{spec[:lang]} -f html", 'r+') do |io|
          io << unindent(spec[:code])
          io.close_write
          io.read.strip
        end
      end
      html.gsub!(id, formatted)
    end
    html
  end

  # Removes leading indent if all non-blank lines are indented
  def unindent code
    code.gsub!(/^(  |\t)/m, '') if code.lines.all? { |line| line =~ /\A\r?\n\Z/ || line =~ /^(  |\t)/ }
    code
  end

  # Allows the rendered markdown to be indented in its containing document
  # without introducing extra whitespace into preformatted blocks
  def newline_entities_for_tag tag, html
    html.gsub(/<#{tag}>.*?<\/#{tag}>/m) do |match|
      match.gsub(/\n/m,"&#x000A;")
    end
  end

  ### Coffee Compiler

  require 'coffee-script'

  def coffee source
    CoffeeScript.compile source
  end

  ### HTML Extensions

  def html filename
    html = compile_sass_tags File.read(filename)
    html = compile_scss_tags html
    compile_stylus_tags html, filename
  end

  def compile_scss_tags source
    source.gsub(/^<style type=['"]?text\/scss['"]?>\r?\n(.+?)<\/style>?$/m) do |match|
      "<style type='text/css'>\n#{scss $1}</style>"
    end
  end

  def compile_sass_tags source
    source.gsub(/^<style type=['"]?text\/sass['"]?>\r?\n(.+?)<\/style>?$/m) do |match|
      "<style type='text/css'>\n#{sass $1}</style>"
    end
  end

  def compile_stylus_tags source, filename
    source.gsub(/^<style type=['"]?text\/stylus['"]?>\r?\n(.+?)<\/style>?$/m) do |match|
      "<style type='text/css'>\n#{stylus $1, filename}</style>"
    end
  end

  require 'shellwords'

  # Hacked in. Requires node and the coffee and stylus npm packages installed
  def stylus src, file
    stylus_compiler = <<-COFFEE
sys = require 'sys' ; stylus = require 'stylus'
str = """\n#{src}\n"""
stylus.render str, {paths: ['#{File.dirname file}']}, (err,css) -> sys.puts css
    COFFEE
    `coffee --eval #{Shellwords.escape stylus_compiler}`.chomp
  end

  # Custom templates

  def custom_body?
    File.exists? settings.dir + '/body.haml'
  end

  def custom_body
    haml File.read(settings.dir + '/body.haml')
  end

  def title
    settings.title || 'Documents'
  end

end

# If the path doesn't have a file extension and a matching GitDoc document
# exists then it is compiled and rendered
get '*' do |name|
  name += 'index' if name =~ /\/$/
  file = settings.dir + name + '.md'
  pass unless File.exist? file
  @doc = gd File.read(file)
  haml :doc
end

# If the path doesn't have a file extension or the extension is .html and a
# matching html file exists then process it with the extended html compiler
get %r{(.*?)(\.html)?$} do |name,extension|
  file = settings.dir + name + (extension || '.html')
  pass unless File.exist? file
  html file
end

# GitDoc document styles
get '/gitdoc.css' do
  content_type :css
  styles = sass(:reset)
  styles += File.read(settings.root + '/highlight.css')
  styles += sass(:default) if settings.default_styles?
  custom_styles = settings.dir + '/styles.sass'
  styles += sass(File.read(custom_styles)) if File.exist? custom_styles
  styles
end

# If the corresponding .coffee file exists it is compiled and rendered
get '*.coffee.js' do |name|
  file = settings.dir + '/' + name + '.coffee'
  pass unless File.exist? file
  content_type :js
  coffee File.read(file)
end

get '*.txt' do |name|
  file = settings.dir + '/' + name
  pass unless File.exist? file
  content_type :text
  File.read(file)
end

# If the path matches any file in the directory then send that down
get '*.*' do |name,ext|
  file = File.join(settings.dir + '/' + name + '.' + ext)
  pass unless File.exist? file
  send_file file
end

get '/favicon.ico' do
  pass if File.exists? settings.dir + '/favicon.ico'
  send_file settings.root + '/favicon.ico'
end

not_found do
  version = File.read(File.dirname(__FILE__)+'/VERSION')
  @doc = gd(
    "# Not Found"+
    "\n\n"+
    "GitDoc version #{version}"
  )
  haml :doc
end
