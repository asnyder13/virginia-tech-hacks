require 'rubygems'
require 'mechanize'
require 'nokogiri'
require 'highline/import'
require_relative 'colored_string'

class HokieSPA
  def initialize
    @agent = Mechanize.new
    @agent.redirect_ok = true
    @agent.user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_6_8) AppleWebKit/535.19 (KHTML, like Gecko) Chrome/18.0.1025.11 Safari/535.19'
    @agent.verify_mode = OpenSSL::SSL::VERIFY_NONE
    @term = '01'
    @year = '2016'
  end

  # Logins, Gets the Courses, Returns Courses Obj with Name/URL/Tools for each
  def login(username, password)
    if username.nil? || username.empty? || password.nil? || password.empty?
      return false
    end

    # Login to the system!
    page = @agent.get('https://auth.vt.edu/login?service=https://webapps.banner.vt.edu/banner-cas-prod/authorized/banner/SelfService')
    login = page.forms.first
    login.set_fields({
      username: username,
      password: password
    })

    login_result = login.submit

    unless login_result.body.match(/Invalid username or password/).nil?
      return false
    end
    
    unless login_result.body.match(/Account Recovery Action Required/).nil?
      login_result.link_with(href: /login\?service/).click
    end

    return true
  end

  # Gets Course Information
  def get_course(crn)
    begin
      course_details = Nokogiri::HTML(@agent.get("https://banweb.banner.vt.edu/ssb/prod/HZSKVTSC.P_ProcComments?CRN=#{crn}&TERM=#{@term}&YEAR=#{@year}").body)
    rescue
      return false # Failed to get course
    end

    # Flatten table to make it easier to work with
    course = {}
    data_set = false

    course[:title] = course_details.css('td.title').last.text.gsub(/-\ +/, '')
    course[:crn] = crn

    # Will catch a botched 'get' of the course info
    #   Got a couple exceptions where it was trying to get the text of a null object
    begin
      course_details.css('table table tr').each_with_index do |row|
        # If we have a data_set
        case data_set
        when :rowA
          [:i, :days, :begin, :end, :room, :exam].each_with_index do |el, i|
            course[el] = row.css('td')[i] ? row.css('td')[i].text : ''
          end
        when :rowB
          [:instructor, :type, :status, :seats, :capacity].each_with_index do |el, i|
            course[el] = row.css('td')[i].text
          end
        end

        data_set = false
        # Is there a dataset?
        row.css('td').each do |cell|
          case cell.text
          when 'Days'
            data_set = :rowA
          when 'Instructor'
            data_set = :rowB
          end
        end
      end
    rescue
      course[:seats] = 'Full'
    end

    return course
  end

  # Registers you for the given CRN, returns true if successful, false if not
  def register_crn(crn, remove = '')
    return :closed if refresh_drop_add == :closed

    flag_remove_crn(remove) unless remove.empty?

    add = enter_crn(crn)

    if add =~ /#{crn}/ && !(add =~ /Registration Errors/)
      return true
    else
      # If the new class is not successfully added and a class was dropped to
      #   make room, then re-adds the old class
      unless remove.empty?
        # Get a new drop/add page for re-adding
        refresh_drop_add
        add = enter_crn(remove)
        # If it can't re-add the old class it will then raise an exception
        if !(add =~ /#{remove}/) || add =~ /Registration Errors/
          raise 'Dropped the class, new class didn\'t register, couldn\'t re-register old class'
        end
        puts 're-registered'
      end

      return false
    end
  end

  private

  def refresh_drop_add
    @drop_add = drop_add_page
    @drop_add_html = Nokogiri::HTML(@drop_add.body)
    @crn_entry_form = @drop_add.form_with(action: '/ssb/prod/bwckcoms.P_Regs')
  rescue
    # Does not crash if Drop/Add is not open yet
    puts 'Drop Add not open yet'.color(:red)
    return :closed
  end

  def drop_add_page
    @agent.get('https://banweb.banner.vt.edu/ssb/prod/twbkwbis.P_GenMenu?name=bmenu.P_MainMnu')
    reg = @agent.get('https://banweb.banner.vt.edu/ssb/prod/hzskstat.P_DispRegStatPage')
    reg.link_with(href: "/ssb/prod/bwskfreg.P_AddDropCrse?term_in=#{@year}#{@term}").click
  end

  # Flips the 'drop' box from no to yes for the desired crn
  def flag_remove_crn(remove)
    # Removing the old class if one was specified
    # Counter to keep track of empty rows
    #   Starts at -2 because counter was picking up the rows
    #   before the first class
    offset = -2
    @drop_add_html.css('table table tr').each_with_index do |row, i|
      # Looks down the table to find the row with the CRN that needs to be removed
      unless row.css('td')[1].nil?
        if row.css('td')[1].text =~ /#{remove}/
          # Changes the drop down for the 'Drop' column for the CRN
          @crn_entry_form.field_with(id: "action_id#{i - 3 - offset}").options[0].select
        elsif row.css('td')[1].text =~ /^\d{5}$/ then

        else
          # Counts how many 'empty' rows there are, ex. a class with additional times
          offset += 1
        end
      end
    end
  end

  def enter_crn(crn)
    @crn_entry_form = @drop_add.form_with(action: '/ssb/prod/bwckcoms.P_Regs')
    @crn_entry_form.fields_with(id: 'crn_id1').first.value = crn
    @crn_entry_form['CRN_IN'] = crn
    @crn_entry_form.submit(@crn_entry_form.button_with(value: 'Submit Changes')).body
  end
end
