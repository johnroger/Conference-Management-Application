class Day

  include MyHtml

  attr_reader :date, :day_sessions, :evening_sessions
  attr_accessor :joomla_category, :joomla_article, :joomla_menu
  
  def initialize attribs
    @date = attribs[:date]
    @day_sessions, @evening_sessions = attribs[:sessions].partition {|s| s.ends_at <= end_of_day}
    @day_sessions.sort!
    @evening_sessions.sort!
  end

  def end_of_day
    date + 17.hours + 30.minutes
  end

  def starts_at
    day_sessions.*.starts_at.min
  end

  def ends_at
    day_sessions.*.ends_at.max
  end

  def tick_size
    15.minutes
  end

  def tick_count
    ((ends_at - starts_at) / tick_size).round
  end

  def ncols 
    # includes 2 columns for room names,
    # as well as a column of each evening session
    2 + tick_count + evening_sessions.count
  end

  def name
    "Due #{date.strftime('%B %d, %Y')}"
  end

  def rooms
    day_sessions.*.room.uniq.sort do |a,b|
      a.nil? && b.nil? ? 0 : 
	a.nil? ? 1 : 
	b.nil? ? -1 :
	a <=> b
    end
  end

  def populate_joomla_schedule section, extras
    # Kluge: category checked_out_time is not used during the generatation of content,
    #        so co-opt it for sorting purposes (see JoomlaSection::restore_integrity!)
    find_or_create_joomla_category_in section
    find_or_create_joomla_article_in joomla_category
    find_or_create_joomla_menu_in extras[:menu]
#    overview_text = [
#      h4(internal_link(joomla_category, name)),
#	ul(sessions.collect{|c| c.populate_joomla_call_for_papers joomla_category})
#    ]
    overview_text = ""
  end

  def find_or_create_joomla_category_in section
    self.joomla_category = section.categories.find_by_title('Days') ||
      section.categories.create!(:title => 'Days')
    joomla_category.update_attributes(:alias => nil)
    joomla_category
  end

  def find_or_create_joomla_article_in category
    self.joomla_article = category.articles.find_by_title(name) ||
      category.articles.create!(:title => name, :checked_out_time => date)
    joomla_article.update_attributes(:alias => nil)
    joomla_category
  end

  def find_or_create_joomla_menu_in menu
    joomla_menu = menu.items.find_by_name(name) || menu.items.create(:name => name)
    joomla_menu.update_attributes(
      :checked_out_time	=> date,
      :parent		=> menu.id,
      :sublevel		=> 1,
      :link		=> JoomlaMenu::link_for(joomla_article),
      :alias		=> nil
    )
    joomla_menu
  end

  def html_schedule
    div({:class => "at-a-glance"},
      h3(date.strftime("%A (%b %d)")),
      at_a_glance_table
    )
  end

  def at_a_glance_table 
    table({ :class => "at-a-glance" },
      at_a_glance_header,
      rooms.collect {|r| at_a_glance_row r},
      at_a_glance_footer
    )
  end

  def at_a_glance_header
    tr({:class => "not-happening"},
      th({:class => "room"}, "Room"),
      at_a_glance_row_part_for(label_pseudo_sessions).join("").gsub(/td/,"th"),
      th({:class => "room"}, "Room"),
      [td({:class => "happening"})] * evening_sessions.count
    )
  end

  def at_a_glance_row room
    label = room ? room.short_name : "TBD"
    tr({:class => "not-happening"},
      th({:class => "room"}, label),
      at_a_glance_row_part_for(sessions_for room),
      th({:class => "room"}, label)
    )
  end

  def at_a_glance_footer
    tr({},
      [td({:class => "not-happening calibration"},"&nbsp;")] * ncols
    )
  end

  def at_a_glance_row_part_for sessions
    tape = ticker_tape_for sessions
    tds = []
    while tape.size > 0
      ncols = 1
      session = tape.shift
      while tape.size > 0 && session == tape.first
	ncols += 1
	tape.shift
      end
      css = {
	:colspan	=> ncols,
	:class		=> (session ? "happening" : "not-happening")
      }
      tds << td(css, session ? session.at_a_glance_html : "&nbsp;")
    end
    tds
  end

  def label_pseudo_sessions
    duration = 90
    start_times = [
      date + 8.hours + 30.minutes,
      date + 10.hours + 30.minutes,
      date + 13.hours + 30.minutes,
      date + 15.hours + 30.minutes
    ]
    start_times.collect do |st|
      et = st + duration.minutes
      name = [st, et].collect{|t| t.strftime('%I:%M').sub(/^0+/,"")}.join("-")
      Session.new(:name => name, :starts_at => st, :duration => duration)
    end.select do |s|
      starts_at <= s.starts_at && s.ends_at <= ends_at
    end
  end

  def sessions_for room
    day_sessions.select{|s| s.room == room}
  end

  def ticker_tape_for sessions
    tape = Array.new(tick_count)
    sessions.reject{|s| s.duration < 30}.each do |s|
      start_tick = ((s.starts_at - starts_at) / tick_size).round
      nticks = (s.duration.minutes / tick_size).round
      tape[start_tick, nticks] = [s] * nticks
    end
    tape
  end

end