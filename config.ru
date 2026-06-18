require 'rack'
require 'rubygems'
require 'bundler'
require './app'
use Rack::Reloader

app = Rack::Builder.new do
  map "/" do
    run App.new
  end

  map "/chat" do
    run ChatApp.new
  end

end

run app
