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

require 'java'
require 'sparseware-sirf-util.jar'
module Rave
  
  # =============================================================================
  # This class wraps the pure java implementation of
  # the VistA RPC broker
  #
  class Broker
    
    def duz
      @duz
    end
    
    def name
      @name
    end
    
    def initialize(options={})
      @host    = options['host'] || '127.0.0.1'
      @port    = options['port'] || 9201
      @timeout = options['timeout'] || 180
      @linger  = options['linger'] || 0
      @defdiv  = options['defdiv']
      @auto_reconnect= options['auto_reconnect'] || false
      @imaging_url_mapping= options['imaging_url_mapping']
      @duz     = 0
      @name    = nil
      @linger  = 0 if @linger < 0
      @linger  = 30 if @linger > 30
      @debug=true if options['debug']==true
      if options['pooled']
      end
      @loggedin = false
      @timezone=Time.now().strftime("%z") #should get timezone on vista server
    end
    
    def connect
      if !@broker
        @broker=com.sparseware.sirf.vista.RPCBroker::getConnection(@host,@port)
      end
      @broker.connect() unless @broker.isConnectionValid()
    end
    
    def create_imaging_url(url)
      return url if !@imaging_url_mapping || @imaging_url_mapping.empty?
      !@imaging_url_mapping.each {|prefix,replacement|
        next unless prefix == url[0, prefix.size]
        url[0, prefix.size]=replacement
        return url
      }
      return url
    end
    
    def loggedin
      @loggedin
    end
    
    def timeout
      @timeout
    end
    
    def timezone
      @timezone;
    end
    
    def ping
      @broker.ping if @broker
    end

    def server_time(spec='NOW')
      return @broker.server_time(spec)
    end

    def switch_user(access,verify, defdiv)
      defdiv=@defdiv unless defdiv
      connect() unless @broker
      @loggedin=false
      begin
        @loggedin=@broker.switchUser(access,verify,defdiv)
        if @loggedin==true
          @name=@broker.getDisplayName()
          @duz=@broker.getDuzAsInt()
          @timeout=@broker.getBrokerTimeOut()
        else
          @name=nil
          @duz=0
        end
        return @loggedin
      rescue Exception=>e
        log(e)
        @broker.disconnect(@linger,true) if @broker
        raise Sirf::HTTPException.new(401 ,e.to_s)
      end
    end
    
    def logout()
      @duz=0
      @loggedin=false
      @broker.logout() if @broker
    end
    def login(access,verify,defdiv)
      @loggedin=false
      begin 
        @loggedin=@broker.login(access,verify,defdiv,@auto_reconnect)
        if @loggedin==true
          @name=@broker.getDisplayName()
          @duz=@broker.getDuzAsInt()
          @timeout=@broker.getBrokerTimeOut()
        else
          @name=nil
          @duz=0
        end
      rescue Exception=>e
        log(e)
        @broker.disconnect(@linger,true) if @broker
        raise Sirf::HTTPException.new(401 ,e.to_s)
      end
    end

    def rpc(name, *vals)
      begin 
        return @broker.rpc(name,vals)
      rescue Exception=>e
        log(e)
        @broker.disconnect(@linger,true) if @broker
        @loggedin=false
        raise Sirf::HTTPException.new(401 ,e.to_s)
      end
    end


    def disconnect()
      @broker.disconnect(@linger,false) if @broker
      @broker=nil
      @loggedin=false
    end
    def fail_gracefully
      disconnect()
    end
    ##
    # Disposes of the broker connection
    # This is meant to be called by connection reapers
    ##
    def dispose
      @broker.disconnect() if @broker
      @broker=nil
      @loggedin=false
    end

    ##
    # Gets whether the current connection is valid
    # It just checks whether the connection has timed out
    ##
    def valid?()
      return @broker && @broker.isConnectionValid()
    end
    private
    def log(e)
      if @debug==true
        puts e.to_s
        #puts e.inspect 
        puts e.backtrace.join("\n")
      end
    end
  end
end
