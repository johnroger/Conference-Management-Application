class Conference < ActiveRecord::Base

  include MyHtml

  hobo_model # Don't put anything above this

  belongs_to :hosting_conference, :class_name => "Conference"
  belongs_to :general_portfolio, :class_name => "Portfolio"
  acts_as_list :scope => :hosting_conference_id

  fields do
    name        :string, :required
    url         :url
    logo_url    :url
    description :markdown
  end

  belongs_to :joomla_article		# For Colocated conferences

  has_many :colocated_conferences, :class_name => "Conference", :foreign_key => :hosting_conference_id,
    :conditions => 'conferences.id != conferences.hosting_conference_id'
  has_many :host_and_colocated_conferences, :class_name => "Conference", :foreign_key => :hosting_conference_id
  has_many :portfolios, :dependent => :destroy
  has_many :public_portfolios, :class_name => "Portfolio", 
    :conditions => 'length(public_email_address) > 1', :order => :name
  has_many :cfps, :through => :portfolios
  has_many :call_for_supporters, :through => :portfolios
  has_many :call_for_next_years, :through => :portfolios
  has_many :sessions, :through => :portfolios
  has_many :members, :through => :portfolios
  has_many :facility_areas, :dependent => :destroy
  has_many :rooms, :through => :facility_areas
  has_many :facilities, :through => :hosting_conference, :source => :facility_areas
  has_many :participants

  default_scope :order => :position 

  named_scope :host_conferences, :conditions => 'conferences.id = conferences.hosting_conference_id'

  def portfolio_chairs
    portfolios.*.chairs.flatten.sort
  end

  def committee_email_list
    portfolio_chairs.collect{|c| "#{c.name} <#{c.private_email_address}>"}.uniq.sort
  end

  def before_save
    self.name = html_encode_non_ascii_characters(name)
    self.description = html_encode_non_ascii_characters(description)
  end

  def after_save
    update_attributes(:hosting_conference_id => id) unless hosting_conference_id
  end

  def after_destroy
    joomla_article.destroy if joomla_article
  end

  def hosting?
    self == hosting_conference
  end

  def chairs
    general_portfolio.chairs
  end

  def chair? user
    ((chairs + hosting_conference.chairs) & user.members).count > 0
  end

  def cfp_due_dates
    # For populating Call for Papers menu area
    cfps.*.due_on.uniq.collect do |due_on|
      CfpDueDate.new(:due_on => due_on, :cfps => cfps.find_all_by_due_on(due_on))
    end
  end

  def roomless_sessions
    sessions.select{|s| !s.room}
  end

  def days
    # For populating the schedule
    list = {}
    sessions_from_all_conferences.each do |s|
      (list[s.starts_at.midnight] ||= []) << s
    end
    list.sort.collect {|date,sessions| Day.new(:date => date, :sessions => sessions)}
  end

  def selves
    # Kluge for populating the Home menu area
    [self]
  end

  def supporter_portfolios
    # Kluge for populating the Supporters menu area
    call_for_supporters.*.portfolio.uniq
  end

  def portfolios_and_colocated_conferences
    portfolios + colocated_conferences
  end

  def portfolios_from_all_conferences
    portfolios.with_sessions + colocated_conferences.*.portfolios.*.with_sessions.flatten
  end

  def sessions_from_all_conferences
    portfolios_from_all_conferences.*.sessions.flatten
  end

  def after_create 
    portfolios << Portfolio.new(:name => "General")
    self.general_portfolio = portfolios.first
    save
  end

  def publish_to_joomla menu_name
    script_path =  "#{File.dirname(__FILE__)}/../../script"
    unless ENV['PATH'][/^script_path/]
	ENV['PATH'] = script_path + ":" + ENV['PATH']
    end
    system("pull-from-joomla") && populate_joomla_menu_area_for(menu_name) && system("push-to-joomla") 
  end

  MAIN_MENU = [
    { :name => "Home",			:class => JoomlaSection,  :collection => "selves", :alias => 'general-information' },
    { :name => "Grants",		:class => JoomlaSection,  :collection => "selves", :alias => 'grants' },
    { :name => "Attending",		:class => JoomlaSection,  :collection => "selves", :order_on => :ordering },
    { :name => "Schedule",		:class => JoomlaSection,  :collection => "days", :order_on => :checked_out_time,
     :overview_table_columns => ['Day', 'Main Activities', 'Evening Activities']
    },
    { :name => "Program",		:class => JoomlaSection,  :collection => "portfolios_from_all_conferences", :order_on => :ordering },
    { :name => "Calls",	:class => JoomlaSection,  :collection => "cfp_due_dates", :alias => 'cfp', :order_on => :ordering},
    { :name => "Committee",		:class => JoomlaCategory,  :collection => "portfolios_and_colocated_conferences", 
     :overview_table_columns => ['Portfolio', 'Chair', 'Affiliation', 'Country']
    },
    { :name => "Colocated Conferences",	:class => JoomlaCategory, :collection => "colocated_conferences" },
    { :name => "Supporters",		:class => JoomlaCategory, :collection => "supporter_portfolios" },
  ]

  def populate_joomla_menu_area_for menu_name
    DeferredDeletion.all.*.destroy
    MAIN_MENU.each_with_index do |config, index|
      area = joomla_area_for config		# Make sure areas and menu items ...
      menu = joomla_menu_for area, index	# ... are always up to date
