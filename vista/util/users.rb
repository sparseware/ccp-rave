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
include Rave

module Vista
  module Util
    class Users < RestrictedModule
      attr_reader :info_fields_out
      def initialize
        @alerts_field_names="id|type^priority^patient^description^date_time^lconm^forwarded_by^forward_comment^forward_date_time"
        @info_types={
          "I" => "Information Only{icon:'resource:scribe.icon.info'}",
        }
        @priority_types={
          "high" => "High{icon:'resource:scribe.icon.priority.high'}",
          "moderate" => "Medium{icon:'resource:Sage.icon.empty'}",
          "low" => "Low{icon:'resource:scribe.icon.priority.low'}",
        }
        @gender={
          "M" => "Male",
          "F" => "Female",
          "U" => "Unknown"
        }
        @user_lookup_fields='@;.01'.freeze
        @user_lookup_field_names='primary_key^name'.freeze
        #.132=ophone;.133=mobile;..136=fax;111=street;.112;.113;.114=city;.115;.116=zip;.151=email;5=sex;5=dob
        @info_fields='@;.01;5;4I;.151;.132;.133;.136;.111;.112;.113;.114;.115;.116'
        @info_fields_out   ="id^xmpp_id^name^dob^gender^speciality^is_provider^email^office_number^mobile_number^fax_number^street^city^state_or_province^zip_code^country^photo"
      end

      # =============================================================================
      # =============================================================================
      # BEGIN API Methods
      # =============================================================================
      # =============================================================================

      def list(session,conn,broker,paths)
        format=extract_format(conn,paths,false)
        dir=1
        start=nil
        id=paths.shift
        bad_request unless id
        return id_list_ex(conn,broker,format,dir,start,id) if id.to_i>0
        return name_list_ex(conn,broker,format,dir,start,id)
      end

      def user(session,conn,broker,paths)
        ien,format=extract_format_and_key(conn,paths,false)
        ien=ien.to_i if ien
        not_found unless ien
        ien-=1
        params={
          FM::FILE => '200',
          FM::FIELDS =>@info_fields,
          FM::XREF => '#',
          FM::MAX => 1,
        }
        params[FM::FROM]=ien
        data,more,more_start=handle_query_ex(broker,'DDR LISTER',params)
        data.strip!
        not_found if data==""
        state=start_line_data(conn,format,@info_fields_out)
        list=data.split('^')
        #.132=ophone;.133=mobile;..136=fax;111=street;.112;.113;.114=city;.115;.116=zip;.151=email;5=sex;5=dob;'.freeze
        list[2].fmdate!
        list.insert(4,'')
        if list[9]
          list[8] << "\n" << list[9]
          list[8] << "\n" << list[10] if list[10]
        end
        g=@gender[list[3]]
        list[3]=g if g
        send_line_data(conn,format,list,state,false)
        finish_line_data(conn,state)
      end
      
      # =============================================================================
      # =============================================================================
      # END API Methods
      # =============================================================================
      # =============================================================================

      def has_key(session,conn,broker,paths)
        bad_request if paths.empty?
        rpc= broker.rpc('ORWU HASKEY',paths.shift)
        conn.puts has_key?(broker,paths.shift) ? "true" : "false"
      end
      def has_key?(broker,key)
        rpc= broker.rpc('ORWU HASKEY',key)
        return rpc=="1" ? "true" : "false"
      end
      def is_service_user(session,conn,broker,paths)
        bad_request if paths.empty?
        service=paths.shift
        bad_request if service.to_i==0
        conn.puts  is_service_user?(broker,service,paths.shift) ? "true" : "false"
      end
      def is_service_user?(broker,service,duz)
        duz=broker.duz unless duz
        service=","+service+","
        params={
          FM::FILE => '123.55',
          FM::FLAGS =>'QX',
          FM::IENS => service,
          FM::VALUE => duz,
        }
        return broker.rpc('DDR FIND1',params).to_i >0
      end

      def name_or_id_list(session,conn,broker,paths)
        dir,format=extract_format_and_key(conn,paths,false)
        start=paths.shift
        query=conn.params["filter"]
        query="" if !query
        return id_list_ex(conn,broker,format,dir,start,query) if query.to_i>0
        return name_list_ex(conn,broker,format,dir,start,query)
      end

      def id_list(session,conn,broker,paths)
        dir,format=extract_format_and_key(conn,paths,false)
        start=paths.shift
        query=conn.params["filter"]
        query="" if !query
        id_list_ex(conn,broker,format,dir,start,query)
      end
      def name_list(session,conn,broker,paths)
        dir,format=extract_format_and_key(conn,paths,false)
        dir=dir.to_i if dir
        dir=1 if !dir || dir==0
        from=paths.shift
        from =conn.params["start"] if !from
        from="" if !from
        from.upcase!
        key =conn.params["key"]
        rpc = broker.rpc("ORWU NEWPERS",from,dir,key,nil,nil,false)
        state=start_line_data(conn,format,"id|name")
        list=[]
        rpc.each_line do |line|
          line.chomp!
          n=line.rindex('^')
          line[n]=" " if n
          line.tr!('^','|')
          list << line
        end
        list.reverse! if dir==-1
        list.each do |line|
          send_line_data(conn,format,line,state,true)
        end
        finish_line_data(conn,state)
      end

      #
      # Vista returns DUZ^NAME^USRCLS^CANSIGN^ISPROVIDER^ORDERROLE^NOORDER^DTIME^
      #   COUNTDOWN^ENABLEVERIFY^NOTIFYAPPS^MSGHANG^DOMAIN^SERVICE^
      #   AUTOSAVE^INITTAB^LASTTAB^WEBACCESS^ALLOWHOLD^ISRPL^RPLLIST^
      #   CORTABS^RPTTAB^STANUM^GECSTATUS^PRODACCT
      #
      def get_current_user_info(conn,broker,all)
        rpc= broker.rpc('ORWU USERINFO')
        list=rpc.pieces('^',1,2,5,3,4,6,7,8,10,11,13,14,15,16,17,19,23,22,20)
        list[2]=list[2]=="1" ? "true" : "false"
        list[3]=list[3]=="1" ? "true" : "false"
        list[6]=list[6]=="0" ? "true" : "false" #change no-ordering to can_order so reverse
        list[8]=list[8]=="1" ? "true" : "false"
        list[9]=list[9]=="1" ? "true" : "false"
        list[14]=list[14]=="1" ? "true" : "false"
        list[15]=list[15]=="1" ? "true" : "false"
        case list[5]
        when '1'
          list[5]='clerk'
        when '2'
          list[5]='nurse'
        when '3'
          list[5]='doctor'
        when '4'
          list[5]='student'
        else
          list[5]='none'
        end
        #        mimic the following code an report back only the reports_only value
        #        list[16]=HasRptTab
        #        list[17]=HasCorTabs
        #        list[18]=IsRPL
        #
        #
        #          if ((HasRptTab) and (not HasCorTabs)) then
        #               IsReportsOnly := true;
        #             // Remove next if and nested if should an "override" later be provided for RPL users,etc.:
        #             if HasCorTabs then
        #               if (IsRPL = '1') then
        #                 begin
        #                   IsRPL := '0'; // Hard set for now.
        #                   IsReportsOnly := false;
        #                 end;
        #             // Following hard set to TRUE per VHA mgt decision:
        #             ToolsRptEdit := true;
        #              //    x := GetUserParam('ORWT TOOLS RPT SETTINGS OFF');
        #              //    if x = '1' then
        #             //      ToolsRptEdit := false;
        if list[18]!="1" && list[16]=="1" && list[17]!="1"
          list[16]="true"
        else
          list[16]="false"
        end
        if all
          list[17]=has_key?(broker,"LRLAB") ? "true" : "false"
          list[18]=has_key?(broker,"XUPROGMODE") ? "true" : "false"
          list[19]=(list[11]=="1" || is_service_user?(broker, "2", broker.duz)) ? "true" : "false"
          list[20]= (list[11]=="1" || is_service_user?(broker, "1", broker.duz)) ? "true" : "false"
        else
          list[17]=""
          list[18]=""
        end
        list.insert(3,'','','','','','','','','')
        s=conn.app.get_option('client_timeout')
        list[10] =s ? s.to_s : ""
        s=broker.timeout
        list[11] = s ? s.to_s : ""
        return list
      end
      def id_list_ex(conn,broker,format,dir,start,query)
        max=conn.params["max"]
        max=FM::MAX_DEFAULT if !max
        params={
          FM::FILE => '200',
          FM::FIELDS =>@user_lookup_fields,
          FM::XREF => 'SSN',
          FM::MAX => max,
          FM::PART =>query
        }
        params[FM::FROM]=start if start
        params[FM::FLAGS]='B' if dir=="-1"
        handle_query(broker,'DDR LISTER',params,conn,format,@user_lookup_field_names)
      end
      def name_list_ex(conn,broker,format,dir,start,query)
        max=conn.params["max"]
        max=FM::MAX_DEFAULT if !max
        query.upcase! if query
        screen=nil
        if query.index(',')
          a=query.split(/\,/,2)
          l0=a[0].length()
          l1=a[1].length()
          query=a[0]
          screen="I $E(^(0),1,#{l0})=\"#{a[0]}\",$E($P(^(0),\",\",2),1,#{l1})=\"#{a[1]}\""
        end
        params={
          FM::FILE => '200',
          FM::FIELDS =>@user_lookup_fields,
          FM::XREF => 'B',
          FM::MAX => max,
          FM::PART =>query
        }
        params[FM::FROM]=start if start
        params[FM::FLAGS]='BQ' if dir=="-1"
        params[FM::SCREEN]=screen if screen
        handle_query(broker,'DDR LISTER',params,conn,format,@user_lookup_field_names)
      end
    end
  end
end
