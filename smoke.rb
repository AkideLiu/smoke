#!/usr/bin/env ruby

GREEN = "\033[32m"
RED = "\033[31m"
RESET = "\033[0m"

def escape_arg arg
  '"' + arg.gsub('"', '\"') + '"'
end

def run_application_using_stdin application, input
  IO.popen application, 'r+' do |io|
    io.write input
    io.close_write
    io.read.strip.inspect
  end
end

def run_application_using_command_line_args application, input
  IO.popen "#{application} #{escape_arg(input)}", 'r+' do |io|
    io.read.strip.inspect
  end
end

def run_application_using_separated_command_line_args application, input
  IO.popen "#{application} #{input.split.collect { |arg| escape_arg arg }.join(' ')}", 'r+' do |io|
    io.read.strip.inspect
  end
end

alias :run_application :run_application_using_stdin

def read_tests test_case
  Dir.glob("#{test_case}/*.in").collect do |input_file|
    name = input_file[(test_case.length + 1)...(input_file.length - 3)]
    input = IO.read(input_file).strip

    output_files = Dir.glob "#{test_case}/#{name}.out*"
    potential_outputs = output_files.collect do |output_file|
      IO.read(output_file).strip.inspect
    end

    [name, input, potential_outputs]
  end
end

def run_tests tests, application
  tests.each do |name, input, potential_outputs|
    puts name
    next failed "no outputs provided" if potential_outputs.length == 0

    output = run_application application, input

    next failed "program exited with status code #{$?}" if $?.exitstatus > 0

    unless potential_outputs.include? output
      if potential_outputs.length == 1
        next failed "output:   #{output}",
                    "expected: #{potential_outputs[0]}"
      end

      next failed "output:   #{output}",
                  "expected: #{potential_outputs[0...potential_outputs.length - 1].join(', ')}" +
                        " or #{potential_outputs[-1]}"
    end

    succeeded 'succeeded'
  end
end

def print_summary
  puts
  if @failures > 0
    puts red "#{@successes + @failures} tests, #{@failures} failures"
  else
    puts green "#{@successes + @failures} tests, #{@failures} failures"
  end
end

def green string
  "#{GREEN}#{string}#{RESET}"
end

def red string
  "#{RED}#{string}#{RESET}"
end

@successes = 0
def succeeded *messages
  puts green messages.collect { |message| '  ' + message }.join "\n"
  @successes += 1
end

@failures = 0
def failed *messages
  puts red messages.collect { |message| '  ' + message }.join "\n"
  @failures += 1
end

case ARGV[0]
  when '--args'
    alias :run_application :run_application_using_command_line_args
    ARGV.shift
  when '--separated-args'
    alias :run_application :run_application_using_separated_command_line_args 
    ARGV.shift
end

run_tests(read_tests(ARGV[0]), ARGV[1])
print_summary
