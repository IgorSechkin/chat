require 'erb'
require 'drb'
require 'open3'
require 'json'
require 'rack'
require 'rack/multipart'

require 'cgi'

require 'thread'



# запускаем сервер drb
Thread.new {
  
      system("ruby serv_drb.rb")
}


class App
  
  attr_accessor :body, :env_type, :sock, :path_info, :type, :content, :headers
  @connection = []
  def initialize()
    
    @mutex = Thread::Mutex.new
    @queue = Queue.new
    @broadcaster = $broadcaster
    # @type = Type_struct.new("text/html", "text/css", "image/gif", "text/css", "text/css", "application/json", "text/javascript", "application/octet-stream", "application/wasm")
    
  end

  def call(env)

    # Dir.chdir("./")
    
    # client drb
    DRb.start_service
    @ro = DRbObject.new_with_uri("druby://localhost:9000")

    # env.each{|en| p en}

    @multipart_params = Rack::Multipart.parse_multipart(env)

    @request = Rack::Request.new(env)
    @response = Rack::Response.new(env)
    
    @path_info = env["REQUEST_PATH"]
    @env_type = env["HTTP_SEC_FETCH_DEST"]
    @env_meth = env["REQUEST_METHOD"]
    @sock = env["puma.socket"]

    @env_params = env["rack.input"].read
    code = CGI.unescape(@env_params)
    
    # отправляем на сервер drb параметры
    if @env_meth == 'POST'
      if @multipart_params != nil
        # для загрузки картинок
        @ro.send(:set_params, @multipart_params) 
      else
        if @path_info == "/rss" || @path_info == "/message" || @path_info == "/stream"   # идет через javascript в формате json
          params = JSON.parse(code)
          @ro.send(:set_params, params)
        else
          @ro.send(:set_params, parse(code)) # в формате string
        end
      end
    elsif @env_meth == 'GET'
      # это для пагинации идет запрос через <a> но с параметром ( <li class="page-item" ><a class="page-link" href="?page=<%= num %>"><%= num %></a></li> )
      # @request.params может отправлять все за исключением javascript (но это не точно)
      @ro.send(:set_params, @request.params) if !@request.params.empty?
    end
    
    # отправляем на сервер drb куки
    if env["HTTP_COOKIE"] != nil
      @ro.send(:set_cookie, parse_cookie(env["HTTP_COOKIE"]))
    end
  
    [200, {"content-type" => "#{get_content_type(@env_type)}"}, [get_template{get_block_template(@path_info)}] ]
    
    
  end

  private

  def get_template
    return ERB.new(IO.read('template.html.erb')).result(binding) if block_given?
  end

  def get_block_template(arg)

    file = arg.delete("/").chomp if arg != nil

    if file =~ /\w+\.(?:png|jpeg|jpg|avi|mp4|xml|mp3|ico|css|xml|js|json|txt|csv|wasm|jquery|html.erb|html)/
      # content_file = File.binread(fstdout.chomp)
      content_file = @ro.send(:read_file, file)
      str = "HTTP/1.1 200 OK\r\nContent-Type: #{get_content_type(@env_type)}\r\nContent-Length: #{content_file.size}\r\n\r\n#{content_file}"
      @sock.write str
      @sock.close
    elsif file == ""
      File.read("public/index.html.erb")
    elsif file == "stream"
      users = @ro.stream();
      str = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\nX-Accel-Buffering: no\r\n\r\n#{"data: #{users.to_json}"}\n\n"
      @sock.write str
      @sock.close
    # elsif file == "message"
    #       # ====================не пошло как хотел ==================================
    #       # =================сдесь нужно как-то сделать чтобы без сообщения поток засыпал=================
    #   messages = @ro.message()
    #   @queue << messages
    #   headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\nX-Accel-Buffering: no\r\n\r\n"
    #   @sock.write headers
      
    #   begin
    #     msg = @queue.pop
    #     body = "#{"data: #{msg.to_json}"}\n\n"
    #     @sock.write body

    #   rescue IOError, ClientDisconnect
    #       puts "Браузер закрыл вкладку, удаляем очередь."
    #   ensure
    #       # @broadcaster.connections.delete(@queue) if @broadcaster.respond_to?(:connections)
    #   end
    #   @sock.close
      
    elsif file == "rss_link" || file == "rss" || file == "form_login" || file == "session" || file == "message" || 
      file == "chat" || file == "logout"
      @ro.send(file.to_sym)
    elsif file =~ /([^=]+)=([^;]+)/
      # для javascript не принимает с параметром HttpOnly;
      @sock.write "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nSet-Cookie: #{arg}; Path=/; secure; SameSite=none;"
      # @sock.write"HTTP/1.1 200 OK\r\nContent-Type: text/css\r\nSet-Cookie: #{arg}; Path=/; HttpOnly; secure; SameSite=Lax;"
    else

    end

  end

  def get_content_type(arg)
    if arg == "document"
      return "text/html"
    elsif arg == "style"
      return "text/css"
    elsif arg == "image"
      return "image/jpeg"
    elsif arg == "audio"
      return "audio/mpeg"
    elsif arg == "video"
      return "video/mp4"
    elsif arg == "manifest"
      return "application/json"
    elsif arg == "script"
      return "text/javascript"
    elsif arg == "empty"
      return  "application/xml; charset=utf-8"
    else
      return "application/wasm"
    end

  end

  def parse_cookie(str)
    a = []
    arr_str = str.split("; ")
    for line in arr_str
      h = line.split("=")
      a << h
    end
    return a.to_h
  end
  def parse_message(str)
    a = []
    arr_str = str.split()
    for line in arr_str
      h = line.split("=")
      a << h
    end
    return a.to_h
  end

  def parse(str)
    a = []
    # перекодировать данные
    # code = CGI.unescape(str)
    str.gsub!("%40", "@")
    arr_str = str.split("&")

    for line in arr_str
      h = line.split("=")
      if h.size == 2
        a << h
      end
    end
    return a.to_h
  end

