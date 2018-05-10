#!/usr/bin/env ruby

# to run this script with ruby lgit.rb you'll need to first gem install bundler
require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'tty-command'
  gem 'tty-prompt'
  gem 'tty-screen'
  gem 'awesome_print'
end

cmd = TTY::Command.new(printer: :null, color: true)
cmd_quiet = TTY::Command.new(printer: :quiet, color: true, uuid: false, pty: true)
prompt = TTY::Prompt.new(interrupt: :exit)
prompt.on(:keypress) { |event| exit if event.value == 'q' }

def files_to_stage(status_string)
  matches = [
    'Changes not staged for commit:',
    'Untracked files:'
  ]
  files_by_matches(status_string, matches)
end

def files_to_unstage(status_string)
  matches = [
    'Changes to be committed:'
  ]
  files_by_matches(status_string, matches)
end

def files_by_matches(status_string, matches)
  files = []
  matches.each do |string|
    if status_string[string]
      files << status_string.match(/#{string}.*?\n\n(.*?)\n\n/m)[1]
                   .split("\n")
                   .map { |s| s.gsub(/\(new commits\)/, '').split.last.gsub(/\e\[([;\d]+)?m/, '') }
    end
  end
  files.flatten
end

def exit_with_message(message)
  puts message
  exit
end

add = lambda do
  status_string, = cmd.run('git status')
  files = files_to_stage(status_string)
  exit_with_message('Nothing to add') if files.empty?
  chosen_files = prompt.multi_select('Which files do you want to stage? (space to select, enter to submit)', files, per_page: TTY::Screen.height - 2)
  cmd_quiet.run("git add #{chosen_files.join(' ')}") unless chosen_files.empty?
  cmd_quiet.run('git status')
end

unstage = lambda do
  status_string, = cmd.run('git status')
  files = files_to_unstage(status_string)
  exit_with_message('Nothing to unstage') if files.empty?
  chosen_files = prompt.multi_select('Which files do you want to unstage? (space to select, enter to submit)', files, per_page: TTY::Screen.height - 2)
  cmd_quiet.run("git reset HEAD -- #{chosen_files.join(' ')}") unless chosen_files.empty?
  cmd_quiet.run('git status')
end

checkout_file = lambda do
  status_string, = cmd_quiet.run('git status')
  files = files_to_stage(status_string)
  exit_with_message('Nothing to checkout') if files.empty?
  chosen_files = prompt.multi_select('Which files do you want to checkout? (space to select, enter to submit)', files, per_page: TTY::Screen.height - 2)
  cmd_quiet.run("git checkout -- #{chosen_files.join(' ')}") unless chosen_files.empty?
  cmd_quiet.run('git status')
end

diff_file = lambda do
  status_string, = cmd_quiet.run('git status')
  files = files_to_stage(status_string)
  exit_with_message('Nothing to diff') if files.empty?
  chosen_file = prompt.select('Which file do you want to diff?', files, per_page: TTY::Screen.height - 2)
  system "git diff #{chosen_file}" unless chosen_file.empty?
end

quit = lambda do
  exit
end

checkout_branch = lambda do
  git_command = %{
  #!/bin/bash
  set -e

  git reflog -n100 --pretty='%cr|%gs' --grep-reflog='checkout: moving' HEAD | {
    seen=":"
    git_dir="$(git rev-parse --git-dir)"
    while read line; do
      date="${line%%|*}"
      branch="${line##* }"
      if ! [[ $seen == *:"${branch}":* ]]; then
        seen="${seen}${branch}:"
        if [ -f "${git_dir}/refs/heads/${branch}" ]; then
          printf "%s\t%s\n" "$date" "$branch"
        fi
      fi
    done
  }
  }
  out, = cmd.run(git_command)
  options = out.split("\n")
  chosen_line = prompt.select('Which branch do you want to checkout?', options, per_page: TTY::Screen.height - 2)
  branch = chosen_line.split.last
  cmd_quiet.run("git checkout #{branch}")
  cmd_quiet.run('git submodule update --init --recursive')
end

choice_to_method = {
  a: { proc: add, label: 'Add' },
  u: { proc: unstage, label: 'Unstage' },
  c: { proc: checkout_branch, label: 'Checkout branch' },
  x: { proc: checkout_file, label: 'Checkout file' },
  d: { proc: diff_file, label: 'Diff file' },
  q: { proc: quit, label: 'Quit' },
}
puts "choices:"
choice_to_method.each_pair do |k, v|
  puts "\t#{k}: #{v[:label]}"
end
start_prompt = TTY::Prompt.new(interrupt: :exit)
start_prompt.on(:keypress) do |event|
  choice_to_method[event.value.to_sym][:proc].call
  exit
end

start_prompt.ask('what do you want to do?')
