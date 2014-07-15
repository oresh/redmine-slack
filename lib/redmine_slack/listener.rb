require 'httpclient'

class SlackListener < Redmine::Hook::Listener
	def controller_issues_new_after_save(context={})
		issue = context[:issue]

		channel = channel_for_project issue.project

		return unless channel

		msg = "<#{object_url issue}|#{escape issue}> - #{escape issue.status.to_s} >> #{escape issue.assigned_to.to_s}"

		attachment = {}
		attachment[:text] = escape issue.description if issue.description
		attachment[:fields] = [{
			:title => I18n.t("field_status"),
			:value => escape(issue.status.to_s),
			:short => true
		}, {
			:title => I18n.t("field_priority"),
			:value => escape(issue.priority.to_s),
			:short => true
		}, {
			:title => I18n.t("field_assigned_to"),
			:value => escape(issue.assigned_to.to_s),
			:short => true
		}]

		speak msg, channel, attachment
	end

	def controller_issues_edit_after_save(context={})
		issue = context[:issue]
		journal = context[:journal]

		channel = channel_for_project issue.project

		return unless channel

		msg = "Update: <#{object_url issue}|#{escape issue}> - #{escape issue.status.to_s} >> #{escape issue.assigned_to.to_s}"

		attachment = {}
		attachment[:text] = escape journal.notes if journal.notes
		attachment[:fields] = journal.details.map { |d| detail_to_field d }
		changed = journal.details.map { |d| status_changed d }
		redminestatus = escape issue.status.to_s

		if changed != false and changed != "[false]"
		speak "Changed true!: #{changed}", "#slack_test", attachment

		if redminestatus != "Closed"
			speak msg, channel, attachment
		end

	end

	def speak(msg, channel, attachment=nil)
		url = Setting.plugin_redmine_slack[:slack_url]
		username = Setting.plugin_redmine_slack[:username]
		icon = Setting.plugin_redmine_slack[:icon]

		params = {
			:text => msg
		}

		params[:username] = username if username
		params[:channel] = channel if channel

		# params[:attachments] = [attachment] if attachment

		if icon and not icon.empty?
			if icon.start_with? ':'
				params[:icon_emoji] = icon
			else
				params[:icon_url] = icon
			end
		end

		client = HTTPClient.new
		client.ssl_config.cert_store.set_default_paths
		client.post url, {:payload => params.to_json}
	end

private
	def escape(msg)
		msg.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
	end

	def object_url(obj)
		Rails.application.routes.url_for(obj.event_url :host => Setting.host_name)
	end

	def channel_for_project(proj)
		cf = ProjectCustomField.find_by_name("Slack Channel")

		val = proj.custom_value_for(cf).value rescue nil

		if val.blank? and proj.parent
			channel_for_project proj.parent
		elsif val.blank?
			Setting.plugin_redmine_slack[:channel]
		elsif not val.starts_with? '#'
			nil
		else
			val
		end
	end

	def detail_to_field(detail)
		if detail.property == "cf"
			key = CustomField.find(detail.prop_key).name rescue nil
			title = key
		elsif detail.property == "attachment"
			key = "attachment"
			title = I18n.t :label_attachment
		else
			key = detail.prop_key.to_s.sub("_id", "")
			title = I18n.t "field_#{key}"
		end

		short = true
		value = escape detail.value.to_s

		case key
		when "title", "subject", "description"
			short = false
		when "tracker"
			tracker = Tracker.find(detail.value) rescue nil
			value = escape tracker.to_s
		when "project"
			project = Project.find(detail.value) rescue nil
			value = escape project.to_s
		when "assigned_to"
			user = User.find(detail.value) rescue nil
			value = escape user.to_s
		when "fixed_version"
			version = Version.find(detail.value) rescue nil
			value = escape version.to_s
		end

		value = "-" if value.empty?

		result = { :title => title, :value => value }
		result[:short] = true if short
		result
	end

	def status_changed(detail)
		if detail.property == "cf"
			key = CustomField.find(detail.prop_key).name rescue nil
			title = key
		elsif detail.property == "attachment"
			key = "attachment"
			title = I18n.t :label_attachment
		else
			key = detail.prop_key.to_s.sub("_id", "")
			title = I18n.t "field_#{key}"
		end

		result = false

		speak "Key: #{key}", "#slack_test", nil

		case key
		when "status"
			result = true
		end

		result
	end
end
