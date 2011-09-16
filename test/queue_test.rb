  require 'yaml'
  enc = YAML::load_file(File.join(File.dirname(__FILE__), '..','..', '..', 'railsApps', 'proposalware', 'config', 'encoding_dot_com.yml'))
  require File.join(File.dirname(__FILE__), *%w[.. lib encoding_wrapper.rb])


  video_source = 'http://media.railscasts.com/assets/episodes/videos/272-markdown-with-redcarpet.mp4'

  instance = EncodingWrapper::Queue.new(enc['user_id'], enc['user_key'])

  result = instance.add_media video_source, nil,[{:output => 'thumbnail'}] 
#
#
p result[:media_id]
#
#  sleep 2
#
#  puts instance.request_status(result[:media_id])
#
#  sleep 2
#
#  puts instance.cancel_media(result[:media_id])
