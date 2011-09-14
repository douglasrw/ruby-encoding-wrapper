require 'rubygems'
require 'uri'
require 'net/http'
require 'nokogiri'
require 'rexml/document'


module EncodingWrapper

  module Actions
    ADD_MEDIA       = "AddMedia"
    UPDATE_MEDIA    = "UpdateMedia"
    CANCEL_MEDIA    = "CancelMedia"
    GET_STATUS      = "GetStatus"
    GET_MEDIA_LIST  = "GetMediaList"
    GET_MEDIA_INFO  = "GetMediaInfo"
  end


  module StatusType
    NEW             = "New"
    WAITING         = "Waiting for encoder"
    PROCESSING      = "Processing"
    SAVING          = "Saving"
    FINISHED        = "Finished"
    ERROR           = "Error"
    DELETED         = "Deleted"
    DOWNLOADING_NEW = "DownloadingNew"
  end

  class Queue
    attr_reader :user_id, :user_key


    def initialize(user_id=nil, user_key=nil, url=nil)
      @user_id = user_id
      @user_key = user_key
      @url = url || 'http://manage.encoding.com/'
      @log = Logger.new(STDOUT)
    end


      # format fields:
      #   output (required):
      #     flv, fl9, wmv, 3gp, mp4, m4v, ipod, iphone, ipad, android, ogg, webm, appletv, psp, zune, mp3, wma,
      #     m4a, thumbnail, image,
      #     mpeg2 (just experimental feature, please use with care, feedback is welcome),
      #     iphone_stream, ipad_stream, muxer
    def request_encoding(action=nil, source=nil, notify_url=nil)
      # :size, :bitrate, :audio_bitrate, :audio_sample_rate,
      # :audio_channels_number, :framerate, :two_pass, :cbr,
      # :deinterlacing, :destination, :add_meta

      xml = Nokogiri::XML::Builder.new do |q|
        q.query {
          q.userid  @user_id
          q.userkey @user_key
          q.action  action
          q.source  source
          q.notify  notify_url
          q.format  { |f| yield f }
        }
      end.to_xml

      response = request_send(xml)

      @log.info "response.class = #{response.class}\n"
      @log.info response
      
      if response.css('errors error').length != 0
        message = response.css('errors error').text
      else
        message = response.css('response message').text
        media_id = response.css('MediaID').text
      end

      {
        :message => message,
        :media_id => media_id
      }

    end


    def request_status(media_id)
      xml = Nokogiri::XML::Builder.new do |q|
        q.query {
          q.userid    @user_id
          q.userkey   @user_key
          q.action    EncodingWrapper::Actions::GET_STATUS
          q.mediaid   media_id
        }
      end.to_xml

      response = request_send(xml)

      response[:status] = false
      response[:progress] = false

      if response[:errors].length == 0
        response[:status] = response[:xml].css('status').text
        response[:progress] = response[:xml].css('progress').text.to_i

        # there is a bug where the progress reports
        # as 100% if the status is 'Waiting for encoder'
        if (response[:status] == EncodingWrapper::StatusType::WAITING)
          response[:progress] = 0
        end
      end

      response
    end


    def cancel_media(media_id)
      xml = Nokogiri::XML::Builder.new do |q|
        q.query {
          q.userid    @user_id
          q.userkey   @user_key
          q.action    EncodingWrapper::Actions::CANCEL_MEDIA
          q.mediaid   media_id
        }
      end.to_xml

      response = request_send(xml)
    end


      # format fields:
      #   output (required):
      #     flv, fl9, wmv, 3gp, mp4, m4v, ipod, iphone, ipad, android, ogg, webm, appletv, psp, zune, mp3, wma,
      #     m4a, thumbnail, image,
      #     mpeg2 (just experimental feature, please use with care, feedback is welcome),
      #     iphone_stream, ipad_stream, muxer
    def add_media(source=nil, notify_url=nil, formats=nil)
      # :size, :bitrate, :audio_bitrate, :audio_sample_rate,
      # :audio_channels_number, :framerate, :two_pass, :cbr,
      # :deinterlacing, :destination, :add_meta

      xml = Nokogiri::XML::Builder.new do |q|
        q.query {
          q.userid      @user_id
          q.userkey     @user_key
          q.action      EncodingWrapper::Actions::ADD_MEDIA
          q.source      source
          q.notify      notify_url
          formats.each_value {|format|
            q.format {
              format.each {|option, value|
                q.send(option, value)
              }
            }
          }
        }
      end.to_xml

      # @log.info xml
      # @log.info "\n\n"
      
      response = request_send(xml)

      # @log.info response

      response[:media_id] = false
      
      if response[:errors].length == 0
        response[:media_id] = response[:xml].css('MediaID').text
      end

      response
    end

    def media_add(source=nil, notify_url=nil)
      add_media(source, notify_url)
    end

    def media_cancel(media_id)
      cancel_media(media_id)
    end

    def media_status(media_id)
      request_status(media_id)
    end

    def media_list
      xml = Nokogiri::XML::Builder.new do |q|
        q.query {
          q.userid    @user_id
          q.userkey   @user_key
          q.action    EncodingWrapper::Actions::GET_MEDIA_LIST
        }
      end.to_xml

      response = request_send(xml)

      response[:list] = []

      media_list = response[':xml'].css('response media')

      media_list.each do |media|
        obj = {}

        fields = media.css('*')
        fields.each do |field|
          obj[field.name.to_sym] = field.text
        end

        response[:list] << obj
      end

      response
    end


    private

    def build_query(action)
      query = Nokogiri::XML::Builder.new do |q|
        q.query {
          q.userid  @user_id
          q.userkey @user_key
          q.action  action
          yield q if block_given?
        }
      end.to_xml
    end


    def request_send(xml)
      url = URI.parse(@url)
      request = Net::HTTP::Post.new(url.path)
      request.form_data = { :xml => xml }
      response = Net::HTTP.new(url.host, url.port).start { |http|
        http.request(request)
      }

      output = {:errors => [], :status => false, :xml => '', :message => ''}
      output[:xml] = Nokogiri::XML(response.body)

      if output[:xml].try(:css) && output[:xml].css('errors error').length != 0
        output[:xml].css('errors error').each { |error| output[:errors] << error.text }
      else
        output[:status] = true
      end

      if output[:xml].try(:css) && output[:xml].css('response message').length == 1
        output[:message] = output[:xml].css('response message').text
      end

      output
    end

  end
end
