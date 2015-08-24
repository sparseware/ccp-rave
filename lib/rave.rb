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
# Rave is A Ruby application framework for the VA's VistA Clinical Information
# System. It maps RESTful urls to VistA resources allowing those resources
# to be easily leveraged via web-based applications.
#
# It supports both CSV and JSON formats for returning records. To get the JSON
# format simply use the .json" extension when making a request. Certian single
# record requests only support json
#
# @version 3.0
# @author Don DeCoteau
# =============================================================================


module Rave
  require 'basic_server'
  require 'clinical_utils'
  
   module Const
      RESULT_TYPE='xResult-Type'.freeze
      RESULT_DATE='xResult-Date'.freeze
      RESULT_FACILITY='xResult-Facility'.freeze
      RESULT_SPECIMEN='xResult-Specimen'.freeze
      RESULT_ACCESSION_NUMBER='xResult-Accession-Number'.freeze
      RESULT_COMMENT='xResult-Comment'.freeze
      ORDER_REQUESTOR='xOrder-Requestor'.freeze

   end
  
 # =============================================================================
  # A class for parsing from/to date values from the end of a url
  # =============================================================================
  class PathParser
    attr_reader :from, :to, :format
    @from
    @to
    @format

    def initialize(mod,conn,broker,paths,err_for_nil=false)
      to,format=parse_reqid(conn,paths.pop,err_for_nil)
      from=paths.pop
      if !from
        from=to
        to="T"
      end
      qp=conn.params
      from=qp['from'] if !from
      to=qp['to'] if !to
      to="T" if !to
      if !from
        from="1001018"
      else
        if from[0].ord<65
          from.to_fmdate!
        else
          from=broker.server_time(from)
        end
      end
      if to[0].ord<65
        to.to_fmdate!
      else
        to=broker.server_time(to)
      end
      @from=from
      @to=to
      @format=format
    end
    
   # =============================================================================
    # Parses a specified id to extract format information. By default
    # the format is specified via a dot extension after the id (e.g. 12.json)
    # 
    # @param conn the connection
    # @param id the id to parse
    # @param err_for_nil true to raise and exception if the id is nil; false otherwise
    # @param default the default for the id is the one passed in is nil
    # 
    # @return a two element array with the id and format in that order
    # =============================================================================
     def parse_reqid(conn,id,err_for_nil=true,default=nil)
      id=default if !id
      if !id and !err_for_nil
        return [nil,'csv_fm_ld']
      end
      raise Sirf::HTTPException.new(404) if !id
      if id.is_a?(String) and id.index '.'
        id,fmt=id.split(/\./,2)
      else
        s=",#{conn.http_accept},"
        if s.index('text/xml')
          fmt='xml' 
        elsif s.index('application/json') || s.index('text/x-json')
          fmt='json' 
        else
          fmt="csv_fm_ld"
        end
      end
      id=nil if id==""
      [id,fmt]
    end
  end

  class Session < BasicServer::Session
    
   
    attr_reader :interactive_reminders
    attr_writer :basic_auth
    def initialize(broker_pool)
      super()
      @broker_pool=broker_pool
      @encounter_id   = nil
      @encounter_date = nil
      @location_id    = nil
      @patient_id     = nil
      @encounter_date = nil
      @broker         = nil
      @user           = nil
      @interactive_reminders=nil
      @duz=0
      @basic_auth     = false
      @last_non_polling_access=Time.now
    end
    
    #=============================================================================
    # Returns the last time a non polling access was made
    #=============================================================================
    def last_non_polling_access
      return @last_non_polling_access
    end
    
    #=============================================================================
    # Timestamps a non polling access
    #=============================================================================
    def timestamp_non_polling_access
      @last_non_polling_access=@last_access
    end
    
    #=============================================================================
    # Returns the id of the current user
    #=============================================================================
    def current_user
      return @broker.duz if @broker
      return 0
    end

    #=============================================================================
    # Gets the name of the current user
    #=============================================================================
    def current_username
      return @user
    end
    #=============================================================================
    # Gets the id of the current patient (if one has been selected)
    #=============================================================================
    def current_patient
      @patient_id
    end
    
    #=============================================================================
    # Gets the id of the current patient's location
    #=============================================================================
    def patient_location
      @location_id
    end
    
    #=============================================================================
    # Gets the date of the encounter for the current patient
    #=============================================================================
    def encounter_date
      @encounter_date
    end
    #=============================================================================
    # Gets the type of the encounter for the current patient
    #=============================================================================
    def encounter_type
      @encounter_type
    end
    
    #=============================================================================
    # Gets the Vista visit specification
    #=============================================================================
    def visit
      "#{@location_id};#{@encounter_date};#{@encounter_type}"
    end
    
   #=============================================================================
    # Returns whether the current is a physician
    #=============================================================================
    def is_physician?
      return @is_physician
    end
    
   #=============================================================================
    # Returns whether the session has an attached broker
    #=============================================================================
    def has_broker?
      return @broker!=nil
    end
    
    #=============================================================================
    # Sets whether the current is a physician
    #=============================================================================
    def set_is_physician(is_physician)
      @is_physician=is_physician
    end

    #=============================================================================
    # Called when a patient is selected to set the patient's information into
    # the session. 
    # 
    # @param conn the connection
    # @param pid the patient's id
    # @param lid the patients location id
    # @param eid the patient's encounter id
    # @param edate the patient's encounter date
    #=============================================================================
    def patient_selected(conn,pid,lid,eid,edate)
      pid=pid.to_i
      lid=lid.to_i
      @encounter_type=eid
      @patient_id=pid
      @location_id=lid
      @encounter_id=eid
      @encounter_date=edate
      conn.http_session["rave_pid"]=pid+@@id_offset
      conn.http_session["rave_edate"]=edate
      conn.http_session["rave_etype"]=eid
      conn.http_session["rave_lid"]=lid+@@id_offset
    end
    
    #=============================================================================
    # Logs out the current user
    #=============================================================================
    def logout
      @broker.logout if @broker
    end
    
    #=============================================================================
    # Ensures that the current user is logged in. If no credentials are passed in
    # then the current logged in state is checked and an exception is raised if
    # the user is not logged in.
    # IF credentials are passed in then the the current logged in state is checked
    # and if the user is not logged in or a different user is logged in then the
    # passed in credentials are authenticated.
    # 
    # @param conn the connection
    # @param username the user's name
    # @param password the user's password
    # @param domain the Vista domain
    #=============================================================================
    def loggedin_broker(conn,username=nil,password=nil,domain=nil)
      #      if conn.username && conn.password
      broker=@broker_pool.get(@broker)
     if @basic_auth==true
        username=conn.username unless username
        password=conn.password unless password
        domain=conn.domain unless domain
      end
      broker.switch_user(username,password,domain) if username && username.length>2 && password && password.length>2
      if broker.loggedin==true
        if @patient_id==nil || @patient_id<1
          id=conn.http_session["rave_pid"]
          @patient_id=id.to_i-@@id_offset if id
          id=conn.http_session["rave_lid"]
          @location_id=id.to_i-@@id_offset if id

          id=conn.http_session["rave_ireminders"]
          @interactive_reminders=id=="true" ? true : false
          @encounter_date=conn.http_session["rave_edate"]
        else
          @interactive_reminders=broker.rpc("ORQQPX NEW REMINDERS ACTIVE") == "1"
          conn.http_session["rave_ireminders"]=@interactive_reminders ? "true" : false
        end
        @user=username if username  && username.length>2
        @broker=broker
        @duz=broker.duz
        return broker
      end
      if broker
        broker.fail_gracefully()
        @broker=nil
      end
      app=conn.app
      header={}
      header["WWW-Authenticate"]='Basic realm="'+app.get_facility_name()+'"'
      
      raise Sirf::HTTPException.new(401,"Unauthorized",header)
    end
    
    #=============================================================================
    # Returns a handle to a broker for this session
    #=============================================================================
    def broker
      @broker=@broker_pool.get(@broker)
    end

    #=============================================================================
    # If the broker connections are being pooled then the broked will be released
    # back to the pool
    #=============================================================================
    def cleanup
      @broker=@broker_pool.release(@broker)
    end

    #=============================================================================
    # If the broker connections are being pooled then the broker will be
    # invalidated
    #=============================================================================
    def dispose
      @broker_pool.invalidate(@broker)
      @broker=nil
    end
  end
  
  #=============================================================================
  # This a a broker pool than does no actually pool connections
  #=============================================================================
  class NullPool
    def initialize(broker_options)
      @options=broker_options
    end
    def get(broker)
      return broker if broker
      return Broker.new(@options)
    end
    def release(broker)
      return broker
    end
    def invalidate(broker)
      begin
        broker.disconnect if broker
      rescue Exception
      end
    end
  end

  class SessionManager < Sirf::SessionManager
    
    # =============================================================================
    # Initializes the session manager object
    # 
    # @param options options from the configuration file
    # @param auto_purge true to automatically purge sessions when they are stale;
    #                   false otherwise
    # @param borker_pool a broker pooling handler
    # =============================================================================
    def initialize(options,auto_purge=true,broker_pool=nil)
      super(auto_purge,broker_pool==nil)
      broker_pool=NullPool.new(options) unless broker_pool
      @broker_pool=broker_pool
      @session_id_string="rave.session.id"
      @session_marker_string="rave.session.marker"
      @options=options.dup
      to=options['client_timeout']
      @session_timeout=to if to
    end
    
    #=============================================================================
    # Gets the value of an option set in the configuration file
    #=============================================================================
    def get_option(name)
      return @options[name]
    end
    
    def create_session()
      sess=Session.new(@broker_pool)
      sess.basic_auth=@options['support_basic_auth'];
      return sess;
    end

    # =============================================================================
    # Returns whether or not the session timed out
    # We override to time out sessions that are just polling
    # =============================================================================
    def session_timeout?(session,timeout) 
      now=Time.now
      return true if session.last_access+timeout <now
      return true if session.last_non_polling_access+timeout <now
      return false;
    end
    
  end

  class Connection < BasicServer::Connection
  end

  class ModuleBase < BasicServer::ModuleBase
    
    # =============================================================================
    # Extracts a from an to data specification from the url information
    # 
    # @param [Hash] qp the query parameters for the url
    # @param [Object] broker the broker
    # @param [Array] paths the url paths
    # @param [Boolean] optional true if the from/to values are optional; false otherwise
    # =============================================================================
    def extract_from_to(qp,broker,paths,optional=false)
      from=paths.shift
      from=qp['from'] if !from
      to=paths.shift
      to=qp['to'] if !to

      to="T" if !to && !optional
      if !from
        from="1001018" if !optional #if no optional then use the a default time
      else
        if from[0].ord<65
          from.to_fmdate!
        else
          from=broker.server_time(from) #value is a FM time spec TODO: have the broker do this in java code if possible
        end
      end
      if to
        if to[0].ord<65
          to.to_fmdate!
        else
          to=broker.server_time(to) #value is a FM time spec
        end
      end
      return [from,to]
    end

    def create_connection(app, env, paths)
      Connection.new(app,env,{},"")
    end

    # =============================================================================
    # Makes and RPC call that's a FM query.
    # 
    # @param broker the broker
    # @param rpc the RPC being called
    # @param params the parameters for the call
    # 
    # @return the results of the query
    # =============================================================================
    def get_query_data(broker,rpc,params)
      if params
        res=broker.rpc(rpc,params)
      else
        res=broker.rpc(rpc)
      end
      a=res.split(/\n/,2)
      a[0].strip!
      query_error("123") if a[0]=="[Errors]"
      query_error(a[1]) if a[0]=="[BEGIN_diERRORS]"
      if rpc=='DDR FINDER'
        if a[0]=="[BEGIN_diDATA]"
          a=a[1].split(/\n/,2) if a[0]=="[Misc]"
          if a[0]=="MORE"
            a[1][0,14]="" #replace  [BEGIN_diDATA]
          end
          a[1].chomp!("[END_diDATA]")
          a[1].strip!
        else
          a[1]=nil
        end
      else
        if a[0]=="[Misc]"
          a=a[1].split(/\n/,3)
          a[1]=a[2]
          a[2]=nil
        elsif a[0]!="[Data]"
          a[1]=nil
        end
      end
      return a[1]
    end
    
    # =============================================================================
    # Generates a HTTP 400 error with that can identify the FM error code or 
    # message
    # =============================================================================
    def query_error(msg)
      raise Sirf::HTTPException.new(400,"BAD REQUEST") if msg==nil
      raise Sirf::HTTPException.new(400,"about:error:fm-code:"+msg) if msg.to_i>0
      msg=msg.split(/\n/).join("\\n")
      raise Sirf::HTTPException.new(400,"about:error:fm-msg:\""+msg+"\"")
    end

    # =============================================================================
    # Makes and RPC call that's a FM query an send results back to the requestor.
    # The method is intended to be used for queries that return results in chunks
    # and support paging
    # 
    # @param broker the broker
    # @param rpc the RPC being called
    # @param params the parameters for the call
    # @param conn the connection
    # @param format the format to use for the results
    # @param field_names the name of the fields associated with the data
    # 
    # =============================================================================
    def handle_query(broker,rpc,params,conn,format='csv_fm_ld',field_names=nil)
      data,more,more_start=handle_query_ex(broker,rpc,params)
      set_paging_info(conn, nil, more_start) if more
      send_data(conn,format, data,field_names)
    end
    
    def handle_query_ex(broker,rpc,params)
      if params
        res=broker.rpc(rpc,params)
      else
        res=broker.rpc(rpc)
      end
      more=false
      more_start=nil
      if res
        a=res.split(/\n/,2)
        a[0].strip!
        query_error("123") if a[0]=="[Errors]"
        query_error(a[1]) if a[0]=="[BEGIN_diERRORS]"
        if rpc=='DDR FINDER'
          if a[0]=="[BEGIN_diDATA]"
            a=a[1].split(/\n/,2) if a[0]=="[Misc]"
            if a[0]=="MORE"
              a[1][0,14]="" #replace  [BEGIN_diDATA]
              more=true
            end
            a[1].chomp!("[END_diDATA]")
            a[1].strip!
          else
            a[1]=nil
          end
        else
          if a[0]=="[Misc]"
            a=a[1].split(/\n/,3)
            more_start=a[0].split(/\^/)[1]
            #puts more_start
            a[1]=a[2]
            more=true
            a[2]=nil
          elsif a[0]!="[Data]"
            a[1]=nil
          end
        end
        more_start="start=#{more_start}"if more
        a[0]=a[1]
        a[1]=more
        a[2]=more_start
        return a
      end
    end
  end
  
  #=============================================================================
  # The class represents a module that requires the the user be authenticated
  # in order for them to make any requests
  #=============================================================================
  class RestrictedModule < ModuleBase

    def process(session,conn,paths,verify_patient=false)
      session.timestamp_non_polling_access if conn['polling']!="true"
      broker = session.broker
      if paths.empty?
        if verify_patient
          dfn=verify_patient_id(session,:index)
          index(session,conn,broker,dfn,paths)
        else
          index(session,conn,broker,paths)
        end
      else
        if paths.length==1
          n=paths[0].rindex '.'
          if n
            paths << paths[0][n..-1]
            paths[0]=paths[0][0..n-1]
          end
        end
        method=paths.first.to_sym
        if respond_to?(method)
          paths.shift
          if verify_patient
            dfn=verify_patient_id(session,method)
            self.send(method,session,conn,broker,dfn,paths)
          else
            self.send(method,session,conn,broker,paths)
          end
        else
          not_found
        end
      end
    end
    
    #=============================================================================
    # Sub classes override to specify whether or not a patient must be selected
    # before the the specified method can be called
    # 
    # @param method the symbol representing the method
    #=============================================================================
    def needs_patient(method)
      return false
    end
    
    #=============================================================================
    # The method is called for a module when not method is specified. It is like
    # the 'index.html' file. By default is generates a NOT FOUND exception
    #=============================================================================
    def index(session,conn,broker,dfn)
      not_found
    end
    
    #=============================================================================
    # Called to check whether the current user/connection is authorized to access
    # this module
    #=============================================================================
    def check_auth(session,conn,paths)
      #check if we are using a pin to piggyback on another session
      pin_session=session['pin_session']
      if(pin_session && pin_session.has_baroker?) 
        session=pin_session
      else
        session['pin_session']=nil
      end
      session.loggedin_broker(conn)
      return session
    end
    
    #=============================================================================
    # Called to verify that the method specified requires a patient to be
    # selected that there is indeed a patient is selected or it throws and HTTP 409
    # exception
    # 
    # @param method the symbol representing the method
    #=============================================================================
    def verify_patient_id(session,method)
      return session.current_patient unless needs_patient(method)
      dfn=session.current_patient
      dfn=dfn.to_i if dfn
      raise Sirf::HTTPException.new(409,"NO PATIENT SELECTED") if dfn==nil || dfn<1
      return dfn
    end
    
    # =============================================================================
    # Purges cached information in the module
    # =============================================================================
    def purge_cache(session,conn,broker,paths)
      raise Sirf::HTTPException.new(403) unless conn.app.is_purge_key_valid?(paths.shift)
    end

  end

  #=============================================================================
  # The class represents a module that requires the the user be authenticated
  # and has selected a patient in order for them to make any requests
  #=============================================================================
  class ClinicalModule < RestrictedModule

    def process(session, conn, paths)
      super(session, conn, paths,true)
    end
    
    def needs_patient(method)
      return true
    end
  end

  class Application < Sirf::Application

    #=============================================================================
    # Initializes the application
    # 
    # @param options the configuration options
    #=============================================================================
    def initialize(options)
      super(options)
      @options=options.dup
      @site_name=nil
      @options=options.dup
      @purge_key=options['purge_key']
      @facility_id=options['facility_id']
      @facility_name=options['facility_name']
      ofile=options['offset_id_file']
      Session::set_id_offset_from_file(ofile) if ofile
      cacheto=options['cached_list_timeout']
      cacheto=3600 if !cacheto
      @cached_lists=CachedLists.new(cacheto,options['rpc_lists'])
    end

    #=============================================================================
    # Gets the id of the facility that this server represent
    #=============================================================================
    def get_facility_id()
      return @facility_id
    end

    #=============================================================================
    # Gets the name of the facility that this server represent
    #=============================================================================
    def get_facility_name()
      return @facility_name if @facility_name
      return @site_name if @site_name
      return "Vista"
    end
    
    # =============================================================================
    # Checks the specified cache purging key to see if the matched the key
    # specified in the configuration file
    # =============================================================================
    def is_purge_key_valid?(key)
      return key==@purge_key
    end

    #=============================================================================
    # Sets up an site specific information about the site that this broker
    # connects to
    #=============================================================================
    def setup_site_info(broker_options)
      broker=Broker.new(broker_options)
      begin
        broker.connect()
        res=broker.rpc('XUS SIGNON SETUP').split(/\n/)
        @site_name=res.length>6 ? res[6] : "VISTA"
      ensure
        broker.disconnect()
      end
    end

    #=============================================================================
    # Gets the value of an option set in the configuration file
    #=============================================================================
    def get_option(name)
      return @session_manager.get_option(name)
    end
    
    #=============================================================================
    # Returns a cached list. If the list has no been cached yet then the caching
    # library will retrieve the appropriate data from the broker and cache it
    # 
    # @param broker the broker
    # @param name the name of the list to retrieve
    # 
    # @return the list of data
    #=============================================================================
    def get_cached_list(broker,name)
      return @cached_lists.get_list_ex(self,broker,name)
    end
    
    #=============================================================================
    # Sets the value for a cached list
    # 
    # @param name the name of the list
    # @param list the value of the list
    # 
    #=============================================================================
    def set_cached_list(name,list)
      return @cached_lists.set_list(name,list)
    end
    
    #=============================================================================
    # Returns whether or not there is a a cached list with the specified name
    #=============================================================================
    def has_cached_list?(name)
      return @cached_lists.has_list?(name)
    end
    
    #=============================================================================
    # Gets the value of an option set in the configuration file
    #=============================================================================
    def site_name
      @site_name
    end
  end

end
