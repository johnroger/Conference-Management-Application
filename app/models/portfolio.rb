class Portfolio < ActiveRecord::Base

  require 'rexml/document'
  include REXML

  hobo_model # Don't put anything above this

  belongs_to :conference
  attr_readonly :conference_id

  fields do
    name        :string, :required
    public_email_address :email_address
    session_type enum_string(:no_sessions, :single_presentation, :multiple_presentations, :all_in_one), :required,
      :default => 'no_sessions'
    call_type	enum_string(:no_call, :for_presentations, :for_supporters), :required, :default => 'no_call'
    description :markdown
  end

  belongs_to :joomla_category
  belongs_to :joomla_menu

  has_many :chairs, :class_name => "Member", :conditions => {:chair => true}
  has_many :members, :dependent => :destroy
  has_many :cfps, :dependent => :destroy	# Really only one, but we want the hobo support

  has_many :sessions, :dependent => :destroy
  has_many :presentations, :dependent => :destroy

  has_many :call_for_supporters, :dependent => :destroy

  def chair? user
    not (chairs & user.members).empty?
  end

  def cfp
    cfps.first
  end


  def load_presentation_from source
    xml = Document.new(source).root
    new_or_existing_presentation(xml).load_from xml
  end

  def new_or_existing_session single_presentation_session_name = nil
    case session_type
    when 'multiple_presentations':	sessions.find_by_name(Session::DEFAULT_NAME) || sessions.create
    when 'single_presentation':		sessions.create(:name => single_presentation_session_name)
    when 'all_in_one':			sessions.first || sessions.create(:name => name)
    else
      sessions.create
    end
  end

  def new_or_existing_presentation xml
    references = {
      :external_reference	=> xml.attributes["id"],
      :title			=> xml.elements["title"].text,
      :short_title		=> xml.elements["shorttitle"].text,
    }
    [:external_reference, :title, :short_title].each do |field|
      value = references[field]
      next unless value && value[/\S/]
      matches = presentations.find(:all, :conditions => {field => value})
      return matches.first if matches.count == 1
    end
    presentations.create!(references)
  end

  def populate_joomla_program section, menu
    return if session_type == 'no_sessions'
    if joomla_category
      joomla_category.write_attribute(:title, name)
      joomla_menu.write_attribute(:name, name)
    else
      self.joomla_category = section.categories.create(:title => name)
      self.joomla_menu = menu.items.create(
	:name => name,
	:parent => menu.id,
	:sublevel => 1,
        :link  => JoomlaMenu::link_for(joomla_category)
      )
      save
    end
    sessions.each{|s| s.populate_joomla_program joomla_category}
  end


  # --- Permissions --- #
  
  never_show :joomla_category, :joomla_menu

  def create_permitted?
    return true if acting_user.administrator?
    conference && conference.chair?(acting_user)
  end

  def update_permitted?
    return false if name_changed? && name_was == "General"
    return false if any_changed?(:conference_id) && !acting_user.administrator?
    chair?(acting_user) || conference.chair?(acting_user) || acting_user.administrator?
  end

  def destroy_permitted?
    return false if name == "General"
    members.empty? && (conference.chair?(acting_user) || acting_user.administrator?)
  end

  def view_permitted?(field)
    acting_user.signed_up?
  end

end
