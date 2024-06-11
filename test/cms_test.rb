ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"
require_relative "../cms"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  ### setup and teardown methods
  def setup
    FileUtils.mkdir_p(data_path)

    about_content = <<~CONTENT
    # Ruby is...
    ## a programming langugage that is natural to read and easy to write.
    CONTENT
    changes_content = "This is the changes page."
    history_content = "Ruby 0.95 released"

    create_document("about.md", content=about_content)
    create_document("changes.txt", content=changes_content)
    create_document("history.txt", content=history_content)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  ### helper methods
  def session
    last_request.env["rack.session"]
  end

  def create_document(name, content="")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def admin_session_credential
    { "rack.session" => { username: "admin" } }
  end

  ### tests
  def test_index
    get "/"
    assert_equal(200, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_includes(last_response.body, "about.md")
    assert_includes(last_response.body, "changes.txt")
    assert_includes(last_response.body, "history.txt")
    assert_includes(last_response.body, "Sign in")
  end

  def test_about
    get "/about.md"
    assert_equal(200, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_includes(last_response.body, "<h1>Ruby is...</h1>")
  end

  def test_changes
    get "/changes.txt"
    assert_equal(200, last_response.status)
    assert_equal("text/plain", last_response["Content-Type"])
    assert_equal("This is the changes page.", last_response.body)
  end

  def test_history
    get "/history.txt"
    assert_equal(200, last_response.status)
    assert_equal("text/plain", last_response["Content-Type"])
    assert_equal("Ruby 0.95 released", last_response.body)
  end

  def test_nonexisting_doc
    get "/does_not_exist.txt"
    assert_equal(302, last_response.status)
    assert_equal("does_not_exist.txt does not exist.", session[:message])

    # get last_response["Location"] # get the url where the user is redirected to
    # assert_equal(200, last_response.status)
    # assert_includes(last_response.body, "does_not_exist.txt does not exist.")

    # get "/" # reloads the page
    # assert_equal(200, last_response.status)
    # refute_includes(last_response.body, "does_not_exist.txt does not exist.")
  end

  def test_view_edit_page
    get "/history.txt/edit", {}, admin_session_credential
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "Editing content of history.txt:")
    assert_includes(last_response.body, %q(<button type="submit">))
  end

  def test_view_edit_page_signed_out
    get "/history.txt/edit"
    assert_equal(302, last_response.status)
    assert_equal("You must be signed in to do that.", session[:message])
  end

  def test_post_edit_page
    post "/history.txt", { content: "new changes" }, admin_session_credential
    assert_equal(302, last_response.status)
    assert_equal("history.txt has been updated.", session[:message])

    get "/history.txt"
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "new changes")
  end

  def test_post_edit_page_signed_out
    post "/history.txt", { content: "new changes" }
    assert_equal(302, last_response.status)
    assert_equal("You must be signed in to do that.", session[:message])
  end

  def test_get_new
    get "/new", {}, admin_session_credential
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "Add a new document:")
    assert_includes(last_response.body, %q(<button type="submit">Create</button>))
  end

  def test_get_new_signed_out
    get "/new"
    assert_equal(302, last_response.status)
    assert_equal("You must be signed in to do that.", session[:message])
  end

  def test_post_new
    post "/new", { content: "test.txt" }, admin_session_credential
    assert_equal(302, last_response.status)
    assert_equal("test.txt has been created.", session[:message])

    get last_response["Location"]
    assert_equal(200, last_response.status)
  end

  def test_post_new_signedout
    post "/new", { content: "test.txt" }
    assert_equal(302, last_response.status)
    assert_equal("You must be signed in to do that.", session[:message])
  end

  def test_post_new_empty
    post "/new", { content: "" }, admin_session_credential
    assert_equal(422, last_response.status)
    assert_includes(last_response.body, "Add a new document:")
    assert_includes(last_response.body, %q(<button type="submit">Create</button>))
  end

  def test_post_new_no_extension
    post "/new", { content: "filename" }, admin_session_credential
    assert_equal(422, last_response.status)
    assert_includes(last_response.body, "Add a new document:")
    assert_includes(last_response.body, %q(<button type="submit">Create</button>))
  end

  def test_delete
    create_document("test.txt")

    post "/test.txt/delete", {}, admin_session_credential
    assert_equal(302, last_response.status)
    assert_equal("test.txt has been deleted.", session[:message])

    get "/"
    refute_includes(last_response.body, %q(href="/<%= file %>"))
  end

  def test_delete_signed_out
    post "/test.txt/delete"
    assert_equal(302, last_response.status)
    assert_equal("You must be signed in to do that.", session[:message])
  end

  def test_signin_form
    get "/users/signin"
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "Username: ")
    assert_includes(last_response.body, "Password: ")
    assert_includes(last_response.body, %q(<button type="signin">Sign In</button>))
  end

  def test_signin
    post "/users/signin", username: "admin", password: "secret"
    assert_equal(302, last_response.status)
    assert_equal("Welcome", session[:message])
    assert_equal("admin", session[:username])

    get last_response["Location"]

    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "Signed in as admin") # checks that the session username is set
    assert_includes(last_response.body, %q(<button type="signout">Sign out</button>))
  end

  def test_signin_wrong
    post "/users/signin", username: "wrong", password: "123"
    assert_nil(session[:username])
    assert_equal(422, last_response.status)
    #assert_equal("Invalid credentials", session[:message]) # why doesn't this work?

    assert_includes(last_response.body, "Invalid credentials")
    assert_includes(last_response.body, %q(placeholder="wrong")) # checks that the wrong username is displayed
    assert_includes(last_response.body, %q(<button type="signin">Sign In</button>))
  end

  def test_signout
    get "/", {}, admin_session_credential  # using session to sign in first
    assert_includes(last_response.body, "Signed in as admin")

    post "/users/signout"
    assert_equal(302, last_response.status)

    get last_response["Location"]
    assert_includes(last_response.body, "You have been signed out.")
    assert_includes(last_response.body, "Sign in")
  end
end