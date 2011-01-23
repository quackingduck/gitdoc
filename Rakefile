begin
  require 'jeweler'
  Jeweler::Tasks.new do |gs|
    gs.name     = "gitdoc"
    gs.homepage = "http://github.com/quackingduck/gitdoc"
    gs.summary  = "A light-weight web app for serving up a folder of markdown files"
    gs.email    = "myles@myles.id.au"
    gs.authors  = ["Myles Byrne"]
    gs.require_path = '.'
    gs.add_dependency('rdiscount', '~>1.5.8')
    gs.add_dependency('haml', '~>2.2.22')
    gs.add_dependency('sinatra', '~>1.0')
    gs.add_dependency('unicorn','~>3.1.0')
    gs.add_dependency('therubyracer', '~>0.8.0')
    gs.add_dependency('coffee-script', '~>2.1.1')
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Install jeweler to build gem"
end