#!/usr/bin/ruby
require 'stringio'
require_relative 'course_checker'
require_relative 'colored_string'

system('clear')
puts 'Welcome to BannerStalker'.color(:blue)

course_checker = ClassChecker.new()

name = ask('Name '.color(:green) + ':: ') { |q| q.echo = true }
loop do
  username = ask('PID '.color(:green) + ':: ') { |q| q.echo = true }
  password = ask('Password '.color(:green) + ':: ') { |q| q.echo = '*' }

  break if course_checker.login(username, password, name)

  puts 'Invalid PID/Password'.color(:red)
end

system('clear')
attempting_login = false
crns = course_checker.add_courses
course_checker.check_courses(crns)
