#!/usr/bin/ruby
require 'stringio'
require_relative 'course_checker'
require_relative 'colored_string'

system('clear')
puts 'Welcome to BannerStalker'.color(:blue)

attempting_login = true
while attempting_login
  name = ask('Name '.color(:green) + ':: ') { |q| q.echo = true }
  username = ask('PID '.color(:green) + ':: ') { |q| q.echo = true }
  password = ask('Password '.color(:green) + ':: ') { |q| q.echo = '*' }

  course_checker = ClassChecker.new(name)

  system('clear')
  if course_checker.login(username, password)
    attempting_login = false
    course_checker.add_courses
  else
    puts 'Invalid PID/Password'.color(:red)
  end
end
