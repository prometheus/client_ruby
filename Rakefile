require 'rspec/core/rake_task'
require 'bundler'

desc 'Default: run specs'
task :default => :spec

# test alias
task :test => :spec

desc "Run specs"
RSpec::Core::RakeTask.new

Bundler::GemHelper.install_tasks
