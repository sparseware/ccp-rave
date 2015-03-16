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
  class Vitals < ClinicalModule
    def initialize
      @vitals = {
        "temp"=>"Temperature",
        "pulse"=>"Pulse",
        "resp"=>"Resperation",
        "pox"=>"Pulse Oximetry",
        "po2"=>"Pulse Oximetry",
        "spo2"=>"Pulse Oximetry",
        "height"=>"Height",
        "weight"=>"Weight",
        "bp"=>"Blood Pressure",
        "bmi"=>"BMI",
        "cg"=>"Circumference/Girth",
        "cvp"=>"Central Venous Pressure (cmH20)",
        "in"=>"Input 24hr (cc)",
        "out"=>"Output 24hr (cc)",
        "pain"=>"Pain",
      }
      @vista_vitals = {
        "T"=>"temp",
        "P"=>"pulse",
        "R"=>"resp",
        "POX"=>"spo2",
        "HT"=>"height",
        "WT"=>"weight",
        "BP"=>"bp",
        "BMI"=>"bmi",
        "C/G"=>"cg",
        "CVP (cmH20)"=>"cvp",
        "Input 24hr (cc)"=>"in",
        "Output 24hr (cc)"=>"out",
        "PN"=>"pain",
      }
    end
    def realtime(session,conn,broker,dfn,paths)
      loc=conn.app.get_option("realtime")
      loc="" unless loc
      conn.mime_text
      conn.puts loc #"/data/telemetry.txt"
    end
    def most_recent(session,conn,broker,id,paths)
      summary(session,conn,broker,id,paths)
    end
    
    def summary(session,conn,broker,dfn,paths)
      rpc = broker.rpc("ORQQVI VITALS", dfn)
      format=extract_format(conn,paths,false)
      rpc.strip!
      fields=ClinicalUtils::VITALS_FIELDS
      linked_data=ClinicalUtils::VITALS_FIELDS_LINKED_DATA
      return no_data(conn,format)  if rpc==""
      state=start_line_data(conn,format,fields,linked_data)
      out=Array.new(3)
      rpc.each_line do |line|
        line.chomp!
        list = line.pieces("^", 2, 5,4, 6,3)
        m=list.pop;
        list[2].fmdate!
        list[3].gsub!(/^\((.*?)\)\s*$/,'\1')
        if list[0]=="WT" || list[0]=="HT"
          m=m.to_f
          if m>0
            m=(m*100).round/100.0
            n=list[1].index ' '
            list[1]=m.to_s+list[1][n..-1] if n
          end
        end
        send_line_data(conn,format,create_summary_value_row(out,format,list),state,false)
      end
      finish_line_data(conn,state)
    end
    
    def list(session,conn,broker,dfn,paths,count=99999999)
      params=PathParser.new(self,conn,broker,paths)
      from=params.from.to_f
      to=params.to
      format=params.format
      fields=ClinicalUtils::VITALS_FIELDS
      linked_data=ClinicalUtils::VITALS_FIELDS_LINKED_DATA
      tz=broker.timezone()
      s=dfn.to_s+"^"+from.to_s+"^"+to.to_s+"^0"
      rpc = broker.rpc("GMV V/M ALLDATA", s)
      lines=rpc.split(/\n/)
      return no_data(conn,format)  if lines.length<5 || lines[4].starts_with?('NO DATA')
      state=start_line_data(conn,format,fields,linked_data)
      ostate=state
      lines.shift
      lines.shift
      lines.shift
      lines.shift
      lines.reverse!
      a=Array.new(5)
      lines.each do | line|
        list=line.pieces('^',1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19)
        list[0].fix_expanded_date!('@','-')
        ldate="#{list[0]}T#{list[1].piece(':',1,2)}#{tz}"
        start_line_data_ex(conn,format)
        state.reset if state
        s=create_value_row(a,format,ldate,'temp',list[2])
        send_line_data(conn,format,s,state,false) if s
        s=create_value_row(a,format,ldate,'pulse',list[3])
        send_line_data(conn,format,s,state,false) if s
        s=create_value_row(a,format,ldate,'resp',list[4])
        send_line_data(conn,format,s,state,false) if s
        s=create_value_row(a,format,ldate,'spo2',list[5])
        send_line_data(conn,format,s,state,false) if s
        s=create_value_row(a,format,ldate,'bp',list[6])
        send_line_data(conn,format,s,state,false) if s
        s=create_value_row(a,format,ldate,'weight',truncate(list[7]),truncate(list[8]),"kg")
        send_line_data(conn,format,s,state,false) if s
        s=create_value_row(a,format,ldate,'bmi',list[9])
        send_line_data(conn,format,s,state,false) if s
        s=create_value_row(a,format,ldate,'height',truncate(list[10]),truncate(list[11]),"cm")
        send_line_data(conn,format,s,state,false) if s
        s=create_value_row(a,format,ldate,'cg',list[12],list[13],"cm")
        send_line_data(conn,format,s,state,false) if s
        s=create_value_row(a,format,ldate,'cvp',list[14],list[15],"mmHg")
        send_line_data(conn,format,s,state,false) if s
        s=create_value_row(a,format,ldate,'in',list[16])
        send_line_data(conn,format,s,state,false) if s
        s=create_value_row(a,format,ldate,'out',list[17])
        send_line_data(conn,format,s,state,false) if s
        s=create_value_row(a,format,ldate,'pain',list[18])
        send_line_data(conn,format,s,state,false) if s
        finish_line_data(conn,state)
        state.comma_needed=true if state 
        count-=1
        break if count<0
      end
      finish_line_data(conn,ostate)
    end
    def truncate(val)
      len=val ? val.length : 0
      return val if len==0
      n=val.index('.')
      return val if !n
      val=val[0..n+2] if n && n+2<len
      return val
    end
    def raw(session,conn,broker,dfn,paths)
      array=as_array(true,session,broker,dfn)
      return unless array
      conn.puts "[date,id,key,name,val,aflag,unit,range,is_document]"
      array.each do |a|
        conn.puts a.join('^')
      end
    end
    def as_array(abnormal_only,session,broker,dfn,from=nil,to=nil)
      to=broker.server_time('T') unless to
      from='1001018' unless from
      tz=broker.timezone()
      s=dfn.to_s+"^"+from.to_s+"^"+to.to_s+"^0"
      rpc = broker.rpc("GMV V/M ALLDATA", s)
      lines=rpc.split(/\n/)
      return nil if lines.length<5 || lines[4]=='NO DATA'
      lines.shift
      lines.shift
      lines.shift
      lines.shift
      lines.reverse!
      a=abnormal_only
      out=[]
      lines.each do | line|
        list=line.pieces('^',1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19)
        list[0].fix_expanded_date!('@','-')
        ldate="#{list[0]}T#{list[1].piece(':',1,2)}#{tz}"
        s=create_array_value_row(a,ldate,'temp',list[2])
        out << s if s
        s=create_array_value_row(a,ldate,'pulse',list[3])
        out << s if s
        s=create_array_value_row(a,ldate,'resp',list[4])
        out << s if s
        s=create_array_value_row(a,ldate,'spo2',list[5])
        out << s if s
        s=create_array_value_row(a,ldate,'bp',list[6])
        out << s if s
        s=create_array_value_row(a,ldate,'weight',truncate(list[7]),truncate(list[8]),"kg")
        out << s if s
        s=create_array_value_row(a,ldate,'bmi',list[9])
        out << s if s
        s=create_array_value_row(a,ldate,'height',truncate(list[10]),truncate(list[11]),"cm")
        out << s if s
        s=create_array_value_row(a,ldate,'cg',list[12],list[13],"cm")
        out << s if s
        s=create_array_value_row(a,ldate,'cvp',list[14],list[15],"mmHg")
        out << s if s
        s=create_array_value_row(a,ldate,'in',list[16])
        out << s if s
        s=create_array_value_row(a,ldate,'out',list[17])
        out << s if s
        s=create_array_value_row(a,ldate,'pain',list[18])
        out << s if s
      end
      return out;
    end
    
    def create_array_value_row(abnormal_only,date,key,val, pval=nil,unit="")
      val=val.piece('-')
      return nil unless val && val.length>0
      abnormal_only
      if val.ends_with?("*")
        abnormal="A"
      else
        return if abnormal_only==true
      end
      val << " (#{pval} #{unit})" if pval && pval.length>0
      name=@vitals[key]
      return [date,nil,key,name,val,abnormal,unit,nil,false]
    end
    def create_value_row(out,format,date,key,val, pval=nil,unit="")
      val=val.piece('-')
      return nil unless val && val.length>0
      abnormal="A" if val.ends_with?("*")
      val << " (#{pval} #{unit})" if pval && pval.length>0
      name=@vitals[key]
      return [date,nil,key,name,val,abnormal,unit,nil,false] unless format
      out=Array.new(5) unless out
      sort=""
      return ClinicalUtils.create_vitals_value_row(out,format,date,nil,nil,key,name,val,abnormal,unit,nil,sort)
    end
    
    def create_summary_value_row(out,format,list)
      val=list[1]
      val=val.piece('-')
      return nil unless val && val.length>0
      key=@vista_vitals[list[0]]
      key=list[0] unless key
      name=@vitals[key]
      name=list[0] unless name
      date=list[2]
      pval=list[3]
      abnormal="*" if val.ends_with?("*")
      val << " (#{pval})" if pval && pval.length>0
      out=ClinicalUtils.create_vitals_value_row(out,format,date,nil,nil,key,name,val,abnormal,nil,nil,nil)
      return out
    end
  end
end