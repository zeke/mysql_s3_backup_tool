require 'rubygems'
require 'yaml'

class MysqlQuickdump
  attr_accessor :config, :hostname
  
  def initialize(db_to_dump, *args)
    die self.class.usage if db_to_dump.nil?
    load_config
    backup db_to_dump
  end # initialize
  
  def backup(db)
    dump_path = "./#{db}_#{Time.now.tv_sec}_#{rand}.sql"
    
    puts "Exporting..."
    dump_result = "#{dump_path}.result"
    mysql_password_clause = @config['mysql_password'] ? "-p#{@config['mysql_password']}" : ""
    `mysqldump -uroot #{mysql_password_clause} > #{dump_path} 2> #{dump_result}`
    
    puts "Compressing..."
    compress_result = `gzip #{dump_path} 2>&1`
    
    puts "Done"
  end

  
  def self.usage
    filename = File.basename(__FILE__)
    "
    #{filename}
      - Uses config file ./settings.yml
      
    USAGE:
    #{filename} db_to_dump
      - does a mysqldump of the specified database and gzips it to the folder containing the script.

"
  end
  
  protected
  
  # just a helper to print an error message and exit without resorting to raise
  def die(msg, exit_code=1)
    puts msg
    exit exit_code
  end # die

  def load_config
    config_file = File.join(File.dirname(__FILE__), "settings.yml")
    @config = YAML.load(File.read(config_file))
    %w(bucket folder filename email smtp_server AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY).each do |setting|
      raise "'#{setting}' is required and missing from the config" if not @config[setting]
    end
  end # load_config
  
end # class MysqlTools

if __FILE__ == $0
  puts MysqlQuickdump::usage if ARGV.size == 0
  # MysqlQuickdump.new(ARGV[0], ARGV[1])
end






