class Presentation < ActiveRecord::Base

  include MyHtml

  hobo_model # Don't put anything above this

  belongs_to :portfolio
  belongs_to :session
  acts_as_list :scope => :session

  fields do
    title              :string, :required
    short_title        :string
    external_reference :string
    url                :url
    reg_number         :string
    audience           :string
    class_type         :string
    class_format       :markdown
    abstract           :markdown
    objectives         :markdown
    resume             :markdown
    timestamps
  end

  has_many :involvements, :dependent => :destroy
  has_many :participants, :through => :involvements

  default_scope :order => :position
  
  def self.configurable_fields
    non_id_fields = column_names.reject{|f| f =~ /^id$|_id$/}
    non_id_fields - %w(created_at updated_at position)
  end

  def initialize *args
    super *args
    self.portfolio ||= session && session.portfolio
  end
  
  def validate
    if session
      errors.add(:session_id, "must be from the correct portfolio") unless
        session.portfolio_id == portfolio_id
    end
  end

  validates_uniqueness_of :title, :scope => :portfolio_id
  validates_uniqueness_of :short_title, :scope => :portfolio_id, :allow_nil => true, :allow_blank => true


  def before_save
    self.session ||= portfolio && portfolio.new_or_existing_session(title)
    self.title = html_encode_non_ascii_characters(title)
    self.short_title = html_encode_non_ascii_characters(short_title)
    self.audience = html_encode_non_ascii_characters(audience)
    self.abstract = html_encode_non_ascii_characters(abstract)
    self.objectives = html_encode_non_ascii_characters(objectives)
    self.resume = html_encode_non_ascii_characters(resume)
  end

  def after_update
    return unless session 
    if session_id_changed?
      [session_id_was, session_id].compact.each do |id|
	Session.find(id).normalize_presentation_positions!
      end
    end
    return unless session.single_presentation?
    session.update_attributes(:name => title) unless session.name == title
    session.update_attributes(:short_name => short_title) unless session.short_name == short_title
  end

  def after_save
    portfolio.changes_pending!
  end

  def conference
    portfolio.conference
  end

  def essential_fields
    %w(title short_title external_reference abstract)
  end

  def extra_fields
    portfolio.presentation_fields.split(/,\s*/) - essential_fields
  end

  def load_from xml
    involvements.destroy_all
    xml.elements.each do |element|
      text = element.text.strip rescue ""
      case element.name
      when "title":		self.title = text
      when "shorttitle":	self.short_title = text
      when "abstract":		self.abstract = text
      when "author":		self.involvements.create(
				  :role => 'author',
				  :participant =>  new_or_existing_participant(element)
				)
      when "workshop_url":	self.url = text
      when "tutclass":		self.class_type = text
      when "format":		self.class_format = text
      when "tutaudience":	self.audience = text
      when "tutresume":		self.resume = text
      when "objectives":	self.objectives = text
      else
	logger.info "Presentation::load_from does not handle #{element.name} elements"
      end
    end
    save
    self
  end

  def new_or_existing_participant xml
    fields = {}
    xml.elements.each do |element|
      text = element.text.strip
      case element.name
      when "name":		fields[:name] = text
      when "email":		fields[:private_email_address] = text
      when "affiliation":	fields[:affiliation] = text
      when "country":		fields[:country] = text
      when "bio":		fields[:bio] = text
      else
	logger.info "Presentation::load_from does not handle author.#{element.name} elements"
      end
    end
    [:private_email_address, :name].each do |field|
      value = fields[field]
      next unless value && value[/\S/]
      matches = Participant.find(:all, :conditions => {field => value, :conference_id => conference.id})
      if matches.count == 1
	existing = matches.first
	existing.update_attributes(fields) or next
	return existing
      end
    end
    conference.hosting_conference.participants.create(fields)
  end


  def intro_html
    if session.single_presentation?
      div("participants",participants_to_html)
    else
      li(title_to_html,
	div("participants",participants_to_html)
      )
    end
  end

  def at_a_glance_title
    if session.single_presentation?
      participants.collect{|p| "* #{p.name}"}
    else
      "* #{title}"
    end
  end

  def to_html
    div("presentation",
      title_to_html,
      participants_to_html,
      abstract.to_html.gsub(/<p>&lt;keep-this-table/,"<table").gsub(/&lt;.keep-this-table><.p>/,"</table>"),
      extra_fields.collect do |field|
        label = field.humanize
	raw_value = self.method(field).call
	next unless raw_value =~ /\w/
	value = raw_value.to_html
	div("presentation-extra",
	  case value
	  when HoboFields::MarkdownString: [h5(label), value]
	  when String: [span("label", label), span("", value)]
	  end
        )
      end.compact
    )
  end

  def title_to_html
    div("title", title.to_html) unless session.single_presentation?
  end

  def participants_to_html
    div("participants",
      involvements.*.to_html
    )
  end


  def session_options
    portfolio.sessions.collect { |s| [s.name, s.id] }.sort
  end


  # --- Permissions --- #

  def create_permitted?
    return true if acting_user.administrator?
    portfolio.chair?(acting_user) || conference.chair?(acting_user)
  end

  def update_permitted?
    return false if portfolio_id_changed?
    return false if session_id_changed? && !portfolio.multiple_presentations_per_session?
    portfolio.chair?(acting_user) || conference.chair?(acting_user) || acting_user.administrator?
  end

  def destroy_permitted?
    portfolio.chair?(acting_user) || conference.chair?(acting_user) || acting_user.administrator?
  end

  def view_permitted?(field)
    return false unless acting_user.signed_up?
    if self.class.configurable_fields.include?(field.to_s)
      portfolio.configured_presentation_fields.include?(field.to_s)
    else
      true
    end
  end

  def move_higher_permitted?
    editable_by?(acting_user, :position)
  end

  def move_lower_permitted?
    editable_by?(acting_user, :position)
  end

end
