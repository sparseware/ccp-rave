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


# =============================================================================
#
# SIRF is a Simple Ruby Framework geared towards building RESTful applications.
# SIRF leaves most of the architectural
# decisions up to the developer. It purpose if to provide a minimal framework
# necessary to get started. It provides basic session management, static and
# dynamic file serving (using Erubis) and module management. The module manager
# maps urls to Ruby module/class combinations and loads the appropriate class
# to handle the url. SIRF leverages Ruby Rack (http://rack.rubyforge.org) to
# support Web server plug-n-play
# 
# @version 2.0
# @author Don DeCoteau
# =============================================================================
module Sirf
  
  require "thread"
  require 'rack'
  require 'erubis'
  require 'const'

  RESPONSE_HEADER         = "response.header".freeze
  SESSION                 = "application.session".freeze
  RACK_SESSION            = "rack.session".freeze
  QUERY_STRING            = "QUERY_STRING".freeze
  RESPONSE_CONTENT_LENGTH = "Content-Length".freeze
  RACK_INPUT              = "rack.input".freeze
  @verbose=false

  def Sirf.verbose
    @verbose
  end
  def Sirf.verbose=(value)
    @verbose=value
  end
  
  #load mime types
  mt=YAML.load_file(File.join(File.dirname(__FILE__), "mime_types.yml")) rescue {}
  mt.each do |key,value|
    Rack::Mime::MIME_TYPES[key.to_s[1..-1]]=value
  end

  # =============================================================================
  # This class is a Rack application that can be used as a base for build
  # Sirf applications. It supports dynamic modules as well dynamic parsing
  # of html html (.rhtml extension) and sdf (.rsdf) files with embedded ruby code.
  # =============================================================================
  class Application
    Rack::Mime::MIME_TYPES["rhtml"]="text/html"

    def initialize(options)
      @file_handler=nil
      @module_file_directories=nil
      @erubis_handler=nil
      @port              = options['port']
      @session_manager   = options['session_manager']
      @local_directory   = options['local_directory']
      @default_type      = options['default_content_type'] || "text/plain"
      @module_prefix     = options['module_directory'] || "module"
      @module_path       = options['module_path'] || @module_prefix
      @prefix            = options['prefix'] || '/'
      @special_auth      = options['use_special_auth'] || false
      @http_auth_code    = options['http_aut_status_code'] || 401

      @root_url      ="/"

      cache         = options['cache_modules'] || true
      monitor       = options['monitor_files'] || true
      freq          = options['file_monitor_frequency'] || 30
      additional_files=options['additional_files_to_monitor']
      mname=options['ruby_module_name']
      @module_manager=ModuleManager.new(self,@local_directory+@root_url+@module_prefix,mname,freq,monitor,cache,additional_files)

      @default_type.freeze
      @module_prefix.freeze
      @root_url.freeze

      @file_handler=FileHandler.new(@local_directory,@default_type)
      
       @service_path="#{options['prefix']}#{options['module_path'] || options['module_prefix']}/"
       @service_path.freeze;
      add_erubis_mime_type(".rhtml","text/html")
      erubis=options['erubis_types']
      if erubis
        erubis.each { |key,value| add_erubis_mime_type(key,value) }
      end

      file_dirs=options['module_file_directories']
      if file_dirs
        file_dirs.each { |dir| add_module_file_directory(dir) }
      end

      mime=options['additional_mime_types']
      if mime
        mime.each { |key,value| add_mime_type(key,value) }
      end
    end
    
    # =============================================================================
    # Returns prefix that specifies that an incoming request for and application module
    # and not for a static file
    # =============================================================================
    def get_module_prefix
      return @module_prefix
    end
    
    # =============================================================================
    # Returns prefix that clients use to access application modules
    # =============================================================================
    def get_service_path
      return @service_path
    end
    # =============================================================================
    # Returns the port that the app was configured  to run on
    # This is only valid when running in standalone mode (i.e. some other tool is 
    # not responsible for starting the app)
    # =============================================================================
    def get_port
      return @port
    end
    # =============================================================================
    # Returns whether a special authorization should be used for HTTP 401 errors
    # Using a special authorization type ensures that you can handle the 
    # authorization in code on the client side
    # =============================================================================
    def use_special_auth
      return @special_auth
    end
    
    # =============================================================================
    # Returns the the authorization code to return when authentication is needed 
    # (defaults the to 401). Using a special authorization code ensures that you
    # can handle the authorization in code on the client side
    # =============================================================================
    def http_auth_status
      return @http_auth_code
    end
    
    # =============================================================================
    # Adds a directory that is allowed to contain module files.
    # Only files in specified directories can be served
    # =============================================================================
    def add_module_file_directory(name)
      @module_file_directories={} if !@module_file_directories
      @module_file_directories[name]=nil
    end
    
    # =============================================================================
    # Returns the module that handles the specified path
    # =============================================================================
    def get_module_for(path)
      a=@module_manager.load_module(path.split('/'))
      return a ? a[0] : nil
    end

    # =============================================================================
    # Adds a new mime type/file extension mapping
    # =============================================================================
    def add_mime_type(ext,type)
      dot_at=ext.rindex '.'
      ext=ext[dot_at+1..-1] if dot_at
      Rack::Mime::MIME_TYPES[ext]=type
    end
    
    # =============================================================================
    # Adds a new erubis type/file extension mapping
    # =============================================================================
    def add_erubis_mime_type(ext,type)
      @erubis_handler=ErubisHandler.new(@local_directory) if !@erubis_handler
      dot_at=ext.rindex '.'
      ext=ext[dot_at+1..-1] if dot_at
      Rack::Mime::MIME_TYPES[ext]=type
      @file_handler.add_handler(ext,@erubis_handler)
    end
    
    def call(env)
      path=Rack::Utils::unescape(env[Sirf::Const::PATH_INFO])
      if Sirf.verbose
        fpath = path.dup
        fpath << "?" << env["QUERY_STRING"].to_s  unless env["QUERY_STRING"].to_s.empty?
        puts fpath
      end
      env[Sirf::Const::SCRIPT_NAME]=path if !env[Sirf::Const::SCRIPT_NAME]
      paths=path.split(/\//)
      paths.shift #remove empty string before first slash
      len=paths.length
      if len<1
        return [404,{},[Sirf::Const::ERROR_404_RESPONSE]]
      end
      env[SESSION]=@session_manager.get_session(self,env,env[RACK_SESSION]) if @session_manager
      if is_module_path?(paths)
        a=@module_manager.load_module(paths)
        if a
          m=a[0]
          paths=a[1]
        else
          sub=paths.shift
          if @module_file_directories and @module_file_directories.has_key?(sub)
            return handle_file(env)
          end
        end
        if m
          begin
            out=m.service(self,env,paths)
            out[1][Sirf::Const::CONTENT_TYPE]=@default_type if !out[1][Sirf::Const::CONTENT_TYPE]
            return out
          end
        end
        return handle_not_found(env)
      end
      handle_file(env)
    end

    def is_module_path?(paths)
      return paths.shift==@module_path
    end
    
    # =============================================================================
    # Checks if the file specified file can be served up
    # 
    # @return the normalized path to the file if it can be served; nil if it can't
    # =============================================================================
    def can_serve(file,expiration=-1)
      file="#{@module_prefix}#{file}" if file && file.starts_with?("/")
      return @file_handler.can_serve(file,expiration)
    end
    
    
    # =============================================================================
    # Checks if the file specified file can be written to
    # 
    # @return the normalized path to the file if it can be written to; nil if it cant
    # =============================================================================
    def can_write(file)
      file="#{@module_prefix}#{file}" if file && file.starts_with?("/")
      return @file_handler.can_write(file)
    end

    # =============================================================================
    # Generates a 404- NOT FOUND response
    # =============================================================================
    def handle_not_found(env)
      return [404,{},[Sirf::Const::ERROR_404_RESPONSE]]
    end
    
    # =============================================================================
    # Removes the specified session from the session manager
    # =============================================================================
    def remove_session(session)
      @session_manager.remove_session(session) if @session_manager
    end
    
    # =============================================================================
    #  Finds a session containing a specific value
    #  
    #  @param key the key
    #  @param value the value
    # =============================================================================
    def find_session_with_value(key,value)
      return @session_manager.find_session_with_value(key,value)
    end
    
    # =============================================================================
    # Sets the session object into the specified Rack environment object
    # =============================================================================
    def set_session(env)
      env[SESSION]=@session_manager.get_session(self,env,env[RACK_SESSION]) if @session_manager
    end
    
    # =============================================================================
    # Returns the base path for modules
    # =============================================================================
    def module_base_path
      path="/"
      path << @module_prefix
      path << "/"
    end
    
    # =============================================================================
    # Handles the sending of a file that is stored relative to a specific module
    # =============================================================================
    def send_module_file(module_name,file_name,env)
      env[Sirf::Const::PATH_INFO]=module_base_path+module_name+"/"+file_name
      handle_file(env)
    end
    # =============================================================================
    # Handles the sending of the specified file
    # =============================================================================
    def handle_file(env)
      @file_handler.call(env)
    end
  end

  # =============================================================================
  # This class manages application modules.
  # It loads and instantiates module classes and can automatically
  # Manage the reloading of modules when the moduleâ€™s source file changes
  # =============================================================================
  class ModuleManager
    def initialize(app,root,module_name=nil,fm_frequency=30, monitor=true, cache=false,addition_files=nil)
      @app=app
      @module_cache = {}
      @file_modified_time = {}
      @file_monitor_thread=nil
      @stop_file_monitor=false
      @file_load_mutex=Mutex.new
      @file_monitor_freq=fm_frequency
      @monitor=monitor
      @cache=cache
      @root=root
      @addition_files=nil
      @module_name= module_name ? module_name : ""
      if addition_files
        @addition_files=addition_files.dup
        addition_files.each do |file|
          file=(@root+'/'+file)
          @file_modified_time[file]=File.mtime(file)
        end
      end
    end
    
    # =============================================================================
    # Takes the requested url path segments and load the appropriate ruby file and instantiates
    # the the appropriate object to handle the request
    # =============================================================================
    def load_module(paths)
      npaths=Array.new()
      file=nil
      while(p=paths.pop)
        npaths.unshift(p)
        s=""
        s << @root << "/" << paths.join('/') << ".rb"
        if @file_modified_time[file] || File.exists?(s)
          file=s
          break
        end
      end
      return nil unless file
      file.squeeze!('/')
      depth=0
      cn=paths.pop().capitalize_first
      name=@module_name.dup
      while(p=paths.shift)
        p=p.capitalize_first
        name << "::" unless name==""
        name << p
        depth+=1
      end
      name << "::" unless name==""
      name << cn
      time=@file_modified_time[file]
      unless time
        begin
         load_new_file(file)
        rescue Exception=> e
          print "load/reload of '#{file}' failed... #{e.message}\n  #{e.backtrace * "\n  "}\n"
          return nil
        end
      end

      obj=@module_cache[name] if @cache && time && time==@file_modified_time[file]
      if Sirf::verbose
        print "loaded module #{name}' from cache\n" if obj
        print "creating new module #{name}\n" if !obj
      end
      obj=eval(name+".new") if !obj
      obj.set_app(@app)
      @module_cache[name]=obj if @cache
      return [obj,npaths]
    end
    
    protected
    def is_module_available(file)
      return true if @file_modified_time[file]
      return false unless  File.exists?(file)
      begin
        return load_new_file(file)
      rescue Exception=> e
        print "load/reload of '#{file}' failed... #{e.message}\n  #{e.backtrace * "\n  "}\n"
        return false
      end
    end
    protected
    def load_new_file(file)
      @file_load_mutex.synchronize do
        return true if @file_modified_time[file] #do the check incase another thread already loaded
        load(file)
        files=@file_modified_time.dup
        files[file]=File.mtime(file)
        @file_modified_time=files
        check_file_notification_starter()
        return true;
      end
    end
    def load_non_module_file(file)
      load(file)
      @file_modified_time[file]=File.mtime(file)
    end
    def stop_monitor(kill=false)
      @stop_file_monitor=true
      if kill and @file_monitor_thread
        Thread.kill(@file_monitor_thread)
        @file_monitor_thread=nil
      end
    end
    def check_file_modifications
      files=@file_modified_time.dup
      changed={}
      changed_non_module_file=false
      files.each do |file,time|
        begin
          if(File.mtime(file)!=time)
            changed[file] = time
            changed_non_module_file=true if @addition_files and @addition_files.include?(file)
          end
        rescue
          changed[file]=nil
        end
      end
      if changed.size>0
        @file_load_mutex.synchronize do
          files=@file_modified_time.dup
          changed.each do |file,time|
            if time==nil
              files.delete(file)
            else
              files[file]=nil
            end
          end
          @file_modified_time=files
        end
      end
      if(changed_non_module_file)
        Thread.new do
          @addition_files.each do |file|
            if @file_modified_time[file]==nil
              load_non_module_file(file)
            end
          end
        end
      end
    end

    private
    def check_file_notification_starter()
      if @monitor and !@file_monitor_thread
        @file_monitor_thread=Thread.new do
          while true do
            sleep(@file_monitor_freq)
            check_file_modifications()
            if(@stop_file_monitor)
              @file_monitor_thread=nil
              return
            end
          end
        end
      end
    end
  end

  # =============================================================================
  # A session object that holds in-memory data
  # for an http sesson
  # =============================================================================
  class Session
    attr_reader :marker, :last_access
    def initialize()
      @marker=Time.now  #use of time is ok because it is use in combination with Object.id
      @last_access=@marker

    end
    def [](key)
      @params={} if !@params
      @params[key]
    end

    def []=(key,val)
      @params={} if !@params
      @params[key] = val
    end

    #=============================================================================
    # Timestamps the session
    #=============================================================================
    def timestamp()
      @last_access=Time.now
    end
    
    #=============================================================================
    # Returns the last time the session was accessed
    #=============================================================================
    def last_access
      @last_access
    end
    
    #=============================================================================
    # Called after a request has been processed
    # Sub-classes can use this to do post-processing cleanup
    #=============================================================================
    def cleanup
         
    end
    #=============================================================================
    # Called when the session is disposed
    #=============================================================================
    def dispose
         
    end
    #=============================================================================
    # Get the id of the session.
    # This is the id that the session manager uses to track sessions
    #=============================================================================
    def get_id
      return object_id
    end
  end

  # =============================================================================
  # A base class for modules
  # The application will call the service method which
  # sets up the default environment for rack services
  # and then calls the process method on the module
  # =============================================================================
  class ModuleBase
    @app=nil
    def service(app,env,paths)
      @app=app
      begin
        conn=create_connection(app,env,paths)
        sess=env[SESSION]
        sess=check_auth(sess,conn,paths)
        process(sess,conn,paths)
        return conn.full_response if conn.full_response
        conn.finish_body()
        body=conn.response_body
        body=[body] unless body.respond_to?(:each)
        [200,conn.response_header,body]
      rescue HTTPException =>e
        if e.status==401
          s=env['HTTP_XAJAX_AUTH']
          if(app.use_special_auth==true || s=="true")
            e.header["WWW-Authenticate"]='XAjax-'+e.header["WWW-Authenticate"] if s!="false"
          end
          e.status=app.http_auth_status
        end
        body=e.message
        body=[body] unless body.respond_to?(:each)
        [e.status,e.header,body]
      rescue com.appnativa.util.net.HTTPException=> e
        begin
          cause=e.cause
          msg=e.message
          msg="Unauthorized" if cause.statusCode==401
          return [cause.statusCode,{},[msg]]
        rescue
          print "#{e.message}\n  #{e.backtrace * "\n  "}\n"
          return [500,{},["Internal Server Error"]]
        end
      rescue Exception=> e
        print "#{e.message}\n  #{e.backtrace * "\n  "}\n"
        return [500,{},["Internal Server Error"]]
      ensure
        sess.cleanup if sess
        log_completion(sess,env) if sess && Sirf.verbose
      end
    end
    def app
      @app
    end
    def set_app(app)
      @strings=app.get_option("application_strings")
      @app=app
    end
    
    # =============================================================================
    # Creates an returns a new Connection object
    # =============================================================================
    def create_connection(app,env,paths)
      Connection.new(app,env,{},StringIO.new)
    end
    
    # =============================================================================
    # Check the authorization of the user the session belongs to
    # Sub-classes override this method to perform custom authorization checks.
    # This version does nothing
    # =============================================================================
    def check_auth(session,conn,paths)
      return session
    end
    
    # =============================================================================
    # Processes an erubis file
    # 
    # @param session the session object (becomes part of the binding scope for use in the template)
    # @param map the a map of values (becomes part of the binding scope for use in the template)
    # @param file the erubis file
    # =============================================================================
    def erubis(session,map,file)
      file=@app.can_serve(file)
      erb=Erubis::Eruby.new(open(file){|io| io.read })
      Module.new.module_eval{
        return erb.result(binding())
      }
    end
    
    # =============================================================================
    # Process the incoming request by calling the method on this object that corresponds
    # to the name specified in the first path element
    # Sub-classes can override this method to perform pre-procession or to change the
    # signature of the method request
    # =============================================================================
    def process(session,conn,paths)
      if !paths.empty? &&  respond_to?(paths.first.to_sym)
        self.send(paths.shift.to_sym,session,conn,paths)
      else
        not_found
      end
    end
    
    private
    def log_completion(session,env)
      begin
        fpath=Rack::Utils::unescape(env[Sirf::Const::PATH_INFO])
        fpath << "?" << env["QUERY_STRING"].to_s  unless env["QUERY_STRING"].to_s.empty?
        puts "#{fpath} processed for #{session.object_id}"
      rescue Exception
      end
    end
  end
  
  # =============================================================================
  # This class encapsulates a client connection and provides convenience
  # functions for responding to a request
  # =============================================================================
  class Connection < Rack::Request
    attr_accessor :full_response
    @full_response=nil
    
    # =============================================================================
    # Initializes the connection
    # 
    # @param app the calling application
    # @param env the Rack environment
    # @param header an hash object to use to store the response header
    # @param body an IO object to use to store the response body
    # =============================================================================
    def initialize(app,env,header,body)
      super env
      @app=app
      @response_header=header
      @response_body=body
      @user =nil
      @password=nil
      @domain=nil
      @boundary=nil
      @preamble_sent=false
      if env["HTTP_AUTHORIZATION"]
        auth = Rack::Auth::Basic::Request.new(env)
        env['REMOTE_USER'] = auth.username
        @user=auth.username
        if @user
          at_at=@user.index '@'
          if at_at
            @domain=@user[at_at+1..-1]
            @user=@user[0..at_at-1]
          end
        end
        @password=auth.credentials[1]
      end
    end
    
    # =============================================================================
    # Performs URI escaping 
    # =============================================================================
    def escape(s)
      Rack::Utils::escape(s)
    end
    
    # =============================================================================
    # Unescapes a URI escaped string
    # =============================================================================
    def unescape(s)
      Rack::Utils::unescape(s)
    end
    
    # =============================================================================
    # Returns the response header
    # =============================================================================
    def response_header
      @response_header
    end
    
    # =============================================================================
    # Returns a handle to the application that the connection is for
    # =============================================================================
    def app
      @app
    end
    
    # =============================================================================
    # Returns the response body
    # =============================================================================
    def response_body
      @response_body
    end
    
    # =============================================================================
    # Adds list of arguments to the response body using a linefeed as a separator
    # =============================================================================
    def puts(*arg)
      @response_body << arg.join("\n") << "\n"
    end

    # =============================================================================
    # Adds list of arguments (without a linefeed) to the response body
    # =============================================================================
    def put(*arg)
      arg.each { |str|  @response_body << (str || "")}
    end
    
    # =============================================================================
    # Adds the specified string (without a linefeed) to the response body
    # =============================================================================
    def print(str=nil)
      @response_body << str || ""
    end
    
    # =============================================================================
    # Returns the username extracted from an specified HTTP Authorization header
    # =============================================================================
    def username
      return @user
    end
    
    # =============================================================================
    # Returns the password extracted from an specified HTTP Authorization header
    # =============================================================================
    def password
      return @password
    end
    
    # =============================================================================
    # Returns the domain extracted from an specified HTTP Authorization header
    # =============================================================================
    def domain
      return @domain
    end
    
    # =============================================================================
    # Returns the Rack HTTP session object
    # =============================================================================
    def http_session
      @env['rack.session']
    end
    
    # =============================================================================
    # Returns the HTTP Accept header
    # =============================================================================
    def http_accept
      @env['HTTP_ACCEPT']
    end

    # =============================================================================
    # Returns the HTTP User-Agent header
    # =============================================================================
    def http_user_agent
      @env['HTTP_USER_AGENT']
    end
    # =============================================================================
    # Handles the sending of a file that is stored relative to a specific module
    # =============================================================================
    def send_module_file(module_name,file_name)
      @full_response=@app.send_module_file(module_name,file_name,@env)
    end
    
    # =============================================================================
    # Returns whether of not the content-type header has been set
    # =============================================================================
    def is_response_content_type_set?()
      @response_header[Sirf::Const::CONTENT_TYPE]!=nil
    end
    
    # =============================================================================
    # Set the content-type header
    # 
    # @param type the mime type to set the header to
    # =============================================================================
    def set_content_type(type)
      if @boundary
        self.put("\r\n--",@boundary,"\r\n")
        self.put(Sirf::Const::CONTENT_TYPE,": ",type,"\r\n")
      else
        @response_header[Sirf::Const::CONTENT_TYPE] =type
      end
    end
    
    # =============================================================================
    # Sets the framework specific X-Paging-Next header
    # =============================================================================
    def set_paging_next_header(value)
      if @boundary
        self.put("X-Paging-Next: ",value,"\r\n")
      else
        @response_header["X-Paging-Next"] =value
      end
    end
    
    # =============================================================================
    # Sets the framework specific X-Paging-Previous header
    # =============================================================================
    def set_paging_previous_header(value)
      if @boundary
        self.put("X-Paging-Previous: ",value,"\r\n")
      else
        @response_header["X-Paging-Previous"] =value
      end
    end
    
    # =============================================================================
    # Sets the framework specific X-Paging-Has-More header
    # =============================================================================
    def set_paging_has_more_header(value)
      if @boundary
        self.put("X-Paging-Has-More: ",value,"\r\n")
      else
        @response_header["X-Paging-Has-More"] =value
      end
    end
    
    # =============================================================================
    # Sets the framework specific X-Link-Info header
    # =============================================================================
    def set_link_info_header(value)
      if @boundary
        self.put("X-Link-Info: ",value,"\r\n")
      else
        @response_header["X-Link-Info"] =value
      end
    end
    
    # =============================================================================
    # Sets an HTTP header
    # =============================================================================
    def set_header(name,value)
      if @boundary
        self.put(name,": ",value,"\r\n")
      else
        @response_header[name] =value
      end
    end
    # =============================================================================
    # Called to do any post processing on the response header.
    # 
    # =============================================================================
    def finish_header
      if @boundary
        self.puts
      end
    end
    
    # =============================================================================
    # Called to do any post processing on the response body
    # =============================================================================
    def finish_body
      if @response_body.length()>0
        self.put("\r\n--",@boundary,"--\r\n") if @boundary
      else
        @response_header[Sirf::Const::CONTENT_TYPE] ="text/plain"
      end
    end
    
    # =============================================================================
    # Set the content-type header to application/json
    # =============================================================================
    def mime_json()
      set_content_type 'application/json'
    end
    
    # =============================================================================
    # Set the content-type header to text/xml
    # =============================================================================
    def mime_xml()
      set_content_type 'text/xml'
    end

    # =============================================================================
    # Set the content-type header
    # 
    # @param mime the mime type to set the header to
    # =============================================================================
    def mime(mime)
      set_content_type mime
    end
    
    # =============================================================================
    # Set the content-type header to multipart/mixed
    # 
    # @param boundary the content boundary
    # =============================================================================
    def mime_multipart(boundary="__FF00_SIRF_MULTIPART_BOUNDARY_PART_OOFF__")
      set_header("MIME-version","1.0")
      set_content_type "multipart/mixed; boundary=\""+boundary+"\""
      @boundary=boundary
    end
    
    # =============================================================================
    # Set the content-type header to text/plain
    # =============================================================================
    def mime_text()
      set_content_type 'text/plain'
    end

    # =============================================================================
    # Set the content-type header to text/html
    # =============================================================================
    def mime_html()
      set_content_type 'text/html'
    end
    
    # =============================================================================
    # Set the content-type header to text/html
    # =============================================================================
    def mime_html8()
      set_content_type 'text/html; charset=utf-8'
    end
    # =============================================================================
    # Set the content-type header to text/x-sdf
    # =============================================================================
    def mime_sdf(extra=false)
      if extra
        set_content_type 'text/x-sdf;extraData=true'
      else
        set_content_type 'text/x-sdf'
      end
    end
  end
  
  # =============================================================================
  # This class provides a rack-style body that can efficiently
  # send a file
  # =============================================================================
  class RackFileBody
    attr_reader :size, :path
    attr_writer :size, :path
    def initialize(path,size=nil)
      @path = path
      @size = size
    end
    def sirf_sendfile(response)
      @size=F.size(@path).to_s if !@size
      small=@size < Sirf::Const::CHUNK_SIZE * 2
      response.send_status(@size)  #content-length already set
      response.send_header
      response.send_file(@path,small)
    end
    def each
      File.open(@path, "rb") do |f|
        while chunk = f.read(Sirf::Const::CHUNK_SIZE) and chunk.length > 0
          begin
            yield chunk
          rescue Object => exc
            break
          end
        end
      end
    end
  end


  # =============================================================================
  # This class is a file handler a rack-style body.
  # Portions of the code are from Mongrel::DirHandler
  # This handler also supports adding custom handlers for specific file extensions
  # =============================================================================
  class FileHandler < Rack::File
    def initialize(root,default_type='text/plain')
      @root                 = File.expand_path(root)
      @handlers             = nil
      @default_content_type = default_type
    end
    
    # =============================================================================
    # Adds a file handler that will handle files of the specified extension
    # =============================================================================
   
    def add_handler(ext,handler)
      @handlers     = {} if !@handlers
      @handlers[ext] = handler
    end
    
    # =============================================================================
    # Checks if the file specified by the passed in path info can be served up
    # 
    # @return the normalized path to the file if it can be served; nil if it can't
    # =============================================================================
    def can_serve(path_info,expiration=-1)
      return nil if path_info.include? ".."
      req_path = Rack::Utils.unescape(path_info)
      # Add the drive letter or root path
      req_path = File.join(@root, req_path)
      req_path = File.expand_path req_path
      if File.exist? req_path and (!@root or req_path.index(@root) == 0)
        # It exists and it's in the right location
        if File.directory? req_path
          # Do not serve anything
          return nil
        else
          # It's a file and it's there
          if expiration>0
            return nil if Time.now-File.mtime(req_path)>expiration
          end
          return req_path
        end
      else
        # does not exist or isn't in the right spot
        return nil
      end
    end
    
    # =============================================================================
    # Checks if the file specified by the passed in path info can be written to
    # 
    # @return the normalized path to the file if it can be written to; nil if it
    #         can't
    # =============================================================================
    def can_write(path_info)
      return nil if path_info.include? ".."
      req_path = Rack::Utils.unescape(path_info)
      # Add the drive letter or root path
      req_path = File.join(@root, req_path)
      req_path = File.expand_path req_path
      if File.directory? req_path
        dir=req_path
      else
        dir = File.dirname req_path 
      end
      if File.exist? dir and (!@root or req_path.index(@root) == 0)
        return req_path
      else
        # does not exist or isn't in the right spot
        return nil
      end
    end

    def call(env)
      handler=nil
      req_path=env[Sirf::Const::PATH_INFO]
      #find extension
      dot_at = req_path.rindex('.')
      ext=req_path[dot_at+1 .. -1] if dot_at
      handler=@handlers[ext] if ext and @handlers
      if handler
        handler.call(env)
      else
        req_path=can_serve(req_path)
        return [404,{},Const::ERROR_404_RESPONSE] if !req_path
        send_file_ex(env,req_path,ext)
      end
    end
    
    # =============================================================================
    # Send an actual file (code copied from the default Rack file handler and 
    # modified to handle mime-type overrides)
    # 
    # @param end the environment
    # @param req_path the requested path
    # @param ext the file extension
    # 
    # @return the complete HTTP response
    # =============================================================================
    def send_file_ex(env,req_path,ext)
      stat = File.stat(req_path)

      # Set the last modified times as well and etag for all files
      mtime = stat.mtime
      # Calculated the same as apache, not sure how well the works on win32
      etag = Sirf::Const::ETAG_FORMAT % [mtime.to_i, stat.size, stat.ino]

      modified_since = env[Sirf::Const::HTTP_IF_MODIFIED_SINCE]
      none_match = env[Sirf::Const::HTTP_IF_NONE_MATCH]

      # test to see if this is a conditional request, and test if
      # the response would be identical to the last response
      same_response = case
      when modified_since && !last_response_time = Time.httpdate(modified_since) rescue nil then false
      when modified_since && last_response_time > Time.now                                  then false
      when modified_since && mtime > last_response_time                                     then false
      when none_match     && none_match == '*'                                              then false
      when none_match     && !none_match.strip.split(/\s*,\s*/).include?(etag)              then false
      else modified_since || none_match  # validation successful if we get this far and at least one of the header exists
      end

      header = env[RESPONSE_HEADER] || {}
      header[Sirf::Const::ETAG] = etag

      if same_response
        [304,{},""]
      else

        status = 200
        header[Sirf::Const::LAST_MODIFIED] = mtime.httpdate

        # Set the mime type from our map based on the ending
        if ext
          header[Sirf::Const::CONTENT_TYPE] = Rack::Mime::MIME_TYPES[ext.downcase] || @default_content_type
        else
          header[Sirf::Const::CONTENT_TYPE] = @default_content_type
        end

        if not env[Sirf::Const::REQUEST_METHOD]=="HEAD"
          body=RackFileBody.new(req_path,stat.size)
        else
          header[RESPONSE_CONTENT_LENGTH]=stat.size.to_s
          body=""
        end
        return [status,header,body]
      end
    end
  end

  # =============================================================================
  # A FileHandler subclass that parses and interprets
  # embedded ruby files
  # =============================================================================
  class ErubisHandler < FileHandler
    def call(env)
      @env=env
      super
    end
    def each
      yield evaluate(Erubis::Eruby.new(open(@path){|io| io.read }), @env)
    end
    
    def sirf_sendfile(response)
      response.body << evaluate(Erubis::Eruby.new(open(@path){|io| io.read }), @env)
      response.finished
    end

    private
    def evaluate(erb, env)
      Module.new.module_eval{
        if env #define some variables that will be in scope when the binding is created and can be accessed in the template
          meta_vars = env
          query = env[QUERY_STRING]
          session=env[SESSION]
        end
        erb.result(binding())
      }
    end
  end

  # =============================================================================
  # This class manages client sessions. Override the create_session() method
  # to create custom session objects
  # =============================================================================
  class SessionManager

    attr_accessor :purge_timeout
    attr_accessor :auto_purge
    
    # =============================================================================
    # Initializes the session object
    # 
    # @param auto_purge true to automatically purge sessions when they are stale;
    #                   false otherwise
    # @param persist true to preserve sessions between requests; false to always create
    #               a new session
    # =============================================================================
    def initialize(auto_purge=true,persist=true)
      @auto_purge=auto_purge
      @sessions=java.util.concurrent.ConcurrentHashMap.new
      @purge_timeout=60*30 #30 minutes
      @last_purge=Time.now
      @persist=persist
      @session_id_string="sirf.session.id"
      @session_marker_string="sirf.session.marker"
      @session_timeout=60*30 #30 minutes
    end
    
    # =============================================================================
    # Creates an returns a new session
    # =============================================================================
    def create_session()
      Session.new()
    end
    
    # =============================================================================
    # Removes the specified session from the session cache
    # =============================================================================
    def remove_session(session)
      return if !session
      @sessions.delete(session.object_id)
    end
    
    # =============================================================================
    #  Gets the session corresponding the the HTTP session.
    #  If a session is not found then a new session is created
    #  
    #  @param app the calling application
    #  @param the Rack environment
    #  @param http_session the Rack HTTP session object
    # =============================================================================
    def get_session(app,env,http_session)
      return create_session() unless @persist
      id=http_session[@session_id_string]
      marker=http_session[@session_marker_string]
      session=nil
      session=@sessions[id] if id
      if session && session_timeout?(session,@session_timeout)==true
        session=nil
        @sessions.delete(id)
      end
      if !session || session.marker!=marker
        session=create_session()
        id=session.object_id
        marker=session.marker
        @sessions[id]=session
        puts "Created new session:"+id.to_s if Sirf::verbose
      else
        puts "Found session:"+id.to_s if Sirf::verbose
      end
      now=session.timestamp()
      if (@auto_purge && @last_purge+@purge_timeout)<now
        @last_purge=now
        purge()
      end
      http_session[@session_marker_string]=marker
      http_session[@session_id_string]=id
      return session
    end
    
    # =============================================================================
    #  Gets the session corresponding the the session id.
    #  
    #  @param id the session_id
    # =============================================================================
    def get_session_ex(id)
      return nil unless @persist
      return @sessions[id]
    end

    # =============================================================================
    #  Finds a session containing a specific value
    #  
    #  @param key the key
    #  @param value the value
    # =============================================================================
    def find_session_with_value(key,value)
      return nil unless @persist
      @sessions.each_value  do |sess|
        if sess[key]==value
          return sess
        end
      end
      return nil
    end

    # =============================================================================
    # Returns whether or not the session timed out
    # =============================================================================
    def session_timeout?(session,timeout) 
      return session.last_access+timeout <Time.now
    end
    
    # =============================================================================
    # Removes all stale sessions from the session cache
    # =============================================================================
    def purge()
      begin
        sessions=@sessions.dup
        tout=Time.now-@purge_timeout
        sessions.each do |id,session|
          if (session.last_access<tout)
            @sessions.delete(id)
            session.dispose
            puts "Purged session:"+id.to_s if Sirf::verbose
          end
        end
      rescue Exception=> e
        print "Session purge failed... #{e.message}\n }\n"
      end
    end
  end

  # =============================================================================
  # This class is an exception that holds an http status code, header and body.
  # Use it to return an arbitrary status code and message to the client
  # =============================================================================
  class HTTPException <Exception
    attr_reader :status, :message, :header
    attr_writer  :status, :message, :header
    @message=nil
    @status=nil
    def initialize(status,message="",header={})
      @status=status
      @message=message
      @header=header
      if(header.empty?)
        header[Sirf::Const::CONTENT_TYPE]="text/plain"
      end
    end
  end
end