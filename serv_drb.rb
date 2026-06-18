require 'drb'
require 'erb'
require 'open3'
require 'sqlite3'
require 'json'
require 'cgi'
require 'digest'
require 'fileutils'
require 'rack/multipart'
# require 'rack'
# require 'action_view'
# require 'action_view/helpers'


# скачать страницу
require 'nokogiri'
require "net/http"
require 'open-uri'
require 'pry'
require "httparty"


require 'rss'



class Tag
    
    def self.type_tag(tag, attr={})
        tag_str = ""
        attr.map(){|k, v| tag_str += "#{k}=\"#{v}\""}
        return "<#{tag} #{tag_str}><div>#{yield}</div></#{tag}>" if block_given?
    end
    def self.button(value, attr={})
       
        return "<form action=\"#{attr[:action]}\" method=\"#{attr[:method]}\">
                  <input type=\"text\" name=\"#{attr[:name]}\" value=\"#{attr[:context]}\" hidden>
                  <input type=\"submit\" value=\"#{value}\">
                </form>"
    end
end

$connection = []
$users_hash = {}

class MyService < Tag
  include ActionView::Helpers::TagHelper
  include Nokogiri
  

  attr_accessor :cookie, :params, :multipart_params, :clients, :messages, :page, :users_on
  def initialize()
    @cookie = nil
    @params = nil
    @cook = nil
    @clients = []
    @messages = []
    @users_on = []
    @page = ""
    @mutex = Thread::Mutex.new
    @members = {}
  end

  # ==============block cookie=================================
  def set_cookie(cook)
    @cookie = cook
  end
  # ==============block params=================================
  def set_params(params)
   @params = params
  end
# ==============block file=================================
  def read_file(file)
    # поиск файла в текущуй директории
    find_comm = "find . -type f -name #{file}"
    stdout, stderr, status = Open3.capture3(find_comm)
    if status.success?
      STDOUT.flush #для опустошения буфера вывода.
      STDOUT.sync = true
      File.umask(0200) #определяет начальные разрешения для всех созданных им файлов.
      path = File.expand_path(stdout.chomp) #expand_path преобразует относительное путевое имя в абсолютный путь.
      str = File.binread(path)
    else
      puts "Error: #{stderr}"
    end
    return str
  end
  # =====================user========================================
  def form_login
    db = SQLite3::Database.new("dev.sqlite3")
    # преобразование в хэш
    db.results_as_hash = true
    @users = db.execute "SELECT email, name FROM users;"
    db.close
    return ERB.new(IO.read("./public/form_login.html.erb")).result(binding)
  end

  def session
    # p str
    # code = CGI.unescape(str)
    # распарсить str в хэш
    # params = parse(code)
    # открыть базу даных
    db = SQLite3::Database.new("dev.sqlite3")
    # преобразование в хэш
    db.results_as_hash = true
    # выбрать юзера из таблицы
    begin
       @user_array = db.execute "SELECT * FROM users WHERE email='#{params["email"]}';" #получаем массив в нём хэш юзера
    
    
      # получаем хэш юзера
      @user = @user_array[0]

      # нужно сравнить парль с формы  Base64.encode64(pars["password"]) и пароль из таблица @user["password"]
      if Digest::SHA256.hexdigest(params["password"]).chomp == @user["password"].chomp
        # если пароли совпали
        "<h1>Hello #{@user["name"]}</h1>"
        # добавить куки
        @cookie = "<link rel=\"stylesheet\" href=\"/email=#{@user["email"]}\"><link rel=\"stylesheet\" href=\"/password=#{@user["password"]}\">"
        ERB.new(IO.read("./public/chat.html.erb")).result(binding)
        
      else
        "<br><div class='container' ><p text-color=\"red\">Вы не правильно ввели email или password попробуйте ещё</p></div>"
        

      end
    rescue NoMethodError
        
        "<meta http-equiv=\"Refresh\" content=\"0; URL= /form_login\"/>"
        # "<alert>гражданин с таким логином в базе отсуствует</alert>"
    end
    
  end

  def logout
    # удаляем куки
    @cook = "<link rel=\"stylesheet\" href=\"/email=#{@cookie["/email"]};max-age=0;\">""<link rel=\"stylesheet\" href=\"/password=#{@cookie[" /password"]};max-age=0;\">"
    @users_on.delete @cookie["/email"]
    return ERB.new(IO.read('./public/rss.html.erb')).result(binding)
  end
# =============================chat=======================================
  def chat
     ERB.new(IO.read("./public/chat.html.erb")).result(binding)
  end

  def stream
    return active_user(cookie["/email"])
  end

  def message
  
    # unless msg.to_s.strip.empty?
    # unless msg != nil

    while params["text"] != nil
      formatted_msg = { time: Time.now.strftime('%H:%M:%S'), text: params["text"] }
      sleep 3
      params.clear
      return formatted_msg
    end
  end
  
# =============================rss=======================================
  def rss_link
    return ERB.new(IO.read('./public/rss.html.erb')).result(binding)
  end

  def rss
    @feed = nil
    if params["item"] =~/\w+\.(?:xml|rss)/
      @feed = RSS::Parser.parse("#{params["item"]}")
    else
      @page = HTTParty.get("#{params["item"]}").force_encoding("UTF-8")
    end

    return ERB.new(IO.read('./public/rss_content.html.erb')).result(binding)
  end

  private

  def parse(str)
    
    a = []
    # перекодировать данные
    code = CGI.unescape(str)
    str.gsub!("%40", "@")
    arr_str = str.split("&")
    for line in arr_str
      h = line.split("=")
      a << h
    end
    return a.to_h
  end


  def get_path_to_file(file)
    path = ""
    if file != "" && file != nil
      # поиск файла в текущуй директории
      find_comm = "find . -type f -name #{file}"
      # find_comm = "find . -name #{file}"
      path, stderr, status = Open3.capture3(find_comm)
    end
    if status.success?
      return path
    else
      puts "Error: #{stderr}"
    end
  end

  def run_process_with_params_system(script_path, params)
    command = "ruby #{script_path} #{params.join(' ')}"
    success = system(command)

    if success
      puts "Process finished successfully."
    else
      puts "Process failed."
    end

  end


  def active_user(email)
    # открыть базу даных
    db = SQLite3::Database.new("dev.sqlite3")
    # преобразование в хэш
    db.results_as_hash = true
    # выбрать имена всех юзеров
    users = db.execute "SELECT email, name FROM users;" #получаем массив в нём хэши юзеров
    # Превращаем ключи из строк в символы
    symbolized_results = users.map do |row|
      row.transform_keys(&:to_sym)
    end
    db.close

    if email != nil
        @users_on << email
        @users_on.uniq!
        @unique_set = Set.new(@users_on)
    end
    
    $users_hash = nil
    $users_hash = symbolized_results.map(){|item| item.merge("active" => @unique_set.include?(item[:email]))}
    return $users_hash
    end


end

server = MyService.new

DRb.start_service('druby://:9000', server)
puts "Сервер запущен на druby://:9000"
DRb.thread.join

# system("kill #{Process.pid}")
