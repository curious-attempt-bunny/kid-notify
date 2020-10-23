require "google/apis/calendar_v3"
require "googleauth"
require "googleauth/stores/file_token_store"
require "date"
require "fileutils"
require "json"
require "date"

relative_path = File.dirname(__FILE__)

OOB_URI = "urn:ietf:wg:oauth:2.0:oob".freeze
APPLICATION_NAME = "Kid Notify".freeze
CREDENTIALS_PATH = "#{relative_path}/credentials.json".freeze
# The file token.yaml stores the user's access and refresh tokens, and is
# created automatically when the authorization flow completes for the first
# time.
TOKEN_PATH = "#{relative_path}/token.yaml".freeze
SCOPE = Google::Apis::CalendarV3::AUTH_CALENDAR_READONLY

##
# Ensure valid credentials, either by restoring from the saved credentials
# files or intitiating an OAuth2 authorization. If authorization is required,
# the user's default browser will be launched to approve the request.
#
# @return [Google::Auth::UserRefreshCredentials] OAuth2 credentials
def authorize
  client_id = Google::Auth::ClientId.from_file CREDENTIALS_PATH
  token_store = Google::Auth::Stores::FileTokenStore.new file: TOKEN_PATH
  authorizer = Google::Auth::UserAuthorizer.new client_id, SCOPE, token_store
  user_id = "default"
  credentials = authorizer.get_credentials user_id
  if credentials.nil?
    url = authorizer.get_authorization_url base_url: OOB_URI
    puts "Opening the browser at: " + url
    `open '#{url}'`
    puts "Please enter resulting code:"
    code = gets
    credentials = authorizer.get_and_store_credentials_from_code(
      user_id: user_id, code: code, base_url: OOB_URI
    )
  end
  credentials
end

# Initialize the API
service = Google::Apis::CalendarV3::CalendarService.new
service.client_options.application_name = APPLICATION_NAME
service.authorization = authorize

# puts service.list_calendar_lists().inspect

# raise 'boom'
# Kernel.exit(0)

class Google::Apis::CalendarV3::Event
  def zoom_url
    zoom_urls = JSON.pretty_generate(self).scan(/zoom.us[\/0-9a-z]+[0-9]+/).uniq
    if zoom_urls.size == 1
      return 'https://'+zoom_urls[0]
    else
      return nil
    end
  end

  def start_time
    self.start.date || self.start.date_time
  end
end

class Numeric
  def minutes; self*1.0/(24*60) end
  alias :minute :minutes
end

while true
  calendar_id = ENV['CALENDAR_ID']
  response = service.list_events(calendar_id,
                                max_results:   100,
                                single_events: true,
                                order_by:      "startTime",
                                time_min:      DateTime.now.rfc3339)

  events = response.items.select do |event|
    !File.exists?("data/#{event.id}.notified")
  end

  event = events[0]

  while true
    seconds_until_start = event.start_time.to_time.to_i - Time.now.to_i
    puts "#{event.start_time.strftime("%l:%M %P")} (T-#{seconds_until_start}) #{event.summary} #{event.zoom_url}"
    if seconds_until_start <= 2*60
      File.write("data/#{event.id}.notified", "true")
      File.write("static/next.html", """
      <html>
      <body>
      <h1>#{event.start_time.strftime("%l:%M %P")} - #{event.summary}</h1>
      <p>#{event.zoom_url ? "<a href=\"#{event.zoom_url}\">Open in zoom</a>." : "<a href=\"https://calendar.google.com\">Check your calendar</a>."}</p>
      </body>
      </html>
      """)
      `open ./static/next.html`
      `curl http://localhost:5000/sayall/Class%20time`
      break
    else
      sleep(10)
    end
  end
end