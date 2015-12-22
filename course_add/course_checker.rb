require_relative 'hokie_spa'
require_relative 'colored_string'

class ClassChecker
  def initialize()
    @hokie_spa = HokieSPA.new
  end

  def login(username, password, n = '')
    @name = n
    @hokie_spa.login(username, password)
  end

  # MAIN LOOP that checks the availability of each courses and fires to register_crn on availability
  def check_courses(courses)
    request_count = 0
    failed_adds = 0
    frequency = 1
    time_start = Time.new
    successes = []
    loop do
      system('clear')

      request_count += 1
      time_now = Time.new

      puts 'Checking Availability of CRNs for '.color(:yellow) + @name
      puts "--------------------------------\n"
      puts "Started:\t#{time_start.asctime}".color(:magenta)
      puts "Now:    \t#{time_now.asctime}".color(:cyan)
      puts "Request:\t#{request_count} (Once every #{frequency} seconds)".color(:green)
      puts "--------------------------------\n\n"

      courses.each_with_index do |c, i|
        puts "#{c[:crn]} - #{c[:title]}".color(:blue)
        course = @hokie_spa.get_course(c[:crn])
        next unless course # If throws error

        puts "Availability: #{course[:seats]} / #{course[:capacity]}".color(:red)

        unless course[:seats] =~ /Full/
          register_result = @hokie_spa.register_crn(c[:crn], c[:remove])
          if register_result == :closed
            failed_adds = 0;
          elsif register_result
            puts "CRN #{c[:crn]} Registration Successful"
            # Tracks what CRNs have been added
            successes.push(courses.slice!(i))
            # Remove classes with the same title
            courses.delete_if { |x| x[:title] == successes.last[:title] }
            # If the registration is successful than resets the failed counter
            failed_adds = 0
          else
            puts 'Couldn\'t Register'

            failed_adds += 1
            if failed_adds == 3
              raise "CRN #{c[:crn]} was unsuccessfully added 3 times"
            end
          end

        end

        print "\n\n"
      end

      # Lists the CRNs that have been added so far
      if successes.length > 0
        puts 'These CRNs have been added successfully: '.color(:magenta)
        successes.each_with_index do |added, i|
          puts "#{i + 1}: #{added[:crn]} - #{added[:title]}".color(:cyan)
        end

        puts "\n"
      end

      # When they are done adding returns true so the
      if courses.size == 0
        puts 'All classes added'.color(:yellow)
        return true
      end

      sleep frequency
    end
  end

  # Add courses to be checked
  def add_courses
    crns = []

    loop do
      system('clear')
      puts 'Your CRNs:'.color(:red)
      crns.each do |crn|
        puts "  -> #{crn[:title]} (CRN: #{crn[:crn]})".color(:magenta)
      end

      # Prompt for CRN
      alt = crns.length > 0 ? ' (or just type \'start\') ' : ' '
      input = ask("\nEnter a CRN to add it#{alt}".color(:green) + ':: ') { |q| q.echo = true }

      # Validate CRN to be 5 Digits
      if input =~ /^\d{5}$/
        crn_remove = ''
        # Asks if a class needs to be taken out beforehand
        loop do
          remove = ask('Does another CRN need to be removed? (yes/no) '.color(:blue)) { |q| q.echo = true }

          break if remove =~ /no/
          if remove =~ /yes/
            crn_remove = ask('Enter the CRN: '.color(:green)) { |q| q.echo = true }
          end

          break if crn_remove =~ /^\d{5}$/
        end

        system('clear')
        # Display CRN Info
        c = @hokie_spa.get_course(input.to_s)
        c[:remove] = crn_remove
        puts "\nCourse: #{c[:title]} - #{c[:crn]}".color(:red)
        puts "--> Time: #{c[:begin]}-#{c[:end]} on #{c[:days]}".color(:cyan)
        puts "--> Teacher: #{c[:instructor]}".color(:cyan)
        puts "--> Type: #{c[:type]} || Status: #{c[:status]}".color(:cyan)
        puts "--> Availability: #{c[:seats]} / #{c[:capacity]}".color(:cyan)
        puts "--> CRN to Remove: #{c[:remove]}\n".color(:cyan)

        # Add Class Prompt
        add = ask('Add This Class? (yes/no)'.color(:yellow) + ':: ') { |q| q.echo = true }
        crns.push(c) if add =~ /yes/

      elsif input == 'start'
        # When all courses have been added the program ends
        return crns
      else
        puts 'Invalid CRN'
      end
    end
  end
end