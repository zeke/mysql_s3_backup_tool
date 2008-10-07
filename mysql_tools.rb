require "yaml"
require 'net/smtp'
require 'rubygems'
require 'aws/s3'

DEBUG = false

class MysqlTools
  include AWS::S3
  attr_accessor :config, :hostname
  
  def initialize(action, *args)
    load_config
    @hostname = `hostname`
    connect
    
    case action
    when 'backup'
      backup
    when 'restore'
      restore(*args)
    else
      die self.class.usage
    end
  end # initialize
  
  def backup
    dump_path   = "/tmp/db_backup_#{Time.now.tv_sec}_#{rand}.sql"
    puts "dump_path: #{dump_path}" if DEBUG
    
    puts "Exporting..."
    dump_result = "#{dump_path}.result"
    mysql_password_clause = @config['mysql_password'] ? "-p#{@config['mysql_password']}" : ""
    `mysqldump -v --quick --single-transaction --all-databases -u root #{mysql_password_clause} > #{dump_path} 2> #{dump_result}`
    puts "dump_result: #{File.read(dump_result)}" if DEBUG
    
    puts "Compressing..."
    compress_result = `gzip #{dump_path} 2>&1`
    puts "Compress result: #{compress_result}" if DEBUG
    
    puts "Storing..."
    file_name = "#{@config['folder']}/#{@config['filename']}_#{Time.now.strftime("%Y-%m-%d_%H-%M")}.sql.gz"
    S3Object.store(file_name, open("#{dump_path}.gz"), @config['bucket'])
    
    success = S3Object.exists?(file_name, @config['bucket']) ? "success":"failure"
    mail('backup', success, file_name)
    puts "Done: #{success}"
  end
  
  def restore(filename=nil)
    # get a list of available backups if no filename given
    filename = get_recent_backup if filename.nil?

    # filename might have folder prepended from get_recent_backup
    filename = File.basename(filename)

    # retrieve the file data
    puts "retrieving [#{filename}] ..."
    die "File [#{filename}] not found." if not S3Object.exists?("#{@config['folder']}/#{filename}", @config['bucket'])
    
    open("/tmp/#{filename}", 'wb') do |file|
      S3Object.stream("#{@config['folder']}/#{filename}", @config['bucket']) do |chunk|
        file.write chunk
      end
    end
  
    # extract it (backups are gzipped)
    puts "extracting..."
    `gunzip -f /tmp/#{filename}`
    
    # import it
    puts "importing..."
    `mysql -u root < /tmp/#{filename.sub(/\.gz/, '')}`
    
    puts "done."
  end # restore
  
  def self.usage
    filename = File.basename(__FILE__)
    "
    #{filename}
      - Uses config file ./settings.yml
      
    USAGE:
    #{filename} backup
      - does a mysqldump on localhost, gzips it and stores to S3 in the configured bucket/folder

    #{filename} restore [filename]
      - Must be run from the machine you wish to restore to.
      - gets the latest mysql backup data from S3 and imports it into mysql
      - takes an optional filename argument for a specific backup file from S3 in the configured bucket/folder
        
"
  end
  
  protected
  
  # just a helper to print an error message and exit without resorting to raise
  def die(msg, exit_code=1)
    puts msg
    exit exit_code
  end # die
  
  # finds the most recent backup filename from the last two weeks
  def get_recent_backup
    puts "entered get_recent_backup" if DEBUG
    filename = "#{@config['folder']}/#{@config['filename']}_#{(Time.now - (60*60*24*14)).strftime("%Y-%m-%d_%H-%M")}"
    list = Bucket.objects(@config['bucket'], :prefix => @config['folder'])
    raise 'Could not find any backups.' if not list
    list.sort!{|a,b| b.key <=> a.key }
    raise 'Could not find a recent backup.' if not list.first
    list.first.key
  end # get_recent_backup

  def load_config
    config_file = File.join(File.dirname(__FILE__), "settings.yml")
    @config = YAML.load(File.read(config_file))
    %w(bucket folder filename email smtp_server AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY).each do |setting|
      raise "'#{setting}' is required and missing from the config" if not @config[setting]
    end
  end # load_config  
  
  def mail(action, result, s3_path)
    if result == "failure"
    puts "Mailing..."
    msgstr = "From: mysql_tools_#{result}@elctech.com 
To: #{@config["email"]}
Subject: #{action} #{result} on #{@hostname} 

#{action} #{result} on #{@hostname} at #{Time.now.to_s}:

Location on S3: #{s3_path}
"
    
    begin
      Net::SMTP.start(@config["smtp_server"], 25) do |smtp|
        smtp.send_message msgstr, 'root@localhost', @config["email"]
      end 
    rescue Exception => e
      puts "ERROR: 
      #{e}
      Could not connect to mail server on #{@config["smtp_server"]}"
    end
    puts "Done."
    end
  end # mail
  
  def connect
    AWS::S3::Base.establish_connection!(
      :access_key_id     => @config["AWS_ACCESS_KEY_ID"],
      :secret_access_key => @config["AWS_SECRET_ACCESS_KEY"]
    )
  end
  
end # class MysqlTools

if __FILE__ == $0
  puts MysqlTools::usage if ARGV.size == 0
  MysqlTools.new(ARGV[0], ARGV[1])
end

