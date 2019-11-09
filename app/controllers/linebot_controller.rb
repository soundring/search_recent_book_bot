class LinebotController < ApplicationController
  require 'line/bot'
  require "json"
  require 'net/https'
  require 'uri'

  protect_from_forgery :except => [:callback]

  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    }
  end

  def callback
    body = request.body.read

    signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(body, signature)
      head :bad_request
    end

    events = client.parse_events_from(body)

    events.each { |event|
      case event
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Text
          str = event.message['text']
          book_url = URI.encode "https://www.googleapis.com/books/v1/volumes?q=#{str}&maxResults=1&orderBy=newest"
          uri = URI.parse(book_url)

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE

          req = Net::HTTP::Get.new(uri.request_uri)
          res = http.request(req)
          json = JSON.parse(res.body)

          release_date = json["items"][0]["volumeInfo"]["publishedDate"]
          title = json["items"][0]["volumeInfo"]["title"]
          image_url = json["items"][0]["volumeInfo"]["imageLinks"]["thumbnail"]
          if image_url.match(/^http:\/\/.*/) then
            image_url = image_url.sub!('http://','https://')
          end
          info_link = json["items"][0]["volumeInfo"]["infoLink"]
          description = json["items"][0]["volumeInfo"]["description"]

          message = {
            type: 'flex',
            altText: 'book',
            contents: {
              type: 'bubble',
              styles: {
                header: {
                  backgroundColor: "#3399FF",
                },
                hero: {
                  separator: true,
                }
              },
              header: {
                type: 'box',
                layout: 'vertical',
                contents: [
                  {
                    type: 'text',
                    text: title,
                    align: 'center',
                    color: '#ffffff',
                    size: 'lg',
                    wrap: true
                  }
                ]
              },
              hero: {
                type: "image",
                url: image_url,
                size: "full",
                aspectRatio: "1.91:1"
              },
              body: {
                type: 'box',
                layout: 'vertical',
                contents: [
                  {
                    type: 'text',
                    text: "#{title} \n \n【あらすじ】 \n #{description} \n \n 発売日: #{release_date}",
                    wrap: true,
                  }
                ]
              },
              footer: {
                type: 'box',
                layout: 'vertical',
                contents: [
                  {
                    type: 'button',
                    style: 'primary',
                    action: {
                      type: 'uri',
                      label: '読みに行く',
                      uri: info_link
                    }
                  }
                ]
              }
            }
          }
          client.reply_message(event['replyToken'], message)
        end
      end
    }

    head :ok
  end
end
