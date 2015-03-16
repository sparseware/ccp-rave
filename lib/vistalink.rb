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
# start vista link in MUMPS with the following command: JOB LISTENER^XOBVTCPL(8001)
# =============================================================================


require 'java'
require 'vljConnector-1.5.0.026.jar'
require 'vljFoundationsLib-1.5.0.026.jar'
require 'vljSecurity-1.5.0.026.jar'
require 'log4j-1.2.8.jar'
require 'javaee.jar'
require 'jaxen-core.jar'
require 'jaxen-dom.jar'
require 'saxpath.jar'
module Rave
  class Broker

    def initialize(options={})
      @server  = options['server'] || "LocalVistaServer"
      @defdiv  = options['defdiv']
      @context= options['context'] || "XOBV VISTALINK TESTER"
      @imaging_url_mapping= options['imaging_url_mapping']
      @access  = nil
      @verify  = nil
      @duz     = 0
      @name    = nil
      @params  = java.util.HashMap.new
      if !options['pooled']
        @mutex=Mutex.new
      else
        @mutex=nil
      end
      @login_context=nil
      @principal
      t = Time.now
      t=t.to_a
      @timezone=Time.now.zone #show get timezone on vista server
      @timezone="PDT" if @timezone.length>3
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
      @login_context!=nil
    end
    def timeout
      @timeout
    end
    def timezone
      @timezone;
    end
    def ping
      rpc('XWB IM HERE')
    end
    def duz
      return @duz
    end
    def server_time(spec='NOW')
      ## add code to figure out time-zone difference between rave and vista server
      #to minimize network calls for time
      rpc('ORWU DT',spec)
    end

    def switch_user(access,verify, defdiv)
      unless access
        access=@access
        verify=@verify
      end
      defdiv=@defdiv unless defdiv
      if @mutex
        @mutex.synchronize do
          switch_user_ex(access,verify,defdiv)
        end
      else
        switch_user_ex(access,verify,defdiv)
      end
    end
    def logout
      @access=nil
      @duz=0
      @principal=nil
      if @login_context
        begin
          @login_context.logout()
        rescue Exception
        end
        @login_context=nil
      end
    end
    def login(access,verify,defdiv)
      if @mutex
        @mutex.synchronize do
          login_ex(access,verify,defdiv)
        end
      else
        login_ex(access,verify,defdiv)
      end

    end

    def rpc(name, *vals)
      if @mutex
        @mutex.synchronize do
          rpc_ex(name,*vals)
        end
      else
        rpc_ex(name,*vals)
      end
    end


    def disconnect()
      logout()
    end

    ##
    # Gracefully terminates the connection to the broker
    # This is meant to be when an unexpected broker error occurs
    # It will cause the broker object to re-initiate the connection if
    # its is used again
    #
    def fail_gracefully()
      #don't wait on the mutex because we want any active connection to terminate (there shouldn't be any)
      begin
        logout()
      rescue Exception
      end
    end

    ##
    # Disposes of the broker connection
    # This is meant to be called by connection reapers
    ##
    def dispose
      logout
    end

    ##
    # Gets whether the current connection is valid
    # It just checks whether the connection has timed out
    ##
    def valid?()
      return true unless @sock or @timeout_time
      return Time.now<@timeout_time
    end
    
    private
    def switch_user_ex(access,verify, defdiv)
      login_ex(access,verify,defdiv)
    end
    def login_ex(access,verify,defdiv)
      @login_context=nil
      @principal=nil;
      begin
        cbh =Java::gov.va.med.vistalink.security.CallbackHandlerUnitTest.new(access,verify,defdiv);
        lc= javax.security.auth.login.LoginContext.new(@server, cbh);
        lc.login();
        @principal = Java::gov.va.med.vistalink.security.VistaKernelPrincipalImpl.getKernelPrincipal(lc.getSubject());
        @login_context=lc;
        @access=access
        @verify=access
        @defdiv=defdiv
        @duz=@principal.getUserDemographicValue(Java::gov.va.med.vistalink.security.m.VistaKernelPrincipal.KEY_DUZ);
        @name=@principal.getUserDemographicValue(Java::gov.va.med.vistalink.security.m.VistaKernelPrincipal.KEY_NAME_DISPLAY);
        @timeout=@principal.getUserDemographicValue(Java::gov.va.med.vistalink.security.m.VistaKernelPrincipal.KEY_DTIME);
        @timeout=@timeout.to_i if @timeout
      rescue Exception=>e
        fail_gracefully() #we want a new connection next time
        raise Sirf::HTTPException.new(502 ,e.to_s)
      end
    end

    def rpc_ex(name, *vals)
      begin
        conn=@principal.getAuthenticatedConnection()
        req=Java::gov.va.med.vistalink.rpc.RpcRequestFactory.getRpcRequest(@context, name);
        unless vals.empty? 
          i=1
          params=req.getParams()
          vals.map do |item|
            case item
            when Array
               h={}
              (item.empty? ? [""] : item).inject([]) do |ary,val|
                h[(ary.size + 1).to_s]=val.to_s
              end
              params.setParam(i,"array",h);
            when Hash
              item.each do |key,val|
                @params.put(key.gsub('"',''),val)
              end
              params.setParam(i,"array",@params);
            else
              params.setParam(i,"string",item.to_s);
            end
            i+=1
          end
        end
        resp = conn.executeRPC(req);
        @params.clear()
        @timeout_time = Time.now + @timeout
        return resp.getResults();
      rescue Exception=>e
        @params.clear()
        fail_gracefully() #we want a new connection next time
        raise Sirf::HTTPException.new(502 ,e.to_s)
      end
    end
  end
end
