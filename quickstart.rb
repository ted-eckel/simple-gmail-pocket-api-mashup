require 'google/apis/gmail_v1'
require 'googleauth/stores/file_token_store'
require 'json'
require 'fileutils'
require 'pocket-ruby'
require 'sinatra'

enable :sessions

CALLBACK_URL = "http://localhost:4567/oauth/callback"

Pocket.configure do |config|
  config.consumer_key = 'INSERT_POCKET_CONSUMER_KEY_HERE'
end

get '/reset' do
  puts "GET /reset"
  session.clear
end

get "/" do
  puts "GET /"
  puts "session: #{session}"

  if session[:access_token]
    '
<a href="/add?url=http://getpocket.com">Add Pocket Homepage</a>
<a href="/retrieve">Retrieve single item</a>
    '
  else
    '<a href="/oauth/connect">Connect with Pocket</a>'
  end
end

get "/oauth/connect" do
  puts "OAUTH CONNECT"
  session[:code] = Pocket.get_code(:redirect_uri => CALLBACK_URL)
  new_url = Pocket.authorize_url(:code => session[:code], :redirect_uri => CALLBACK_URL)
  puts "new_url: #{new_url}"
  puts "session: #{session}"
  redirect new_url
end

get "/oauth/callback" do
  puts "OAUTH CALLBACK"
  puts "request.url: #{request.url}"
  puts "request.body: #{request.body.read}"
  result = Pocket.get_result(session[:code], :redirect_uri => CALLBACK_URL)
  session[:access_token] = result['access_token']
  puts result['access_token']
  puts result['username']
  # Alternative method to get the access token directly
  #session[:access_token] = Pocket.get_access_token(session[:code])
  puts session[:access_token]
  puts "session: #{session}"
  redirect "/"
end

get '/add' do
  client = Pocket.client(:access_token => session[:access_token])
  info = client.add :url => 'http://getpocket.com'
  "<pre>#{info}</pre>"
end

# ==================================================================================
# ==================================================================================

OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'
APPLICATION_NAME = 'Gmail & Pocket API'
CLIENT_SECRETS_PATH = 'client_secret.json'
CREDENTIALS_PATH = File.join(Dir.home, '.credentials',
                             "UNIQUE_FILENAME.yaml")
SCOPE = Google::Apis::GmailV1::AUTH_GMAIL_READONLY

##
# Ensure valid credentials, either by restoring from the saved credentials
# files or intitiating an OAuth2 authorization. If authorization is required,
# the user's default browser will be launched to approve the request.
#
# @return [Google::Auth::UserRefreshCredentials] OAuth2 credentials
def authorize
  FileUtils.mkdir_p(File.dirname(CREDENTIALS_PATH))

  client_id = Google::Auth::ClientId.from_file(CLIENT_SECRETS_PATH)
  token_store = Google::Auth::Stores::FileTokenStore.new(file: CREDENTIALS_PATH)
  authorizer = Google::Auth::UserAuthorizer.new(
    client_id, SCOPE, token_store)
  user_id = 'default'
  credentials = authorizer.get_credentials(user_id)
  if credentials.nil?
    url = authorizer.get_authorization_url(
      base_url: OOB_URI)
    puts "Open the following URL in the browser and enter the " +
         "resulting code after authorization"
    puts url
    code = gets
    credentials = authorizer.get_and_store_credentials_from_code(
      user_id: user_id, code: code, base_url: OOB_URI)
  end
  credentials
end

# Initialize the API
service = Google::Apis::GmailV1::GmailService.new
service.client_options.application_name = APPLICATION_NAME
service.authorization = authorize
user_id = 'me'


get "/retrieve.json" do
  content_type :json

  result = service.list_user_threads(user_id, max_results: 10)
  puts "No threads found" if result.threads.empty?

  combined_array = []

  result.threads.each do |thread|
    threadObject = service.get_user_thread(user_id, thread.id)
    threadObject.messages.each do |message|
      epoch = (message.internal_date.to_i / 1000)
      combined_array << {type: "Gmail",
                          date: Time.at(epoch),
                          time: epoch,
                          object: JSON.parse(message.to_json)}
    end
  end

  client = Pocket.client(:access_token => session[:access_token])
  info = client.retrieve(:detailType => :complete, :count => 10)

  info["list"].each do |key, value|
    epoch = value["time_updated"].to_i
    combined_array << {type: "Pocket", date: Time.at(epoch), time: epoch, object: value}
  end

  sorted_array = combined_array.sort {|x, y| y[:time] <=> x[:time]}
  sorted_array.to_json
end