#      if [config[:name], "All Areas"].include? menu_name
	populate_joomla_menu_area_with config, area, menu
	area.restore_integrity! config[:order_on]
	menu.restore_integrity! config[:order_on]
#      end
    end
  end

  def populate_joomla_general_information section, extras
    # Populated through Joomla itself
  end

  def populate_joomla_grants section, extras
    grants_menu = JoomlaMenu.find_by_name(section.title)
    overview_text = nil
  end

  def populate_joomla_attending section, extras
    attending_menu = JoomlaMenu.find_by_name(section.title)
    unless section.categories.find_by_title(category_title = 'Registering')
      category = section.categories.create!(:title => category_title)
      article = category.articles.create!(:title => category_title, :sectionid => section.id)
      item = attending_menu.items.create(
	:name => category_title,
	:sublevel => 1,
        :link  => JoomlaMenu::link_for(article)
      )
      item.update_params!(:show_category => "0")
    end
    unless section.categories.find_by_title(category_title = 'Getting to SPLASH')
      category = section.categories.create!(:title => category_title)
      ['Visa Requirements', 'By Air', 'By Car'].each do |title|
	category.articles.create!(:title => title, :sectionid => section.id)
      end
      attending_menu.items.create(
	:name => category_title,
	:sublevel => 1,
        :link  => JoomlaMenu::link_for(category)
      )
    end
    unless section.categories.find_by_title(category_title = 'While at SPLASH')
      category = section.categories.create!(:title => category_title)
      ['Hotel', 'Dining', 'Social Events', 'Transportation', 'Parking', 'Why stay at the Conference Hotel?'].each do |title|
	category.articles.create!(:title => title, :sectionid => section.id)
      end
      attending_menu.items.create(
	:name => category_title,
	:sublevel => 1,
        :link  => JoomlaMenu::link_for(category)
      )
    end
    unless section.categories.find_by_title(category_title = 'Conference Facility Floor Plans')
      category = section.categories.create!(:title => category_title)
      attending_menu.items.create(
	:name => category_title,
	:sublevel => 1,
        :link  => JoomlaMenu::link_for(category)
      )
    end
    category = section.categories.find_by_title(category_title = 'Conference Facility Floor Plans')
    facility_areas.*.populate_joomla_program(category)
    overview_text = nil
  end

  def populate_joomla_colocated_conferences category, extras
    # called for each colocated conference (not for the host conference)
    unless joomla_article
      self.joomla_article = joomla_general_section.articles.create(
	:title => name,
	:catid => category.id
      )
      save!
    end
    fancy_title = name
    fancy_title = img(logo_url, "#{name} logo") if logo_url =~ /\w/
    fancy_title = external_link(url, fancy_title) if url =~ /\w/
    joomla_article.update_attributes(
      :introtext => div("colocated_conference",
	h2(fancy_title),
	description.to_html,
	div("readon", external_link(url,"Read more: #{name}"))
      )
    )
    overview_text = nil
  end

  def populate_joomla_committee category, extras
    # called for each colocated conference (not for the host conference)
    with = " &amp; "
    overview_text = tr({:class => 'committee'},
      td({}, external_link(url, name)),
      td({}, chairs.*.to_html.join(with)),
      td({}, chairs.*.affiliation.join(with)),
      td({}, chairs.*.country.join(with))
    )
  end

  def joomla_general_section
    JoomlaSection.find_by_alias "general-information"
  end

  def html_schedule
    days.*.html_schedule
  end

  def <=> rhs
    position <=> rhs.position
  end


  # --- Permissions --- #

  never_show :joomla_article

  def create_permitted?
    acting_user.administrator?
  end

  def update_permitted?
    return true if acting_user.administrator? 
    return false if any_changed?(:hosting_conference_id, :joomla_article_id)
    chair?(acting_user)
  end

  def destroy_permitted?
    acting_user.administrator?
  end

  def view_permitted?(field)
    true
  end

private

  def joomla_area_for config
    area_class = config[:class]
    area_fields = {:title => config[:name]}
    area_fields[:section] = joomla_general_section.id if area_class == JoomlaCategory
    area = area_class.find(:first, :conditions => area_fields) || area_class.create!(area_fields)
    area.update_attributes!(:alias => config[:alias])
    area
  end

  def joomla_menu_for area, index
    name = area.title
    puts "name=#{name}"
    link = JoomlaMenu::link_for(area)
    menu = JoomlaMenu.find_by_name(name) ||
      JoomlaMenu.find_by_link(link) ||
      JoomlaMenu.create!(:name => name, :link => link)
    menu.update_attributes!(
      :name => name,
      :link => link,
      :alias => area.alias,
      :ordering => index+1
    )
    menu.update_params!(:show_section => "1")
    menu
  end

  def populate_joomla_menu_area_with config, area, menu
    populator = "populate_joomla_" + area.alias.gsub(/\W/,"_")
    extras = { :menu => menu }
    ordering = 0
    parts = method(config[:collection]).call.collect do |item|
      extras[:ordering] = ordering += 1
      item.method(populator).call(area, extras)
    end.compact
    if parts.empty?
      menu.update_attributes!(:link => JoomlaMenu::link_for(area))
    else
      menu.update_attributes!(
	:link => JoomlaMenu::link_for(
	  area.populate_overview_article(fulltext(parts, config))
	)
      )
    end
  end

  def fulltext parts, config
    if columns = config[:overview_table_columns]
      table({},
	tr({}, columns.collect {|c| th({}, c)}),
	parts
      )
    else
      parts.join("\n")
    end
  end

end
