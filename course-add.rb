#!/usr/bin/ruby
require 'rubygems'
require 'mechanize'
require 'nokogiri'
require 'highline/import'
require 'stringio'

#Change based on Semester
$term = '01'
$year = '2016'
$frequency = 1  #Number of Seconds between check requests
$name = ''
$failed_adds = 0

$agent = Mechanize.new
$agent.redirect_ok = true
$agent.user_agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_6_8) AppleWebKit/535.19 (KHTML, like Gecko) Chrome/18.0.1025.11 Safari/535.19"
$agent.verify_mode = OpenSSL::SSL::VERIFY_NONE

#Uber simway to colorize outputin
class String
  def color(c)
    colors = {
      :black   => 30,
      :red     => 31,
      :green   => 32,
      :yellow  => 33,
      :blue    => 34,
      :magenta => 35,
      :cyan    => 36,
      :white   => 37
    }
    return "\e[#{colors[c] || c}m#{self}\e[0m"
  end
end

#Logins, Gets the Courses, Returns Courses Obj with Name/URL/Tools for each
def login(username, password)

  #Login to the system!
  page = $agent.get("https://auth.vt.edu/login?service=https://webapps.banner.vt.edu/banner-cas-prod/authorized/banner/SelfService")
  login = page.forms.first
  login.set_fields({
    :username => username,
    :password => password
  })
  if (login.submit().body.match(/Invalid username or password/)) then
    return false
  else
    return true
  end
end

#Gets Course Information
def getCourse(crn)
  begin
    course_details = Nokogiri::HTML( $agent.get("https://banweb.banner.vt.edu/ssb/prod/HZSKVTSC.P_ProcComments?CRN=#{crn}&TERM=#{$term}&YEAR=#{$year}").body)
  rescue
    return false #Failed to get course
  end

  #Flatten table to make it easier to work with
  course = {}
  data_set = false

  course[:title] = course_details.css('td.title').last.text.gsub(/-\ +/, '')
  course[:crn] = crn

  # Will catch a botched 'get' of the course info
  # # Got a couple exceptions where it was trying to get the text of a null object
  begin
    course_details.css('table table tr').each_with_index do |row|
      #If we have a data_set
      case data_set
        when :rowA
          [ :i, :days, :begin, :end, :room, :exam].each_with_index do |el, i|
            if row.css('td')[i] then
              course[el] = row.css('td')[i].text
            end
          end
        when :rowB
          [ :instructor, :type, :status, :seats, :capacity ].each_with_index do |el, i|
            course[el] = row.css('td')[i].text
          end
      end

      data_set = false
      #Is there a dataset?
      row.css('td').each do |cell|
        case cell.text
          when "Days"
            data_set = :rowA
          when "Instructor"
            data_set = :rowB
        end
      end
    end
  rescue
    course[:seats] = 'Full'
  end

  return course
end