end

# ===========chat================

require 'thread'
require 'set'

$users_hash = nil

# Хранилище для всех активных SSE-подключений
class ChatBroadcaster
  @connections = [""]
  @users_on = []
  
  class << self
    def subscribe(connection)
      @connections << connection
    end

    def unsubscribe(connection)
      @connections.delete(connection)
    end


    def broadcast(message)
      # Отправляем сообщение во ВСЕ открытые браузеры
      @connections.each do |conn|
        conn.write("data: #{message.to_json}\n\n")
        # Для некоторых серверов (например, Puma) нужен принудительный сброс буфера:
        conn.flush if conn.respond_to?(:flush)
      rescue
        # Если клиент отключился, удаляем его
        unsubscribe(conn)
      end
    end
  end
end

# глобальная переменная
$broadcaster = ChatBroadcaster.new

# Наше Rack приложение
class ChatApp
    
  def initialize
    @mutex = Thread::Mutex.new  
  end
  def call(env)
    # p env['rack.upgrade?']
    request = Rack::Request.new(env)
    # 1. Точка подключения к SSE (Браузеры слушают этот эндпоинт)
    if request.path == '/chat/stream'
      headers = {
        'Content-Type' => 'text/event-stream',
        'Cache-Control' => 'no-cache',
        'Connection' => 'keep-alive',
        'X-Accel-Buffering' => 'no' # Отключает буферизацию в Nginx
      }

      # Используем rack.hijack для перехвата сокета и удержания постоянного соединения
        body = lambda do |stream|
            # @mutex.synchronize {ChatBroadcaster.subscribe(stream)}
            if env["HTTP_COOKIE"] != nil
              cookie = parse_cookie(env["HTTP_COOKIE"])
            end
            # stream.instance_variable_set(:@email, cookie['/email'])
            # ChatBroadcaster.active_user(cookie["/email"])
            @mutex.synchronize {ChatBroadcaster.subscribe(stream)}
            
            # Поддерживаем соединение открытым. При закрытии вкладки удаляем подписчика.
            # stream.instance_variable_get(:@io).to_io.close_on_exec = true rescue nil
            # p stream.instance_variables
            
              
            
            stream.flush if stream.respond_to?(:flush)

            # sleep 3
        end   
      return [200, headers, body]

    end

    # 2. Точка отправки сообщений (Сюда стучит fetch)
    if request.path == '/chat/send' && request.post?
      payload = JSON.parse(request.body.read) rescue {}
      if env["HTTP_COOKIE"] != nil
          cookie = parse_cookie(env["HTTP_COOKIE"])
      end
      
      if payload['text'] && !payload['text'].strip.empty?
        # Рассылаем сообщение ВСЕМ, включая отправителя
        ChatBroadcaster.broadcast({
          email: cookie["/email"],
          text: payload['text'],
          time: Time.now.strftime('%H:%M:%S')
        })
      end
      return [200, { 'Content-Type' => 'application/json' }, [{ status: 'success' }.to_json]]
    end
  end

  private

  def parse_cookie(str)
    a = []
    arr_str = str.split("; ")
    for line in arr_str
      h = line.split("=")
      a << h
    end
    return a.to_h
  end


end
