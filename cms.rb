require "sinatra"
require "sinatra/reloader" # reloads the application
require "tilt/erubis"
require "redcarpet"
require "yaml"
require "bcrypt"

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def load_user_yaml
  file = if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end
  YAML.load_file(file)
end

def render_markdown(txt)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(txt)
end

def signed_in?
  session.key?(:username)
end

def only_admit_signed_in_user
  unless signed_in?
    session[:message] = "You must be signed in to do that."
    redirect "/"
  end
end

def valid_credentials?(user, password)
  auth_users = load_user_yaml
  auth_users.key?(user) && BCrypt::Password.new(auth_users[user]) == password
end

configure do
  enable :sessions
  set(:session_secret, SecureRandom.hex(32))
  set(:erb, :escape_html => true)
end

before do
  pattern = File.join(data_path, "*")
  @files = Dir.glob(pattern).map { |fpath| File.basename(fpath) }
end

# view homepage
get "/" do
  erb :index
end

#  view signin page
get "/users/signin" do
  erb :signin
end

# enter credentials
post "/users/signin" do
  user = params[:username]
  pw = params[:password]

  if valid_credentials?(user, pw)
    session[:message] = "Welcome"
    session[:username] = params[:username]
    redirect "/"
  else
    session[:message] = "Invalid credentials"
    status 422
    erb :signin
  end
end

# sign out
post "/users/signout" do
  session[:message] = "You have been signed out."
  session.delete(:username)
  redirect "/"
end

# view page to create a new document
get "/new" do
  only_admit_signed_in_user
  erb :new
end

# create a new document
post "/new" do
  only_admit_signed_in_user

  filename = params[:content].to_s # need to call to_s for <input> tags, <textarea> is fine

  if filename.empty? || ![".txt", ".md"].include?(File.extname(filename))
    session[:message] = "A filename with .txt or .md file extension is required."
    status 422
    erb :new
  else
    filepath = File.join(data_path, filename)
    File.new(filepath, 'w')
    session[:message] = "#{filename} has been created."
    redirect "/"
  end
end

# view file content
get "/:filename" do
  filename = params[:filename]
  pattern = File.join(data_path, filename) # File.read(root + '/data/' + filename)

  if File.exist?(pattern)
    @lines = File.read(pattern)
    ext = filename.split('.')[-1]
    
    case ext
    when "md"
      erb render_markdown(@lines)
    when "txt"
      headers["Content-Type"] = "text/plain"
      @lines
    end
  else
    session[:message] = "#{filename} does not exist."
    redirect "/"
  end
end

# view edit page for a file
get "/:filename/edit" do
  only_admit_signed_in_user

  @filename = params[:filename]
  @lines = File.read(File.join(data_path, @filename)) # File.read(root + '/data/' + @filename)
  erb :edit
end

# update content of an existing file
post "/:filename" do
  only_admit_signed_in_user

  filepath = File.join(data_path, params[:filename]) # File.write(root + '/data/' + params[:filename], params[:content])
  File.write(filepath, params[:content])
  session[:message] = "#{params[:filename]} has been updated."
  redirect "/"
end

# delete an existing file
post "/:filename/delete" do
  only_admit_signed_in_user

  filepath = File.join(data_path, params[:filename])
  File.delete(filepath)
  session[:message] = "#{params[:filename]} has been deleted."
  redirect "/"
end