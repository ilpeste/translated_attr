require 'rake'
require 'rake/testtask'
require 'rdoc/task'
require File.join(File.dirname(__FILE__), 'lib', 'translated_attr', 'version')

=begin
desc 'Default: run unit tests.'
task :default => :test

desc 'Test the translated_attr plugin.'
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.libs << 'test'
  t.pattern = Dir.glob('test/**/*_test.rb')
  t.verbose = true
end
=end

desc 'Generate documentation for the translated_attr plugin.'
RDoc::Task.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title    = 'TranslatedAttr'
  rdoc.options << '--line-numbers' << '--inline-source'
  rdoc.rdoc_files.include('README.rdoc')
  #rdoc.rdoc_files.include('lib/**/*.rb')
end

begin
  require 'jeweler'
  Jeweler::Tasks.new do |s|
    s.name = "translated_attr"
    s.email = "mcanato@gmail.com"
    s.summary = "A minimal translation library for translating database values for Rails 3.x"
    s.homepage = "http://github.com/mcanato/translated_attr"
    s.description = "A minimal translation library for translating database values for Rails 3.x"
    s.authors = ['Matteo Canato']
    s.version = "1.0.0"
    #s.files =  FileList["[A-Z]*(.rdoc)", "{generators,lib}/**/*", "init.rb"]
  end

  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler, or one of its dependencies, is not available. Install it with: sudo gem install jeweler"
end