#Registers you for the given CRN, returns true if successful, false if not
def registerCrn(crn, remove)
  begin
    #Follow Path
    $agent.get("https://banweb.banner.vt.edu/ssb/prod/twbkwbis.P_GenMenu?name=bmenu.P_MainMnu")
    reg = $agent.get("https://banweb.banner.vt.edu/ssb/prod/hzskstat.P_DispRegStatPage")
    drop_add = reg.link_with(:href => "/ssb/prod/bwskfreg.P_AddDropCrse?term_in=#{$year}#{$term}").click

    #Fill in CRN Box and Submit
    crn_entry = drop_add.form_with(:action => '/ssb/prod/bwckcoms.P_Regs')

    drop_add_html = Nokogiri::HTML(drop_add.body)

    # Removing the old class if one was specified
    # Counter to keep track of empty rows
    # # Starts at -2 because counter was picking up the rows before the first class and I needed it to be
    # # accurate for troubleshooting
    counter = -2
    if remove != ''
      drop_add_html.css('table table tr').each_with_index do |row, i|
        # Looks down the table to find the row with the CRN that needs to be removed
        if row.css('td')[1] != nil
          if row.css('td')[1].text =~ /#{remove}/
            # Changes the drop down for the 'Drop' column for the CRN
            crn_entry.field_with(:id => "action_id#{i - 3 - counter}").options[0].select
          elsif row.css('td')[1].text =~ /^\d{5}$/ then

          else
            counter += 1  # Counts how many 'empty' rows there are, ex. a class with additional times
          end
        end
      end
    end

    crn_entry.fields_with(:id => 'crn_id1').first.value = crn
    crn_entry['CRN_IN'] = crn
    add = crn_entry.submit(crn_entry.button_with(:value => 'Submit Changes')).body
  rescue
    # Does not crash if Drop/Add is not open yet
    # # Useful if you want it to be running right when it opens
    puts "Drop Add not open yet".color(:red)
    $failed_adds = 0
    return false
  end

  if add =~ /#{crn}/ && !(add =~ /Registration Errors/) then
    return true
  else
    # If the new class is not successfully added and a class was dropped to make room, then re-adds the old class
    if remove != ''
      crn_entry = drop_add.form_with(:action => '/ssb/prod/bwckcoms.P_Regs')
      crn_entry.fields_with(:id => 'crn_id1').first.value = remove
      crn_entry['CRN_IN'] = remove
      add = crn_entry.submit(crn_entry.button_with(:value => 'Submit Changes')).body
      # If it can't re-add the old class it will then raise an exception
      if !(add =~ /#{remove}/) || add =~ /Registration Errors/
        raise 'Well stuff messed up: dropped the class, new class didn\'t register, couldn\'t re-register old class'
      end
      puts 're-registered'
    end

    return false
  end
end

#MAIN LOOP that checks the availability of each courses and fires to registerCrn on availability
def checkCourses(courses)

  request_count = 0
  $failed_adds = 0
  time_start = Time.new
  successes = []
  loop do
    system("clear")

    request_count += 1
    time_now = Time.new

    puts "Checking Availability of CRNs for ".color(:yellow) + $name.to_s
    puts "--------------------------------\n"
    puts "Started:\t#{time_start.asctime}".color(:magenta)
    puts "Now:    \t#{time_now.asctime}".color(:cyan)
    puts "Request:\t#{request_count} (Once every #{$frequency} seconds)".color(:green)
    puts "--------------------------------\n\n"

    courses.each_with_index do |c, i|

      puts "#{c[:crn]} - #{c[:title]}".color(:blue)
      course = getCourse(c[:crn])
      next unless course #If throws error

      puts "Availability: #{course[:seats]} / #{course[:capacity]}".color(:red)

      if (course[:seats] =~ /Full/) then
      # If course is full, do nothing
      else
        if (registerCrn(c[:crn], c[:remove])) then
          puts "CRN #{c[:crn]} Registration Successful"
          # Tracks what CRNs have been added
          successes.push(courses.slice!(i))
          # Remove classes with the same title
          courses.delete_if { |x| x[:title] == successes.last[:title] }
          # If the registration is successful than resets the failed counter
          $failed_adds = 0
        else
          puts "Couldn't Register"

          $failed_adds += 1
          if $failed_adds == 3 then
            raise "CRN #{c[:crn]} was unsuccessfully added 3 times"
          end
        end

      end

      print "\n\n"
    end

    # Lists the CRNs that have been added so far
    if successes.length > 0
      puts "These CRNs have been added successfully: ".color(:magenta)
      successes.each_with_index do |added,i|
        puts "#{i+1}: #{added[:crn]} - #{added[:title]}".color(:cyan)
      end

      puts "\n"
    end

    # When they are done adding returns true so the
    if courses.size == 0
      puts "All classes added".color(:yellow)
      return true
    end

    sleep $frequency
  end
end

#Add courses to be checked
def addCourses
  crns = []

  loop do
    system("clear")
    puts "Your CRNs:".color(:red)
    crns.each do |crn|
      puts "  -> #{crn[:title]} (CRN: #{crn[:crn]})".color(:magenta)
    end

    #Prompt for CRN
    alt = (crns.length > 0)  ? " (or just type 'start') " : " "
    input = ask("\nEnter a CRN to add it#{alt}".color(:green) + ":: ") { |q| q.echo = true }

    #Validate CRN to be 5 Digits
    if (input =~ /^\d{5}$/) then
      remove_loop = true

      # Asks if a class needs to be taken out beforehand
      while remove_loop
        remove = ask("\nDoes another CRN need to be removed? (yes/no) ".color(:blue)) {|q| q.echo = true}
        if remove =~ /yes/
          crn_remove = ask("Enter the CRN: ".color(:green)) {|q| q.echo = true}
          if crn_remove =~ /^\d{5}$/
            remove_loop = false
          end
        elsif remove =~ /no/
          crn_remove = ""
          remove_loop = false
        end
      end

      system("clear")
      #Display CRN Info
      c = getCourse(input.to_s)
      c[:remove] = crn_remove
      puts "\nCourse: #{c[:title]} - #{c[:crn]}".color(:red)
      puts "--> Time: #{c[:begin]}-#{c[:end]} on #{c[:days]}".color(:cyan)
      puts "--> Teacher: #{c[:instructor]}".color(:cyan)
      puts "--> Type: #{c[:type]} || Status: #{c[:status]}".color(:cyan)
      puts "--> Availability: #{c[:seats]} / #{c[:capacity]}".color(:cyan)
      puts "--> CRN to Remove: #{c[:remove]}\n".color(:cyan)


      #Add Class Prompt
      add = ask("Add This Class? (yes/no)".color(:yellow) + ":: ") { |q| q.echo = true }
      crns.push(c) if (add =~ /yes/)

    elsif (input == "start") then
      # When all courses have been added the program ends
      if checkCourses(crns)
        break
      end
    else
      puts "Invalid CRN"
    end
  end
end


def main
  system("clear")
  puts "Welcome to BannerStalker".color(:blue)

  attempting_login = true
  while attempting_login
    $name = ask("Name ".color(:green) + ":: ") {|q| q.echo = true}
    username = ask("PID ".color(:green) + ":: ") { |q| q.echo = true }
    password = ask("Password ".color(:green) + ":: " ) { |q| q.echo = "*" }

    system("clear")
    if login(username, password) then
      attempting_login = false
      addCourses
    else
      puts "Invalid PID/Password".color(:red)
    end
  end
end

main
