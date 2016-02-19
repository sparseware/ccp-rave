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

require "sirf_utils"
include Rave
module Vista
  class Patient < ClinicalModule
    def initialize
      @reminder_categories ={
        '0' => "Applicable",
        '1' => "Due",
        '2' => "Not Applicable",
        '3' => "Error",
        '4' => "Unknown",
      }
      @reminder_priorities ={
        "1" => "High{icon:'resource:scribe.icon.priority.high'}",
        "2" => "Medium{icon:'resource:Sage.icon.empty'}",
        "3" => "Low{icon:'resource:scribe.icon.priority.low'}",
      }

      @reminder_field_names="description^due_date^last_occurance^priority^type"
      @reminder_ok_as_dialog={}
      @io_fields="date^io^result^type".split(/\^/)
      @osat_fields="date^order^instructions".split(/\^/)
      @allergy_fields="allergen^reaction".split(/\^/)
      @allergy_fields_linked_data=[true,nil]
      @problem_fields="problem^status".split(/\^/)
      @problem_fields_linked_data=[true,nil,nil]
      @careteam_fields="id^xmpp_alias^name^role^is_physician".split(/\^/)
      @admissions_fields="date^location^admit_type^discharge_status"
      @admissions_fields_linked_data=[nil,true,nil,true]
      @appointments_fields="date^location^status"
      @appointments_fields_linked_data=[true,nil,nil]
      @flag_fields=["description"]
      @flag_fields_linked_data=[true]
    end
    
    def summary(session,conn,broker,dfn,paths)
      format=extract_format(conn,paths)
      type=paths.shift
      return bad_request unless type
      case type
      when 'allergies'
        get_allergies(session,conn,broker,dfn,format,true)
      when 'problems'
        get_problems(session,conn,broker,dfn,format,true)
      else
        bad_request
      end
    end
    def careteam(session,conn,broker,dfn,paths)
      format=extract_format(conn,paths)
      team=session['care_team']
      if team
        state=start_line_data(conn,format,@careteam_fields)
        state.escape=true
        team.each do |s|
          send_line_data(conn,format,s,state,true)
        end
        finish_line_data(conn,state)
        return
      end
      team=session['select_care_team']
      team=Array.new unless team
      rpc=broker.rpc("ORQPT PATIENT TEAM PROVIDERS", dfn)
      rpc.strip!
      if rpc.to_i >0
        rpc.each_line do |line|
          line.chomp!
          id=line.piece('^',1)
          s="#{id}^^#{line.piece('^',2)}^Team Physician^true"
          team << s
        end
      end
      session['care_team']=team
      session['select_care_team']=nil;
      state=start_line_data(conn,format,@careteam_fields)
      state.escape=true
      team.each do |s|
         send_line_data(conn,format,s,state,true)
      end
      finish_line_data(conn,state)
      return
      
    end
    def problems(session,conn,broker,dfn,paths)
      format=extract_format(conn,paths)
      list=problems_as_array(session,broker,dfn);
      return no_data(conn,format) unless list && list.length>0
      state=start_line_data(conn,format,@problem_fields,@problem_fields_linked_data)
      state.escape=true
      list.each do |line|
        send_line_data(conn,format,line,state)
      end
      finish_line_data(conn,state)
    end

    def allergies(session,conn,broker,dfn,paths)
      format=extract_format(conn,paths)
      list=allergies_as_array(session,broker,dfn,format);
      return no_data(conn,format) unless list && list.length>0
      state=start_line_data(conn,format,@allergy_fields,@allergy_fields_linked_data)
      state.escape=true
      list.each do |line|
        send_line_data(conn,format,line,state)
      end
      finish_line_data(conn,state)
    end
    
    def flags(session,conn,broker,dfn,paths)
      format=extract_format(conn,paths)
      res = broker.rpc("ORPRF HASFLG",dfn)
      res.strip!
      return no_data(conn,format) if res==""
      state=start_line_data(conn,format,@flag_fields,@flag_fields_linked_data)
      state.escape=true
      res.each_line do |line|
        line.replace_char!('^','|')
        send_line_data(conn,format,[line],state)
      end
      finish_line_data(conn,state)
    end
    
    def flag(session,conn,broker,dfn,paths)
      ien,format=extract_format_and_key(conn,paths)
      res = broker.rpc("ORPRF GETFLG",dfn,ien)
      res.strip!
      send_text(conn,format,res)
    end
    
    def problem(session,conn,broker,dfn,paths)
      ien = paths[0].to_i
      conn.put broker.rpc("ORQQPL DETAIL", dfn, ien, "") if ien > 0
    end

    def allergy(session,conn,broker,dfn,paths)
      ien = paths[0].to_i
      conn.put broker.rpc("ORQQAL DETAIL", dfn, ien, ien) if ien > 0
    end
    def posting(session,conn,broker,dfn,paths)
      type=paths.shift
      type='sticky' unless type
      type.downcase!
      ien = type.to_i
      if ien > 0
        conn.put broker.rpc("TIU GET RECORD TEXT", ien)
      elsif type == "sticky"
        conn.send_module_file('data',"postings/#{dfn}.html")
      elsif type == "a"
        conn.put broker.rpc("ORQQAL LIST REPORT", dfn)
      end
    end
    
    # =============================================================================
    # Returns the list of admissions for the current (or specified) patient
    #
    # @path admissions/[id]
    #
    # @return true or false
    # =============================================================================
    def admissions(session,conn,broker,dfn,paths)
      format=extract_format(conn,paths)
      state=start_line_data(conn,format,@admissions_fields,@admissions_fields_linked_data)
      id=paths.shift
      id=dfn if !id || id.to_i==0
      loc=conn.params['location']=="true"
      rpc=broker.rpc("ORWPT ADMITLST",id)
      rpc.each_line do |line|
        line.chomp!
        list=line.split(/\^/)
        next if loc && list[2]==""
        case list[6]
        when "1"
          list[6]="Completed"
        when "2"
          list[6]="Unsigned"
        end
        line = "A;" << list[0]
        line << ";"
        line << list[1] if list[1]!="" && list[1]!="0"
        list[0].fmdate!
        line << "|" << list[0] << "^" << list[2]
        line << "^" << list[3]
        line << "^" 
        line << list[5] << "|" << list[6] if list[5]!="0"
        send_line_data(conn,format,line,state,true)
      end
      finish_line_data(conn,state)
    end

    # =============================================================================
    # Gets the appointments for a patient for a given date range
    #
    # @path appointments/[from/to]
    #
    # @return a two part multipart document. The first part contains the id|title
    #         for the test sections in the report and the second part contains
    #         the text for the report
    # =============================================================================
    def appointments(session,conn,broker,dfn,paths)
      format=extract_format(conn,paths)
      from,to=extract_from_to(conn.params,broker,paths,true)
      from="1001018" if !from
      tp="T+3650"
      loc=conn.params['location']=="true"
      state=start_line_data(conn,format,)
      rpc=broker.rpc("ORWCV VST", dfn,0,from,to)
      rpc.each_line do |line|
        line.chomp!
        list=line.pieces('^',1..4)
        list[1].fmdate!
        list[2].replace_char!(';','|')
        next if loc && list[2]==""
        make_linked_data(list)
        send_line_data(conn,format,list,state)
      end
      finish_line_data(conn,state)
    end

    def alerts(session,conn,broker,dfn,paths)
      #return unauthorized 
      format=extract_format(conn,paths)
      rpc = broker.rpc("ORQQPXRM REMINDERS APPLICABLE", dfn,session.patient_location)
      state=start_line_data(conn,format,@reminder_field_names)
      rpc.each_line do |line|
        line.chomp!
        list = line.pieces("^",1, 2, 3,4,5,6,7,7)
        list[2].fmdate! if list[2] =~ /^\d/
        list[3].fmdate! if list[3] =~ /^\d/
        list[4]=@reminder_priorities[list[4]] #make null for now
        s=@reminder_categories[list[5]]
        s=@reminder_categories['2'] if !s
        list[5]=s
        list[6]=list[6]=='1' ? 'true' : 'false'
        list[7]=dialog_ok_as_template(broker,list[0])
        make_linked_data(list)
        send_line_data(conn,format,list,state)
      end
      finish_line_data(conn,state)
    end
    
    def allergies_as_array(session,broker,dfn,format)
      rpc = broker.rpc("ORQQAL LIST", dfn)
      return nil if rpc=="^No Allergy Assessment\n"
      su=StringUtils.new
      out=[]
      rpc.each_line do |line|
        line.chomp!
        line=su.title_case(line)
        list = line.pieces("^", 1, 2, 4)
        make_linked_data(list)
        list[1].gsub!(/\;/,'; ')
        out << list
      end
      return out
    end
    
    def problems_as_array(session,broker,dfn)
      rpc = broker.rpc("ORQQPL LIST", dfn, "A")
      return nil if rpc=="^No problems found.\n"
      su=StringUtils.new
      out=[]
      rpc.each_line do |line|
        line.chomp!
        next if line==""
        line=su.title_case(line)
        line=line.pieces('^',1,2)
        make_linked_data(line)
        out << line
      end
      return out
    end
    
    def dialog_ok_as_template(broker,ien)
      s=@reminder_ok_as_dialog[ien]
      unless s
        rpc=broker.rpc("TIU REM DLG OK AS TEMPLATE",ien)
        s=rpc.include?("1") ? "true" : "false"
        @reminder_ok_as_dialog[ien]=s
      end
      return s
    end

  end
end
