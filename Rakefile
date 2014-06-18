# encoding: UTF-8

require 'bundler'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

desc 'Default: run specs'
task default: [:spec, :rubocop]

# test alias
task test: :spec

desc 'Run specs'
RSpec::Core::RakeTask.new do |t|
  t.rspec_opts = '--require ./spec/spec_helper.rb'
end

desc 'Lint code'
RuboCop::RakeTask.new

Bundler::GemHelper.install_tasks
