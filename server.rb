#=============================================================================
#  Copyright (c) SparseWare. All rights reserved.
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU Affero General Public License as
#  published by the Free Software Foundation, either version 3 of the
#  License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU Affero General Public License for more details.
#
#  You should have received a copy of the GNU Affero General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#=============================================================================


# Place all requires here so that other files
# don't have to worry about require path
require 'kernelex'
require 'const'
require 'sirf'
require 'sirf_utils'
require 'yaml'
require 'json'
require 'optparse'
require 'appnativa.util.jar'
require 'appnativa.util-net.jar'

load File.join(File.dirname(__FILE__), "lib/fm.rb")
load File.join(File.dirname(__FILE__), "lib/broker.rb")
load File.join(File.dirname(__FILE__), "lib/rave.rb")
load File.join(File.dirname(__FILE__), "lib/cachingex.rb")
java.lang.System.setProperty("java.security.auth.login.config","./jaas.config")

def create_rave_app(standalone=true,rack_options=nil)
  file="config.yml"
  if ARGV.length>0 && !ARGV[0].starts_with?("-")
    file=ARGV.shift
  end
  options  = YAML.load_file(File.join(File.dirname(__FILE__), file))

  opts = OptionParser.new
  opts.banner = "Usage: server.rb [config_file] [options]"
  opts.separator ""
  opts.separator "Specific options:"
  opts.on('-v', '--verbose', "Run verbosely")    { Sirf::verbose = true  }
  opts.on_tail("-h", "--help", "Show this message") { output_rave_help(opts) }
  opts.on_tail("--version", "Show version") {output_rave_version}
  opts.on('-b', '--broker BROKER FILE',"Specify a broker config file")    do  |v|
    options['broker_config']=v
  end
  opts.on('-d', '--dir DIRECTORY',"Specify the local directory to serve files from")    do  |v|
    options['local_directory']=v
  end
  opts.on('--prefix PREFIX',"Specify the prefix for the application")    do  |v|
    options['prefix']=v
  end
  opts.on('-m','--module MODULE_PATH',"Specify name that path that identifies the module")    do  |v|
    options['module_path']=v
  end
  opts.parse!(ARGV) rescue output_rave_help(opts)

  options['local_directory']=File.expand_path(options['local_directory']) if options['local_directory']
  file=options['broker_config']
  file="broker.yml" if !file
  file << ".yml" if !file.ends_with?(".yml")
  broker_options  = YAML.load_file(File.join(File.dirname(__FILE__), file))
 
  puts "Trying to establish connection to broker at #{broker_options['host']}:#{broker_options['port']}"
  options['session_manager']=Rave::SessionManager.new(broker_options)
  if options['purge_timeout']
    options['session_manager'].purge_timeout=options['purge_timeout']
    options.delete('purge_timeout')
  end

  app=Rave::Application.new(options)
  #app.setup_site_info(broker_options)
  puts "Using broker at #{broker_options['host']}:#{broker_options['port']}"
  puts "Service path: #{options['prefix']}#{options['module_path'] || options['module_prefix']}/"
  if standalone
    pool_options={}
    if options['http_session_timeout']
      pool_options[:expire_after]=options['http_session_timeout']
      options.delete('http_session_timeout')
    end

    if options['session_domain']
      pool_options[:domain]=options['session_domain']
      options.delete('session_domain')
    end
    pool_options[:httponly]=false #java 1.6 and below can't support this
    if options['memcache_server']
      pool_options[:memcache_server]=options['memcache_server']
      app = Rack::Session::Memcache.new(app,pool_options)
    else
      app = Rack::Session::Pool.new(app,pool_options)
    end
    map={}
    if options['prefix']
      map[options['prefix']]=app
    else
      map['/']=app
    end
    file_url_mappings=options['file_url_mappings']
    if file_url_mappings and !file_url_mappings.empty?
      file_url_mappings.each do |key,value|
        map[key]=Sirf::FileHandler.new(File.expand_path(value))
      end
    end
    if rack_options && options['port']
      rack_options[:Port]=options['port']
    end
    app=Rack::URLMap.new(map)
  end
  return app
end

def output_rave_version
  puts "Rave Server v0.8"
  exit 0
end
def output_rave_help(opts)
  puts opts
  exit
end
def run_rave
  rack_options={}
  app=create_rave_app(true,rack_options)
	Rack::Handler::WEBrick.run(app,rack_options)
end
