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
    class Patients < RestrictedModule
      def initialize
               @lookup_fields='@;.01;.03I;.02I;.09;.104IE;.102;.1;.108'.freeze
        @select_lookup_fields='@;.01;.03I;.02I;.09;.104IE;.102;.1IE;.108;.1041IE'.freeze
        @gender={
          "M" => "Male",
          "F" => "Female",
          "U" => "Unknown"
        }

        @list_fields   ="id^name^dob^gender^mrn^provider_name^encounter_date^encounter_reason^location^rm_bed^photo".split('^')
        @list_fields_linked_data=Array.new(10)
        @list_fields_linked_data[5]=true
        @most_recent_map=Caching::CachedConcurrentMap.new  #put in database when in production
        @select_fields ="id^name^dob^gender^mrn^provider_id^provider_name^encounter_date^encounter_reason^location_id^location^rm_bed^attending_id^attending_name^language^photo^relationship^code_status^code_status_short^wt^ht^io_in^io_out".split('^')
        @select_fields_linked_data=Array.new(@select_fields.length)
        @select_fields_linked_data[16]=true # linked data
      end
      # =============================================================================
      # =============================================================================
      # BEGIN API Methods
      # =============================================================================
      # =============================================================================


      def establish_relationship(session,conn,paths)
      end
      
      def expire_relationship(session,conn,paths)
      end
      
      def most_recent(session,conn,broker,paths)
        format=extract_format(conn,paths)
        user=session.current_user
        return no_data(conn,format) unless user
        mru=@most_recent_map[user]
        if mru
          state=start_line_data(conn,format,@list_fields,@list_fields_linked_data)
          mru.each do |item|
            send_line_data(conn,format,item,state,false)
          end
          finish_line_data(conn,state)
          return
        end
        res = broker.rpc("ORWPT TOP")
        res.strip!
        return no_data(conn,format) if res==""
        state=start_line_data(conn,format,@list_fields,@list_fields_linked_data)
        res.each_line do |line|
          line.chomp!
          list=lists_helper(conn,format,broker,line.piece('^',1))
          send_line_data(conn,format,list,state,false)
        end
        finish_line_data(conn,state)
      end
    
      def mine(session,conn,broker,paths)
        format=extract_format(conn,paths)
        res = broker.rpc("ORQPT PROVIDER PATIENTS",session.current_user)
        res.strip!
        return no_data(conn,format) if res==""
        state=start_line_data(conn,format,@list_fields,@list_fields_linked_data)
        res.each_line do |line|
          line.chomp!
          list=lists_helper(conn,format,broker,line.piece('^',1))
          send_line_data(conn,format,list,state,false)
        end
        finish_line_data(conn,state)
      end

      def nearby(session,conn,broker,paths)
        format=extract_format(conn,paths)
        return no_data(conn,format)
      end
      
      #=============================================================================
      # Selects a patient and keeps information about the selected patient
      # in the user's server session cache
      # 
      # @note path=select/{id}
      # 
      # @note we always send a JSON object that contains information about the selected patient
      #=============================================================================
      def select(session,conn,broker,paths)
        not_found if paths.empty?
        dfn,format=extract_format_and_key(conn,paths)
        res = broker.rpc("ORWPT SELECT", dfn)
        #RPC to return key information on a patient as follows:
        #  1    2   3   4    5      6    7    8       9       10      11   12 13  14
        #  NAME^SEX^DOB^SSN^LOCIEN^LOCNM^RMBD^CWAD^SENSITIVE^ADMITTED^CONV^SC^SC%^ICN
        res.strip!
        list=res.split(/\^/)
        not_found if list[0]=="-1"
        su=StringUtils.new
        vc=get_visit_category(broker,list[4])
        session.patient_selected(conn,dfn,list[4],vc,list[9].dup)
        slist=select_helper(conn,format,broker, dfn)
        #return field positions
        #0=id,1=name,2=dob,3=gender,4=mrn,5=provider_id,6=provider_name,7=encounter_date,8=encounter_reason
        #9=location_id,10=location,11=rm_bed,12=attending_id,13=attending_name,14=language,15=photo
        #16=relationship,17=code_status,18=code_status_short,19=wt,20=ht,21=io_in,22=io_out
        slist[9]=list[4] #location id
        slist[8]=su.title_case(slist[8])
        slist[16]="1|Caregiver" # hard-code relationship
        slist[22]="" # force the list to expand
        
        team=Array.new
        m=slist[5]
        if m && m.to_i>0
          slist[6]=su.title_case(slist[6])
          s="#{m}^^#{slist[6]}^Admitting Physician^true^"
          team << s
        end
        m=slist[14]
        if m && m.to_i>0
          slist[15]=su.title_case(slist[15])
          s="#{m}^^#{slist[15]}^Attending Physician^true^"
          team << s
        end
        session["select_care_team"]=team if team.length>0
        session["sensitive_patient"]=list[8]=="1" ? true : false
        vitals(broker, dfn,slist,19)
        conn.mime_json
        conn.puts "{"
        i=0
        fields=@select_fields
        ldfields=@select_fields_linked_data
        lv=nil
        fields.each do |field|
          val=slist[i]
          ld=ldfields[i]
          if val && val!=""
            ldn=ld==true ?  val.index('|') : nil
            conn.put lv,",\n" if lv
            if(ldn) 
              lv="  \"#{field}\":{\"linkedData\":\"#{val[0,ldn]}\",\"value\":\"#{val[ldn+1..-1]}\"}"
            else
              lv="  \"#{field}\": \"#{val}\""
            end
           
          end
          i+=1
        end
        conn.puts lv if lv
        conn.puts "}"
        add_to_most_recent(session, slist)
      end

      def list(session,conn,broker,paths)
        format=extract_format(conn,paths,false)
        id=conn.params["identifier"]
        id=paths.shift unless id
        if !id
          quick_list(session,conn,broker,format)
          return
        end
        gender=conn['gender']
        gender=paths.shift unless gender
        start=conn.params["start"]
        dir=conn.params["dir"]
        dir="1" unless dir
        return id_list_ex(conn,broker,format,dir,start,id,gender) if id.to_i>0
        return name_list_ex(conn,broker,format,dir,start,id,gender)
      end

      def by_category(session,conn,broker,paths)
        name=paths.shift
        if name=="provider"
          mine(session,conn,broker,paths)
          return
        end
        not_found if paths.empty? 
        id,format=extract_format_and_key(conn,paths,true)
        rpc=nil
        case name
        when 'team'
          rpc='ORQPT TEAM PATIENTS'
        when 'clinic'
          rpc='ORQPT CLINIC PATIENTS'
        when 'unit'
          rpc='ORQPT WARD PATIENTS'
        when 'speciality'
          rpc='ORQPT SPECIALTY PATIENTS'
        end
        not_found if rpc==nil
        res = broker.rpc(rpc,id)
        res.strip!
        if(res=="^No patients found.")
          return no_data(conn,format)
        end
        m=conn.app.get_module_for("util/patients/lists_helper")
        state=start_line_data(conn,format,@list_fields,@list_fields_linked_data)
        res.each_line do |line|
          list=m.lists_helper(conn,format,broker,line.piece('^',1))
          send_line_data(conn,format,list,state,false)
        end
        finish_line_data(conn,state)
      end      
      
      # =============================================================================
      # =============================================================================
      # END API Methods
      # =============================================================================
      # =============================================================================

      protected
      def select_helper(conn,format,broker,ien)
        ien=ien.to_i
        ien-=1
        params={
          FM::FILE => '2',
          FM::FIELDS =>@select_lookup_fields,
          FM::XREF => '#',
          FM::MAX => 1,
        }
        params[FM::FROM]=ien
        data,more,more_start=handle_query_ex(broker,'DDR LISTER',params)
        data.strip!
        return format_row(format,data,false)
      end
      
      def quick_list(session,conn,broker,format)
        user=session.current_user
        return unauthorized unless user
        state=start_line_data(conn,format,@list_fields,@list_fields_linked_data)
        has_most_recent=false
        mru=@most_recent_map[user]
        if mru
          has_most_recent=true
          mru.each do |item|
            send_line_data(conn,format,item,state,false)
          end
        else
          res = broker.rpc("ORWPT TOP")
          res.strip!
          unless res==""
            res.each_line do |line|
              line.chomp!
              list=lists_helper(conn,format,broker,line.piece('^',1))
              send_line_data(conn,format,list,state,false)
            end
            has_most_recent=true
          end
        end
        if has_most_recent==true
          if format=='json'
            sep=['{columnSpan:-1;valueType:widget_type; value:\"Label{templateName:bv.line.data_separator}\"}']
          else
            sep=['{columnSpan:-1;valueType:widget_type; value:"Label{templateName:bv.line.data_separator}"}']
          end
          rd=make_row_data(format,"enabled: false")
          send_line_data(conn,format,sep,state,false,rd)
        end
        res = broker.rpc("ORQPT DEFAULT PATIENT LIST")
        res.strip!
        unless res==""
          state=start_line_data(conn,format,@list_fields,@list_fields_linked_data)
          res.each do |line|
            line.chomp!
            list=lists_helper(conn,format,broker,line.piece('^',1))
            send_line_data(conn,format,list,state,false)
          end
        end
        finish_line_data(conn,state)
      end
      
      def lists_helper(conn,format,broker,ien)
        ien=ien.to_i
        ien-=1
        params={
          FM::FILE => '2',
          FM::FIELDS =>@lookup_fields,
          FM::XREF => '#',
          FM::MAX => 1,
        }
        params[FM::FROM]=ien
        data,more,more_start=handle_query_ex(broker,'DDR LISTER',params)
        data.strip!
        return format_row(format,data,true)
      end
      
      def handle_data(conn,format,data,fields,for_list=true,linked_data=nil)
        return no_data(conn,format) if  data==""
        state=start_line_data(conn,format,fields,linked_data)
        data.each_line do |line|
          line.chomp!
          send_line_data(conn,format,format_row(format,line,for_list),state,false)
        end
        finish_line_data(conn,state)
      end

      def format_row(format,row,for_list=true,su=StringUtils.new)
        #IEN=0
        #NAME=1 #.01
        #DOB=2 #.03
        #SEX=3 #.02
        #SSN=4 #.109
        #PROVIDER=5 #.104-IEN
        #PROVIDER=6 #.104-NAME
        #CURRENT_MOVEMENT=7 #.102
        #WARD_LOCATION=8 #.1
        #CURRENT_ROOM=9 #.108
        list=row.split('^')
        for i in 0..10
          list[i]='' unless list[i]
        end
        list[2].fmdate!
        list[7].fix_expanded_date!('@',',')
        g=@gender[list[3]]
        list[3]=g if g
        unless for_list
          list.insert(8, '') #insert encounter reason 
          case format
          when 'json'
            list[1].escape_string!
            #list[7].escape_string!
          else
            list[1].escape_string_quote_if_necessary!
            #list[7].escape_string_quote_if_necessary!
          end
          return list
        end
        list[5] << "|" << list[6] if list[6]!=""
        list[6]=list[7]
        list[7]="" #encounter reason
        list[10]='' #photo
        list.pop(list.length-10)
        case format
        when 'json'
          list[1].escape_string!
          list[6].escape_string!
          list[7].escape_string!
        else
          list[1].escape_string_quote_if_necessary!
          list[6].escape_string_quote_if_necessary!
          list[7].escape_string_quote_if_necessary!
        end
        return list
      end

      def id_list_ex(conn,broker,format,dir,start,query,gender)
        max=conn.params["max"]
        max=FM::MAX_DEFAULT if !max
        params={
          FM::FILE => '2',
          FM::FIELDS =>@lookup_fields,
          FM::XREF => 'SSN',
          FM::MAX => max,
          FM::PART =>query
        }
        params[FM::FROM]=start if start
        params[FM::FLAGS]='B' if dir=="-1"
        data,more,more_start=handle_query_ex(broker,'DDR LISTER',params)
        set_paging_info(conn, nil, more_start) if more
        handle_data(conn,format,data,@list_fields,true,@list_fields_linked_data)
      end

      def name_list_ex(conn,broker,format,dir,start,query,gender)
        max=conn.params["max"]
        max=FM::MAX_DEFAULT if !max
        query.upcase! if query
        start.upcase! if start
        gender.upcase! if gender
        screen=nil
        if query.index(',')
          a=query.split(/\,/,2)
          l0=a[0].length()
          l1=a[1].length()
          query=a[0]
          screen="I $E(^(0),1,#{l0})=\"#{a[0]}\",$E($P(^(0),\",\",2),1,#{l1})=\"#{a[1]}\""
        elsif query.index(' ')
          a=query.split(/ /,2)
          l0=a[1].length()
          l1=a[0].length()
          query=a[1]
          screen="I $E(^(0),1,#{l0})=\"#{a[1]}\",$E($P(^(0),\",\",2),1,#{l1})=\"#{a[0]}\""
        end
        if screen
          screen << ",$P(^(0),U,2)=\"#{gender}\"" if gender 
        else
          screen="I $P(^(0),U,2)=\"#{gender}\"" if gender 
        end
        params={
          FM::FILE => '2',
          FM::FIELDS =>@lookup_fields,
          FM::XREF => 'B',
          FM::MAX => max,
          FM::PART =>query
        }
        puts screen if screen
        params[FM::FROM]=start if start
        params[FM::FLAGS]='B' if dir=="-1"
        params[FM::SCREEN]=screen if screen
        data,more,more_start=handle_query_ex(broker,'DDR LISTER',params)
        set_paging_info(conn, nil, more_start) if more
        handle_data(conn,format,data,@list_fields,true,@list_fields_linked_data)
      end
      
      def add_to_most_recent(session,list)
        user=session.current_user
        return unless user
        mru=@most_recent_map[user]
        if mru
          mru.pop if mru.length>5
          for i in (0..mru.length-1)
            if mru[i][0]==list[0]
              mru.delete_at(i)
              break
            end
          end
        else
          mru=Array.new
          @most_recent_map[user]=mru
        end
        mru.unshift [list[0],list[1],list[2],list[3],list[4],list[6],list[7],list[8],list[10],list[18]]
      end
      
      def get_visit_category(broker,loc)
        return "" if loc==""
        inpatient=true
        init=inpatient ? "H" : ""
        rpc=broker.rpc("ORWPCE GETSVC",init,loc,inpatient ? 1 : 0)
        rpc.strip!
        return rpc.length==0 ? init : rpc
      end
      
      def vitals(broker,dfn,out,pos)
        rpc = broker.rpc("ORQQVI VITALS", dfn)
        rpc.each_line do |line|
          list = line.pieces("^", 2, 5)
          out[pos]=list[1] if list[0]=='WT'
          out[pos+1]=list[1] if list[0]=='HT'
          out[pos+3]=list[1] if list[0]=='IN'
          out[pos+4]=list[1] if list[0]=='OUT'
        end
      end
      
    end
  end
end
