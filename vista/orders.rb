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
  class Orders < ClinicalModule
    def initialize
      @order_types=nil
      @order_category_mapping=nil
      @med_fields="type^drug^infusion_rate^start_date^stop_date^refills^tot_dose^unit_per_dose^orderid^status^lastfill^directions^notes^prn".split(/\^/)
      @med_fields_linked_data=Array.new(13)
      @med_fields_linked_data[0]=true
      @med_summary_fields="drug^status".split(/\^/)
      @med_summary_fields_linked_data=[true,nil]
      @order_status = {
        0  => 'Error',
        1  => 'Discontinued',
        2  => 'Complete',
        3  => 'Hold',
        4  => 'Flagged',
        5  => 'Pending',
        6  => 'Active',
        7  => 'Expired',
        8  => 'Scheduled',
        9  => 'Partial results',
        10 => 'Delayed',
        11 => 'Unreleased',
        12 => 'Dc/edit',
        13 => 'Cancelled',
        14 => 'Lapsed',
        15 => 'Renewed',
        97 => '', # <== "null" status, used for "No Orders Found."
        98 => 'New',
        99 => 'No status'
      }
      @fields="type^ordered_item^infusion_rate^start_date^stop_date^refills^tot_dose^unit_per_dose^status^lastfill^directions^notes^prn^category^clinical_category^provider^signed^flagged".split('^')
      @fields_linked_data=Array.new(18)
      @fields_linked_data[0]=true
      @fields_linked_data[1]=true
      @fields_linked_data[15]=true
    end
    
    # =============================================================================
    # =============================================================================
    # BEGIN API Methods
    # =============================================================================
    # =============================================================================

  
    # =============================================================================
    #Get a list or orders
    #
    #@note path=list/{view}
    #
    # @param from [Time] the start time - optional
    # @param to [Time] the end time - optional
    # @param view [String] orders view can be one of (active,unsigned,recently_expired,discontinued,expired,flagged,current,on_hold,pending)
    #
    #TODO: add from/to support
    # =============================================================================
    def list(session,conn,broker,dfn,paths)
      format=extract_format(conn,paths)

      if !paths.empty?
        view=paths.shift
      end
      # build a list of order types
      types_hash=@order_types;
      unless types_hash
        @order_type_mapping=conn.app.get_option("order_type_mapping")
        @order_category_mapping=conn.app.get_option("order_category_mapping")
        types_hash = {}
        p=conn.app.get_option("order_category_piece")
        p=p.to_i if p;
        p=3 if !p || p==0
        rpc = broker.rpc("ORWORDG MAPSEQ")
        rpc.each_line do |line|
          line.chomp!
          idno = line.piece("=", 1)
          name = line.piece("^", 2)
          category = line.piece("^", p)
          category =name if category.empty?
          types_hash[idno] = category
        end
        @order_types=types_hash
      end
      category_hash=@order_category_mapping
      state=start_line_data(conn,format,@fields,@fields_linked_data)
      state.escape=true
      # build list of order numbers
      params=Array.new(5)
      params[0]="2^0"
      params[1]=1
      params[2]=0
      params[3]=0
      params[4]=""
      view=conn.params['view'] if !view
      case view
      when 'active'
      when 'unsigned'
        params[0]='11^0'
      when 'recently_expired'
        params[0]="2^0"
        params[2]=broker.rpc('ORWOR EXPIRED')
        params[3]=broker.rpc('ORWU DT','NOW')
      when 'discontinued'
        params[0]="3^0"
      when 'expiring'
        params[0]="5^0"
      when 'current'
        params[0]="23^0"
      when 'pending'
        params[0]="7^0"
      when 'on_hold'
        params[0]="18^0"
      when 'flagged'
        params[0]="12^0"
      when 'event'
        params[0]="23^0"
        params[4]=conn.params['event'] || view
      else
        if view
          list=view.split(/;/)
          len=list.length
          len=5 if len>5
          len-=1
          for i in 0..len
            params[i]=list[i]
          end
        end
      end
      # [dfn, FilterTS^eventDelay.speciality(0), Service (DGroup), time_from, time_thru, pt_evt_id]
      rpc = broker.rpc("ORWORR AGET", dfn, params[0],params[1],params[2],params[3],params[4])
      iens = []
      rpc.each_line do |line|
        iens << line.piece("^", 1)
      end
      # build list of orders
      list = []
      rpc = broker.rpc("ORWORR GET4LST", 2, -1, iens)
      # RPC returns
      #           1   2    3     4      5     6   7   8   9    10    11    12    13    14     15     16  17    18    19     20
      # Pieces: ~IFN^Grp^ActTm^StrtTm^StopTm^Sts^Sig^Nrs^Clk^PrvID^PrvNam^ActDA^Flag^DCType^ChrtRev^DEA#^VA#^DigSig^IMO^DCOrigOrder}
      #         0         1            2           3           4      5         6       7           8         9       10       11    12    13         14             15      16      17 
      sig=""
      order=nil
      status=0
      # return fields
      # 0=type,1=ordered_item,2=infusion_rate,3=start_date,4=stop_date,5=refills,6=tot_dose
      # 7=unit_per_dose,8=status,9=lastfill,10=directions,11=notes,12=prn,13=category,14=clinical_category
      rpc.each_line do |line|
        s=line[0,1];
        line=line[1..-1]
        case s
        when "~"
          if (status != 0  and order)
            list[1] = order
            list[10]=sig
            send_line_data(conn,format,list,state,false)
            status=0;
            order=nil
          end
          line.chomp!
          list = line.pieces("^", 1, 2, 0,0, 4, 5,0,0,6,0,0,0,0,0,11,10,7,13)
          status=list[8].to_i
          list[13]=types_hash[list[1]]
          type=@order_type_mapping[list[1]]
          type=list[1] unless type
          if type=="home_meds"
            type="meds"
          end
          list[0].replace_char!(';','_')
          list[0] << "|" << type
          list[8] = @order_status[status]
          list[3].fmdate!
          list[4].fmdate!
          if(!list[15].empty?) 
            list[14] = list[14].piece("~")
            list[15] << "|" << list[14]
          end
          list[14]=type=="meds" ? list[13] : ""
          if list[16]=="1"
            list[16]="true"
          else
            list[16]="false"
          end
          if list[17]=="1"
            list[17]="true"
          else
            list[17]="false"
          end
          category=category_hash[list[13]]
          list[13]=category if category
          sig=""
          order=nil
        when "t"
          if order
            sig << '\n' unless sig.empty?
            sig << line.chomp 
          else
            order=line.chomp 
          end
        when "|"
          sig << line.chomp.html_to_text
        end
      end
      if (status != 0  and order)
        list[1] = order
        list[10]=sig
        send_line_data(conn,format,list,state,false)
      end
      finish_line_data(conn,state)
    end

    def order(session,conn,broker,dfn,paths)
      ien,format=extract_format_and_key(conn,paths)
      ien.replace_char!('_',';')
      send_text(conn,format,broker.rpc("ORQOR DETAIL", ien, dfn))
      conn.mime_html
  
    end
  

  
    # =============================================================================
    # Get the list of ordered medications
    # @param type optional medication type (active, summary)
    # =============================================================================
    def medications(session,conn,broker,dfn,paths)
      type=paths.shift
      type='list' unless type
      case type
      when 'active'
      when 'list'
        active_medications(session,conn,broker,dfn,paths)
      when 'summary'
        medication_summary(session,conn,broker,dfn,paths)
      else
      end
    end
    
    # =============================================================================
    # =============================================================================
    # END API Methods
    # =============================================================================
    # =============================================================================

    def medication(session,conn,broker,dfn,paths)
      ien,format=extract_format_and_key(conn,paths)
      ien.replace_char!('_',';')
      send_text(conn,format,broker.rpc("ORWPS DETAIL", dfn, ien))
    end
    

    def results(session,conn,broker,dfn,paths)
      ien=paths.first
      conn.put broker.rpc("ORWOR RESULT", dfn,ien,ien)
    end

    def results_history(session,conn,broker,dfn,paths)
      ien=paths.first
      conn.put broker.rpc("ORWOR RESULT HISTORY",dfn,ien,ien)
    end
    
    def medication_summary(session,conn,broker,dfn,paths)
      format=extract_format(conn,paths)
      rpc = broker.rpc("ORWPS ACTIVE", dfn)
      rpc.strip!
      return no_data(conn,format) if rpc==""
      orders=rpc.split("~")
      orders.shift
      su=StringUtils.new
      state=start_line_data(conn,format,@med_summary_fields,@med_summary_fields_linked_data)
      state.escape=true
      until orders.empty?
        lines=orders.shift.split(/\n/)
        s=lines.shift
        s.strip!
        list=s.split('^')
        rpc=""
        next if list[0]=="OP" # don't want outpatient
        list[9]=su.title_case(list[9])
        case list[9]
        when 'Expired','Discontinued','Canceled'
          next
        end
        list[1]=list[8]
        list[1] << "_1" unless list[1].index("_")
        list[1].replace_char!(';','_')
        list[2]=su.title_case(list[2])
        list[0]="#{list[1]}|#{list[2]}"
        if list[9]=="Pending"
          list[1]=format_color_hint(format,list[9],"blue")
        else
          list[1]=list[9]
        end
        list.pop(list.length-2)
        send_line_data(conn,format,list,state)
      end
      finish_line_data(conn,state)
    end

    # =============================================================================
    # Get the active medications for the current patient
    #
    # broker call returns:
    #  type^ien^drug^infusion_rate^stop_date^refills^tot_dose^unit_dose^orderid^status^lastfill^^^start_date
    #   drug\directions on seperate lines
    #
    # rave returns:
    # id|type^drug^infusion_rate^start_date^stop_date^refills^tot_dose^unit_dose^orderid^status^lastfill^directions^notes
    # =============================================================================
    def active_medications(session,conn,broker,dfn,paths)
      format=extract_format(conn,paths)
      rpc = broker.rpc("ORWPS ACTIVE", dfn)
      rpc.strip!
      return no_data(conn,format) if rpc==""
      state=start_line_data(conn,format,@med_fields,@med_fields_linked_data)
      state.escape=true
      orders=rpc.split("~")
      orders.shift
      su=StringUtils.new
      until orders.empty?
        lines=orders.shift.split(/\n/)
        s=lines.shift
        s.strip!
        list=s.split('^')
        s=list.shift
        s.chomp!
        case s
        when 'UD'
          type="Unit Dose"
        when 'OP'
          #type="Outpatient"
          next #don't want outpatient
        when "IV"
          type="Intravenous"
        else
          type="Home"
        end
        #move start date
        s=""
        s=list[14].fmdate! if list[14]
        list.insert(3,s)

        list[4].fmdate!
        list.slice!(13..-1)
        list[11]=""
        list[12]=""
        rpc=""
        list[9]=su.title_case(list[9])
        case list[9]
        when 'Expired','Discontinued','Canceled'
          next
        end
        until lines.empty?
          s=lines.shift
          s.strip!
          next if s=="t  HOME"
          case s[0]
          when 116# 't'
            list[13] << "\\n" if list[13]!=""
            list[12] << s[1..-1]
          when 92 # '\\
            list[12] << "\\n" if list[12]!=""
            list[11] << s[1..-1]
          else
            list[11] << " "
            list[11] << s
          end
        end
        list[11].strip!
        list[12].strip!
        if list[11].starts_with?(list[1])
          n=list[11].index(']')
          if n
            list[1]=list[11][0..n]
            list[11]=list[11][n+1..-1]
            list[11].strip!
          else
            list[11]=list[11][list[1].length..-1]
          end
        elsif list[11].starts_with?("[GEQ")
          n=list[11].index(']')
          if n
            list[11]=list[11][n+1..-1]
            list[11].strip!
          end
        end
        list[12]=list[12][1..-1] if list[12][0]==92
        list[0].replace_char!(';','_')
        list[0]="#{list[0]}|#{type}"
        list[1]=su.title_case(list[1])
        list[11]=su.title_case(list[11])
        if list[9]=="Pending"
          list[1]=format_color_hint(format,list[1],"pending")
        end
        send_line_data(conn,format,list,state)
      end
      finish_line_data(conn,state)
    end
    
    def events(session,conn,broker,dfn,paths)
      conn.put rpc = broker.rpc("OREVNTX LIST",dfn)
    end

    def filters(session,conn,broker,dfn,paths)
      state=start_line_data(conn,'csv')

      # build list of order numbers
      iens = []
      rpc = broker.rpc("ORWORR AGET", dfn, "2^0", 1, 0, 0, "") #!# [dfn, FilterTS, Service (DGroup), time_from, time_thru, pt_evt_id]
      rpc.each_line do |line|
        iens << line.piece("^", 1)
      end

      # build counts by order status
      hash = {}; hash.default = 0
      rpc = broker.rpc("ORWORR GET4LST", 2, -1, iens) #!# what are these params?
      rpc.each_line do |line|
        next unless line[0,1] == '~'
        type = line.piece("^",6).to_i
        hash[type] += 1
      end

      # sort and send
      list = hash.sort {|a,b| b[1] <=> a[1]}
      list.map! do |type,num|
        name = @order_status[type.to_i]
        "#{name}|#{name} (#{num})"
      end
      list.unshift("|All")
      list.each do |item|
        conn.puts item if item
      end
    end

    def views(session,conn,broker,dfn,paths)
      conn.send_module_file('clinical','data/views.csv_fm_ld')
    end
    
    def expanded_views(session,conn,broker,dfn,paths)
      conn.send_module_file('clinical','data/expanded_views.csv_fm_ld_ri')
    end
    def unsigned(session,conn,broker,dfn,paths)
      ien,format=PathParser::extract_format_and_key(paths,false)
      state=start_line_data(conn,format)
      rpc= broker.rpc('ORWOR UNSIGN',dfn)
      rpc.each_line do |line|
        line.chomp!
        send_line_data(conn,format,line,state,true)
      end
      finish_line_data(conn,format,state)
    end

    def types(session,conn,broker,dfn,paths)
      ien,format=PathParser::extract_format_and_key(paths,false)
      state=start_line_data(conn,format)
      rpc = broker.rpc("ORWDX WRLST") #!# parameter is Encounter.location
      rpc.each_line do |line|
        line.chomp!
        line = line.pieces("^", 1, 2).join('|')
        if line.include? "*************************************"
          line='|{ value:<<EOF Line { horizontalAlign: full} EOF; valueType: widget_type }[selectable=false]'
        end
        send_line_data(conn,format,line,state,true)
      end
      finish_line_data(conn,format,state)
    end
    
    def meds_history(session,conn,broker,dfn,paths)
      ien,format=extract_format_and_key(conn,paths)
      conn.put broker.rpc("ORWPS MEDHIST", dfn, ien)
    end
    
    def as_array(active_only,session,broker,dfn,from=nil,to=nil)
      rpc = broker.rpc("ORWPS ACTIVE", dfn)
      rpc.strip!
      return nil if rpc==""
      out=[]
      orders=rpc.split("~")
      orders.shift
      su=StringUtils.new
      until orders.empty?
        lines=orders.shift.split(/\n/)
        s=lines.shift
        s.strip!
        list=s.split('^')
        s=list.shift
        case s
        when 'UD'
          type="Unit Dose"
        when 'OP'
          type="Outpatient"
        when "IV"
          type="Intravenous"
        else
          type="Home"
        end
        #move start date
        s=""
        s=list[14].fmdate! if list[14]
        list.insert(3,s)

        list[4].fmdate!
        list.slice!(13..-1)
        list[11]=""
        list[12]=""
        rpc=""
        until lines.empty?
          s=lines.shift
          s.strip!
          next if s=="t  HOME"
          case s[0]
          when 116# 't'
            list[12] << "\\n" if list[12]!=""
            list[12] << s[1..-1]
          when 92 # '\\
            list[12] << "\\n" if list[12]!=""
            list[11] << s[1..-1]
          else
            list[11] << " "
            list[11] << s
          end
        end
        list[11].strip!
        list[12].strip!
        if list[11].starts_with?(list[1])
          n=list[11].index(']')
          if n
            list[1]=list[11][0..n]
            list[11]=list[11][n+1..-1]
            list[11].strip!
          else
            list[11]=list[11][list[1].length..-1]
          end
        elsif list[11].starts_with?("[GEQ")
          n=list[11].index(']')
          if n
            list[11]=list[11][n+1..-1]
            list[11].strip!
          end
        end
        list[12]=list[12][1..-1] if list[12][0]==92
        list[0].replace_char!(';','_')
        list[1]=su.title_case(list[1])
        list[11]=su.title_case(list[11])
        list[9]=su.title_case(list[9])
        list.unshift list[0]
        list[1]=type
        out << list
      end
      return out
    end
  end
end
