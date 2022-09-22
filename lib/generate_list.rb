require 'aws-sdk-s3'
require 'logger'

LOGGER = ::Logger.new( STDOUT ) # :nodoc:

BUCKET = "ekispert-lib"
PREFIX = "yahoo/"
OUT_BUCKET = "yahoo-han-list"
LISTSIZE = 2
OLDLISTSIZE = 10

def exists?(client, bucket, key)
  client.head_object(
    bucket: bucket,
    key: key
  )
  true
rescue StandardError
  false
end

def run(event:,context:)
  client = Aws::S3::Client.new
  options = {bucket: BUCKET,  prefix: "yahoo/"}
  files = []
  # list_objects_v2 は 1000件を超えるとページネイトが必要
  loop do
    object_list = client.list_objects_v2(options)
    object_list.contents.each do |object|
      # マッチ例："transitwar.linux-x86_64.202209_01.20220822104038.tar.gz"
      file = []
      match_data = object.key.sub(PREFIX, "").match(/transitwar.linux-x86_64.([0-9]{6})_([0-9]{2}).([0-9]{14}).tar.gz/)  
      unless match_data.nil?
        # 要素1 ファイル名
        file << match_data[0]
        # 要素2 YYYYMMDD , 版番号 , YYYYMMDDhhmmss を連結した文字列
        file << match_data[1].to_s +  match_data[2].to_s + match_data[3].to_s
        files << file
      end
    end
    options[:continuation_token] = object_list.next_continuation_token
    break unless object_list.next_continuation_token
  end
  # 最新のファイルが先頭にくるように並べ替え
  files2 = files.sort{|a, b| b[1].to_i <=> a[1].to_i}
  if files2.size > 0
    new_package = files2[0][0]
    target_obj = "list.txt"
    out_client = Aws::S3::Client.new()
    # 書き込み
    list = []
    add_old_list = []
    if exists?(out_client, OUT_BUCKET, target_obj)
      obj = out_client.get_object(bucket: OUT_BUCKET, key: target_obj)
      list = obj.body.read.split("\n")
    end
    if list.first != new_package
      list.unshift new_package
      pop_count = list.size - LISTSIZE
      pop_count.times do |num|
        add_old_list << list.pop
      end
      out_client.put_object(
        bucket: OUT_BUCKET,
        key: target_obj,
        body: list.join("\n")
      ) 
      LOGGER.info("list"+list.to_s)
    end

    if add_old_list.size > 0
      old_list_obj = "old.txt"
      old_list = []
      if exists?(out_client, OUT_BUCKET, old_list_obj)
        obj = out_client.get_object(bucket: OUT_BUCKET, key: old_list_obj)
        old_list = obj.body.read.split("\n")
      end
      add_old_list.each do |elm|
        old_list.unshift elm
      end
      old_list.slice!(OLDLISTSIZE, old_list.size-OLDLISTSIZE) if old_list.size > OLDLISTSIZE
      out_client.put_object(
        bucket: OUT_BUCKET,
        key: old_list_obj,
        body: old_list.join("\n")
      ) 
      LOGGER.info("old_list"+old_list.to_s)
    end
  end
end

