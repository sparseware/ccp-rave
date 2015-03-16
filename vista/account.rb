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
require "base64"
include Rave
module Vista
  class Account < ModuleBase
    def initialize
      @vista_fields ="client_timeout^alerts_check^user_class^can_sign^order_role^can_order^timeout^can_verify^notify_apps^domain^service^auto_save_interval^initial_tab^ad_hoc_query^disable_hold^reports_only^has_labs_key^super_user^medicine_service^all_services".split('^')
      @fields ="id^name^is_provider^dob^gender^mobile_phone^office_phone^home_phone^sip_number^photo^client_upgrade_status^client_upgrade_href".split('^')
      #fields ="id^name^is_provider^dob^gender^mobile_phone^office_phone^home_phone^sip_number^photo^client_timeout^alerts_check^user_class^can_sign^order_role^can_order^timeout^can_verify^notify_apps^domain^service^auto_save_interval^initial_tab^ad_hoc_query^disable_hold^reports_only^has_labs_key^super_user^medicine_service^all_services"
    end
    def login(session,conn,paths)
      username=conn['username']
      password=conn['password']
      domain=conn['domain']
      password=Base64::decode64(password) if password && conn['base64']=='true'
      unless username
        username=conn.username
        password=conn.password
        domain=conn.domain
        session.basic_auth=true
      end
      unauthorized unless password && password.length>2 && username && username.length>2
      session.logout()
      broker = session.loggedin_broker(conn, username, password,domain)
      format=extract_format(conn,paths)
      m=conn.app.get_module_for("util/users/info")
      list=m.get_current_user_info(conn,broker,true)
      vista=list.slice!(10..-1)
      session.set_is_physician(list[2]=='true')
      list.concat check_version(conn)
      if format=='json'
        conn.mime_json()
        conn.put "{"
        for i in 0..list.length
          value=list[i]
          next unless value
          value=value.to_s
          conn.put "\"#{@fields[i]}\":\"#{value}\","
        end
        if vista
          conn.put  "\"vista_params\":{"
          value=vista[i]
          value="" unless value
          value=value.to_s
          value.escape_string_quote_if_necessary
          conn.put "\"#{@vista_fields[0]}\":\"#{value}\""
          for n in 1..vista.length
            value=vista[n]
            next unless value
            next unless @vista_fields[n]
            value=value.to_s
            value.escape_string_quote_if_necessary
            conn.put ",\"#{@vista_fields[n]}\":\"#{value}\""
          end
          conn.puts"},"
        end
        unless @site_params
          @site_params=conn.app.get_option("client_site_parameters");
          @site_params=@site_params.to_hash.to_json if @site_params
        end
        conn.put  "\"site_parameters\":#{@site_params}" if  @site_params
        conn.puts "}"
      else
        state=start_line_data(conn,format,@fields)
        state.escape=true
        send_line_data(conn,format,list,state,false)
        finish_line_data(conn,state)
      end
    end

    def logout(session,conn,paths)
      session.dispose()
      conn.app.remove_session(session)
    end
    def check_version(conn)
      return [nil,nil]
    end
    
    def alerts(session,conn,broker,paths)
      s,format=extract_format_and_key(conn,paths,false)
      state=start_line_data(conn,format)
      rpc= broker.rpc('ORWORB FASTUSER')
      list=nil
      rpc.each_line do |line|
        line.chomp!
        if line.starts_with?("Forwarded by: ^")
          s=line.piece('^',3,99)
          s=s[1,s.length-2] if s.starts_with?('"') and s.length>2
          list[7]=s
          s=line.piece('^',2)
          list[6]=s.piece("   ",1)
          s=s.piece("   ",2)
          s.fix_expanded_date!(' ')
          list[8]=s
          next
        end
        send_line_data(conn,format,list,state,false) if list
        list=line.pieces('^',1,4,2,6,8,3)
        s=@info_types[list[0]]
        list[0]=s if s
        list[0]=list[4]+'|'+list[0]
        s=list[1]
        s=@priority_types[s.downcase!] if s
        list[1]=s if s
        list[4]=list[4].piece(';',3).fmdate!
        list << "" << "" << ""
      end
      send_line_data(conn,format,list,state,false) if list
      finish_line_data(conn,state)
    end

    def status(session,conn,paths)
      broker=session.loggedin_broker(conn)
      count=0
      rpc= broker.rpc('ORWORB FASTUSER')
      rpc.each_line do |line|
        line.chomp!
        count+=1 if line.length>0 and !line.starts_with?("Forwarded by: ^")
      end
      conn.puts <<-MSG
        {
          "ok": true,
          "alerts": #{count}
        }
      MSG
    end
  end
end
