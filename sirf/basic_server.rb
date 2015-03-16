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
# This class serve  as a base class for SIRF servers
# =============================================================================
module BasicServer
  
  class Session < Sirf::Session

    # used to offset the patient id prior to it being saved to
    # the http session. When clustering this id should be set via the
    # Session::set_id_offset() so that all servers use the same offset
    @@id_offset=17
    
    def initialize()
      super()
      @location_id     = 0
      @patient_id     = 0
      @encounter_date = nil
    end

    # =============================================================================
    # Sets the offset_id from a file
    # if the file does not exist then it is create and an new id is
    # added to it
    # =============================================================================
    def self.set_id_offset_from_file(file)
      File.open(file, 'rw+') do |f|
        f.flock File::LOCK_EX
        begin
          id=f.gets
          id.chomp if id
          id=id.to_i if id
          if !id || id<1
            id=Time.now % 1000000
            f.puts id
          end
          @@id_offset=id
        ensure
          f.flock File::LOCK_UN
        end
      end
    end
    def self.set_id_offset(offset)
      @@id_offset=offset
    end
  end
  
  # =============================================================================
  # This class maintains state information
  # when sending results back one line at a time.
  # =============================================================================
  class LineSendState
    attr_accessor :names_array, :comma_needed, :format, :linked_data_flags_array, :escape, :for_list
    
    # =============================================================================
    # Initializes the state
    # 
    # @param field_names the list of fields names in the order they will be returned
    #                    (can be an array or ^ seperated string)
    # @param format the return format (e.g. json or csv)
    # @param linked_data_flags an array of boolean values indication which fields
    #                          contain linked data
    # =============================================================================
    def initialize(field_names,format,linked_data_flags=nil)
      if field_names 
        if field_names.kind_of?(Array)
          @names_array=field_names
        else
          @names_array=field_names.split(/\^/)
        end
      else
        @names_array=nil
      end
      if linked_data_flags 
        if linked_data_flags.kind_of?(Array)
          @linked_data_flags_array=linked_data_flags
        else
          @linked_data_flags_array=linked_data_flags.split(/\^/)
        end
      else
        @linked_data_flags_array=nil
      end
      @comma_needed=false
      @format=format
      @escape=false
      @for_list=false
    end
    
    def dup
      ls=LineSendState.new(nil,@format)
      ls.names_array=@names_array
      return ls
    end
    
    def reset
      @comma_needed=false
    end
  end
  class Connection < Sirf::Connection
    
    # =============================================================================
    # Set the content-type header to text/plain with a '^' separator for the columns
    # 
    # @param ldsep optional separator for linked data
    # =============================================================================
    def mime_csv_fm(ldsep=nil)
      if ldsep
        set_content_type 'text/plain;separator=^;ldseparator='+ldsep
      else
        set_content_type 'text/plain;separator=^'
      end
    end
    
    # =============================================================================
    # Set the content-type header to text/plain with a '^' separator for the columns
    # a '\' for linked data
    # 
    # @param risep optional separator for rod information
    # =============================================================================
    def mime_csv_fm_ld(risep=nil)
      if risep
        set_content_type 'text/plain;separator=^;ldseparator=|;riseparator'+risep
      else
        set_content_type 'text/plain;separator=^;ldseparator=|'
      end
    end
    # =============================================================================
    # Set the content-type header to text/plain with a '^' separator for the columns
    # a '\' for linked data and '~' for row information
    # =============================================================================
    def mime_csv_fm_ld_ri
      set_content_type 'text/plain;separator=^;ldseparator=|;riseparator=~'
    end
    
  end
  
  class ModuleBase < Sirf::ModuleBase
   
    # =============================================================================
    # Generates an exception with an HTTP 404 error code
    # =============================================================================
    def not_found(msg=nil)
      msg="NOT FOUND" if !msg
      raise Sirf::HTTPException.new(404,msg)
    end
    
    # =============================================================================
    # Generates an exception with an HTTP 401 error code
    # =============================================================================
    def unauthorized(www_authenticate = 'Basic Realm="Server"')
      header={}
      header["WWW-Authenticate"]=www_authenticate
      raise Sirf::HTTPException.new(401,"Unauthorized",header)
    end
    
    # =============================================================================
    # Generates an exception with an HTTP 500 error code
    # =============================================================================
    def error(msg="Internal Server Error")
      raise Sirf::HTTPException.new(500,msg)
    end
    
    # =============================================================================
    # Generates an exception with an HTTP 400 error code
    # =============================================================================
    def bad_request(msg="BAD REQUEST")
      raise Sirf::HTTPException.new(400,msg)
    end

    
    # =============================================================================
    # Sends a no data responses
    # 
    # @param conn the connection
    # @param format the format for the data
    # =============================================================================
    def no_data(conn,format)
      if format=="json"
        conn.puts "{}"
      end
      return nil
    end
    
    # =============================================================================
    # Formats a color hint
    # @param format the format
    # @param value the data value
    # @param color  the color name
    # @param linked_data optional linked data for the value
    # =============================================================================
    def format_color_hint(format,value,color,linked_data=nil)
      value="" unless value
      case format
      when 'json'
        return "{\"value\":\"#{value.escape_string!}\",\"linkedData\":\"#{linked_data}\",\"fgColor\":\"#{color}\"}" if linked_data
        return "{\"value\":\"#{value.escape_string!}\",\"fgColor\":\"#{color}\"}}"
      else
        return "#{linked_data}|#{value.escape_string_quote_if_necessary!}{fgColor:#{color}}" if linked_data
        return "#{value.escape_string_quote_if_necessary!}{fgColor:#{color}}"
      end
    end
    
    def format_linked_data(format,value,linked_data)
      value="" unless value
      case format
      when 'json'
        return "{\"value\":\"#{value.escape_string!}\",\"linkedData\":\"#{linked_data}\"}"
      else
        return "#{linked_data}|#{value.escape_string_quote_if_necessary!}}"
      end
    end
    
    #=============================================================================
    # Formats a title hint (a row/column that will span the rest of the list/table
    # and act as a title)
    # 
    # @param format the format
    # @param value the data value
    # @param linked_data optional linked data for the value
    #=============================================================================
    def format_title_hint(format,value,linked_data=nil)
      value="" unless value
      case format
      when 'json'
        return "{\"value\":\"#{value.escape_string!}\",\"linkedData\":\"#{linked_data}\",\"font-style\":\"bold\",\"columnSpan\":\"-1\"}" if linked_data
        return "{\"value\":\"#{value.escape_string!}\",\"font-style\":\"bold\",\"columnSpan\":\"-1\"}"
      else
        return "#{linked_data}|#{value.escape_string_quote_if_necessary!}{font-style: bold; columnSpan:-1}" if linked_data
        return "#{value.escape_string_quote_if_necessary!}{font-style: bold; columnSpan:-1}"
      end
    end
    
    # =============================================================================
    # Converts the specified text to an array
    # @param text the text
    # @param width the maximum width of any given line
    # =============================================================================
    def make_text_array(text,width=255)
      return make_text_array_ex(text,width) if text.starts_with?("<html>")
      a=text.split(/\n/)
      len=a.length
      while len>0
        len-=1
        s=a[len]
        if s.length>width
          aa=make_text_array_ex(s,width)
          a[len,1]=aa
        end
      end
      return a
    end
    
    # =============================================================================
    # Creates a json name/value pair
    # =============================================================================
    def make_json_pair(name, value,escape=false)
      value=value.escape_string if escape
      return "\"#{name}\":\"#{value}\""
    end
 
    
    # =============================================================================
    # Extracts a key form an id value that may contain a format specifier
    # 
    # @param id the id
    # @param err_for_nil true to generate and exception if the passed id is nil; false otherwise
    # @param def_id default to use if the passed in id is nil
    # =============================================================================
    def extract_key(id,err_for_nil=true,def_id=nil)
      id=def_id if !id
      if !id and !err_for_nil
        return nil
      end
      id=nil if id==""
      raise Sirf::HTTPException.new(404, "Missing ID") if !id
      n=id.rindex('.') if id.is_a?(String)
      id[n..-1]="" if n
      return id
    end

    # =============================================================================
    # Extracts the requested return format form the path extension or the HTTP
    # Accept header
    # 
    # @param conn the connection
    # @param paths the paths array
    # @param def_format the default format
    # =============================================================================
    def extract_format(conn,paths,def_format="csv_fm_ld")
      return def_format if paths.empty?
      format=paths[paths.length-1]
      n=format.rindex('.') if format.is_a?(String)
      if !n
        s=",#{conn.http_accept},"
        return 'json' if s.index('application/json')
        return 'json' if s.index('text/x-json')
        return 'rml' if s.index('text/x-rml')
        return def_format 
      end
      format=format[n+1..-1]
      paths[paths.length-1][n..-1]=""
      paths.shift if paths[paths.length-1]==""
      return format
    end

    # =============================================================================
    # Extracts a key an format from the specified paths array
    # 
    # @param conn the connection
    # @param paths the paths array
    # @param err_for_nil true to generate and exception if the passed id is nil; false otherwise
    # @param def_id default to use if the passed in id is nil
    # @param def_format the default format
    # =============================================================================
    def extract_format_and_key(conn,paths,err_for_nil=true,def_id=nil,def_format="csv_fm_ld")
      format=extract_format(conn,paths,def_format)
      id=paths.shift
      id=def_id if !id
      if !id and !err_for_nil
        return [nil,format]
      end
      id=nil if id==""
      raise Sirf::HTTPException.new(404, "Missing ID") if !id
      return [id,format]
    end
    
    # =============================================================================
    # Purges cached information in the module. This method can be use to remotely
    # purged data that is cached by a module
    # =============================================================================
    def purge_cache(session,conn,connection,paths)
      raise Sirf::HTTPException.new(403) unless conn.app.is_purge_key_valid?(paths.shift)
    end
    
    # =============================================================================
    # Make linked data for a specified format form the first two elements of
    # the specified list. The first two elements will be replaced by a single value
    # representing the value and another piece of data that is linked to it (typically
    # and internal identifier)
    # 
    # @param the list to use
    # @param format the format
    # =============================================================================
    def make_linked_data(list,format='csv')
      case format
      when 'json'
        list[0] ="{\"value\":\"#{list[1]}\",\"linkedData\":\"#{list[0]}\"}"
      else
        list[0] << "|"
        list[0] << list[1]
      end
      list[1]=list[0]
      list.delete_at(0)
    end
    
    # =============================================================================
    # Make linked data for a json formatted value
    # =============================================================================
    def make_linked_data_json(ld,value)
      return "{\"value\":\"#{value}\",\"linkedData\":\"#{ld}\"}"
    end
    
    # =============================================================================
    # Make linked data for a csv formatted value
    # =============================================================================
    def make_linked_data_csv(ld,value)
      return "#{ld}|#{value}"
    end

    # =============================================================================
    # Gets the value of a mapped string
    # 
    # @param name the name of the string
    # @param default_value the value to return if the named string does not exist
    # =============================================================================
    def get_string(name, default_value)
      s=nil
      s=@strings[name] if @strings
      return s ? s : default_value
    end


    # =============================================================================
    # Creates a new connection
    # =============================================================================
    def create_connection(app, env, paths)
      Connection.new(app,env,{},"")
    end

    # =============================================================================
    # Sends a line/row of data sourced from a linefeed delimited string
    # 
    # @param conn the connection
    # @param format the return format (e.g. json or csv)
    # @param data the data
    # @param field_names the list of fields names in the order they will be returned
    #                    (can be an array or ^ seperated string)
    # =============================================================================
    def send_data(conn,format,data,field_names=nil)
      data=nil if data and data.length==0
      case format
      when 'json'
        conn.mime_json()
        if !data
          conn.puts "{ \"rows\":[]}"
          return
        end
        conn.puts "{"
        if field_names
          an=field_names.split(/\^/)
          conn.put "["
          comma_needed=false
          nl=an.length
          data.each_line do |line|
            conn.put ',' if comma_needed
            comma_needed=true if !comma_needed
            conn.put "\n"
            conn.put "\t{"

            a=line.chomp.split(/\^/)
            conn.put "\"",an[0],"\": "
            conn.put '"',a[0],'"'
            i=1
            while i<nl
              conn.put ", \"",an[i],"\": "
              conn.put '"',a[i],'"'
              i=i+1
            end
            conn.put "}"
          end
          conn.put "\n]"

        else
          conn.put "\"rows\": ["
          comma_needed=false
          data.each_line do |line|
            conn.put ',' if comma_needed
            comma_needed=true if !comma_needed
            conn.put "\n"
            conn.put "\t["
            a=line.chomp.split(/\^/)
            name=a.shift
            conn.put '"',name,'"' if name
            a.each do |col|
              conn.put ",\"",col,'"'
            end
            conn.put "]"
          end
          conn.put "\n\t]"
        end
        conn.puts "\n}"
      else
        ld=nil
        if format=='csv_fm'
          conn.mime_csv_fm
        elsif  format=='csv_fm_ld'
          conn.mime_csv_fm_ld
          ld='|'
        elsif  format=='csv_fm_ld_ri'
          ld='|'
          conn.mime_csv_fm_ld_ri
        else
          conn.mime_csv_fm
        end
        conn.puts field_names if field_names and conn.params['header']=='true'
        data.tr!('^',ld) if ld and data
        conn.puts data if data
      end
    end

    # =============================================================================
    # Prepares the connection and state object for the sending of a line/row oriented
    # data. Call prior to calling <code>start_line_data</code> or
    # <code>send_no_data</code>
    # 
    # @param conn the connection
    # @param format the return format (e.g. json or csv)
    # @param field_names the list of fields names in the order they will be returned
    #                    (can be an array or ^ seperated string)
    # @param linked_data_flags an array of boolean values indication which fields
    # =============================================================================
    def start_line_data(conn,format,field_names=nil,linked_data_flags=nil, error=nil)
      case format
      when 'json'
        conn.mime_json()
        if error
          error.escape_string_quote_if_necessary! 
          conn.put "{\"error\":\"#{error}\",\"_rows\":["
        else
          conn.put "{"
          if field_names
            conn.put '"_columns":["'
            field_names=field_names.split(/\^/) unless field_names.kind_of?(Array)
            conn.put field_names.join('","')
            conn.puts '"],'
          end
          conn.put "\"_rows\":["
        end
        return LineSendState.new(field_names,format,linked_data_flags)
      else
        if format=='csv_fm'
          conn.mime_csv_fm
        elsif  format=='csv_fm_ld'
          conn.mime_csv_fm_ld
        elsif  format=='csv_fm_ld_ri'
          conn.mime_csv_fm_ld_ri
        elsif  format=='sdf'
          conn.mime_sdf
        else
          conn.mime_csv_fm
        end
        
        state=LineSendState.new(field_names,format,linked_data_flags)
        if field_names and conn.params['header']=='true'
          conn.puts state.names_array.join('^')
        end
        return state
      end
    end

    # =============================================================================
    # Sends a line/row of data sourced from a file on disk
    # 
    # @param conn the connection
    # @param format the return format (e.g. json or csv)
    # @param filename the name of the file
    # @param field_names the list of fields names in the order they will be returned
    #                    (can be an array or ^ seperated string)
    # @param linked_data_flags an array of boolean values indication which fields
    # @param for_list true if the data is for a list; false if it for a table
    # =============================================================================
    def send_file_data(conn,format,filename,field_names,linked_data_flags,for_list)
      filename=conn.app.can_serve(filename);
      return not_found("count not serve file") unless filename
      state=start_line_data(conn, format, field_names, linked_data_flags)
      state.escape=true
      state.for_list=for_list
      f=File.open(filename)
      begin
        f.each_line do |line|
          line.strip!
          return unless line.length>0
          send_line_data(conn,format,line,state,true)
        end
        finish_line_data(conn, state);
      ensure
        f.close()
      end
    end
    
    # =============================================================================
    # Sends text as html
    # 
    # @param conn the connection
    # @param text the text to send
    # =============================================================================
    def send_text_as_html(conn,text)
      conn.mime_html
      text.rstrip!
      if(text.ends_with?("</html>"))
        conn.puts text
      else
        conn.puts "<html>\n<body>\n<pre style=\"font-size:0.8em; font-family: Lucida Console, Monaco, Menlo, Courier New,monospace\">"
        conn.puts text
        conn.puts "</pre>\n</body>\n</html>"
      end
    end
    
    # =============================================================================
    # Converts the text to an html document (if necessary)
    # 
    # @param text the text to convert
    # 
    # @return the text as an html document
    # =============================================================================
    def text_to_html(text)
      text.rstrip!
      if(text.ends_with?("</html>"))
        return text
      else
        s="<html>\n<body>\n<pre style=\"font-size:0.8em; font-family: Lucida Console, Monaco, Menlo, Courier New,monospace\">"
        s << text
        s << "</pre>\n</body>\n</html>"
        return s
      end
    end
    
    
    # =============================================================================
    # Sends text
    # 
    # @param conn the connection
    # @param format [String] the format
    # @param text [String] the text to send
    # =============================================================================
    def send_text(conn,format,text)
      if(format=="html")
        send_text_as_html(conn,text)
      else 
        conn.mime_text
        conn.puts text
      end
    end
    
    # =============================================================================
    # Sends a line/row of data. If formats the line based on the requested format
    # The state object is used to store information across invocations.
    # 
    # @param conn the connection
    # @param format the requested format on how to get the previous page
    # @param cols the data columns 
    # @param state state information
    # @param dosplit true if the cols parameter is a string that needs to be split
    #        on a '^' boundary; false otherwise
    # @param row_data optional row information
    # =============================================================================
    def send_line_data(conn,format,cols,state,dosplit=false,row_data=nil)
      return unless cols
      escape=false
      names=state.names_array
      linked_data=state.linked_data_flags_array
      nl=names ? names.length-1 : -1
      if state.escape==true
        if dosplit
          cols=cols.split(/\^/)
          dosplit=false
        end
        escape=true
      end
      for_list=state.for_list==true && nl==0 && !row_data
      is_text=format=='txt'
      case format
      when 'json'
        cols=cols.split(/\^/) if dosplit
        comma_needed=state.comma_needed
        if names
          conn.put ',' if comma_needed
          conn.put "{"  unless for_list==true
          comma_needed=false
          if row_data && row_data!=""
            conn.put row_data
          end
          value=cols[0]
          value=value.to_s if value
          if value && value!=""
            comma_needed=true
            conn.put "\"",names[0],"\":" unless for_list==true
            value.escape_string! if escape==true
            if linked_data and linked_data[0]==true
              ldn=value.index('|')
              if ldn
                conn.put "{\"linkedData\":\"#{value[0,ldn]}\",\"value\":\"#{value[ldn+1..-1]}\"}"
              else
                conn.put '"',value,'"'
              end
            else
              conn.put '"',value,'"'
            end
          end
          for i in 1..nl
            value=cols[i]
            value=value.to_s if value
            if value && value!=""
              conn.put "," if comma_needed
              comma_needed=true
              conn.put "\"",names[i],"\":" unless for_list==true
              if value[0].ord==123  #'{' 
                conn.put value
              else
                value.escape_string! if escape==true
                if linked_data and linked_data[i]==true
                  ldn=value.index('|')
                  if ldn
                    conn.put "{\"linkedData\":\"#{value[0,ldn]}\",\"value\":\"#{value[ldn+1..-1]}\"}"
                  else
                    conn.put '"',value,'"'
                  end
                else
                  conn.put '"',value,'"'
                end
              end
            end
          end
          conn.put "}"  unless for_list==true
        end
        state.comma_needed=true
      else
        conn.put row_data if row_data
        if dosplit
          conn.puts cols
        else
          nl=names.length-1
          for i in 0..nl
            conn.put '^' if i>0
            col=cols[i]
            next unless col
            if escape==true
              if is_text==false and linked_data and linked_data[i]==true
                ld=col.piece('|',1)
                if ld==col
                  ld=""
                else
                  col=col.piece('|',2)
                end
                conn.put ld,'|'
                if col.is_a?(String)
                  col.escape_string_quote_if_necessary!
                else
                  col=col.to_s
                end
                conn.put col
              else
                if col.is_a?(String)
                  col.escape_string_quote_if_necessary!
                else
                  col=col.to_s
                end
                conn.put col
              end
            else
              unless  col.is_a?(String)
                col=col.to_s
              end
              conn.put col
            end
          end
          conn.puts
        end
      end
    end

    # =============================================================================
    # Sets information about how paging is to be handled
    # 
    # @param conn the connection
    # @param prev_info information on how to get the previous page
    # @param next_info information on how to get the next page
    # @param prev_info information on how to get the previous page
    # =============================================================================
    def set_paging_info(conn,prev_info=nil,next_info=nil,link_info=nil)
      conn.set_paging_has_more_header("true")
      conn.set_paging_next_header(prev_info) if prev_info
      conn.set_paging_next_header(next_info) if next_info
      conn.set_link_info_header(link_info) if link_info
    end
    
    # =============================================================================
    # Creates a returns row data (markup used to describe a row) from a set of
    # hash values. The data is assumed to be properly formatted. The method simply
    # places the data within the appropriate construct for the specified format
    # =============================================================================
    def make_row_data(format,data)
      return data unless data
      return make_row_data_from_hash(format,data) if data.kind_of?(Hash)
      case format
      when 'json'
        return "\"_attributes\": \"{#{data.escape_string!}}\", "
      else 
        return data if data[0].ord==123  #'{' 
        return "{#{data.escape_string_quote_if_necessary!}}~"
      end
    end
    
    # =============================================================================
    # Creates a returns row data (markup used to describe a row) from a set of
    # hash values. The format determine how the data is represented.
    # 
    # @param format to format for the data
    # @param data the hash containing the data
    # =============================================================================
    def make_row_data_from_hash(format,data)
      return data unless data
      s=""
      case format
      when 'json'
        s<< "\"_attributes\":{"
        comma=false
        data.each_pair do |name, val|  
          val.escape_string!
          if comma
            s << ","
          else
            comma=true
          end
          s << "\""
          s << name
          s << "\":\""
          s << val
          s << "\""
        end
        s << "}"
      else
        s<< "{"
        comma=false
        data.each_pair do |name, val|  
          val.escape_string!
          if comma
            s << ";"
          else
            comma=true
          end
          s << name
          s << ":\""
          s << val
          s << "\""
        end
        s << "}"
      end
      return s
    end
    
    # =============================================================================
    # Finishes sending data that was being sent a line at a time
    # 
    # @param conn the connection
    # @param state the line state
    # =============================================================================
    def finish_line_data(conn,state)
      if state
        case state.format
        when 'json'
          conn.put "]}"
        end
        state.comma_needed=false
      end
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
        id,format=id.split(/\./,2)
      else
        format="csv_fm_ld"
      end
      id=nil if id==""
      [id,format]
    end
    protected
  
    # =============================================================================
    # Used for the connection and state object for the sending of a line/row as
    # part of a nested hierarchy. This method  start new branch in an existing 
    # hierarchy.
    # 
    # @param conn the connection
    # @param format the return format (e.g. json, or csv)
    # =============================================================================
    def start_line_data_ex(conn,format)
      case format
      when 'json'
        conn.put "\"rows\":["
      else
      end
    end

    def make_text_array_ex(text,width=255)
      a=[]
      len=text.length
      i=0
      width-=1
      while i<len
        t=i+width
        if t>=len
          a << text[i..-1]
          break
        end
        c=text[t]
        while i<t && c>33
          t-=1
          c=text[t]
        end
        t=t+width if t==i
        a << text[i..t]
        i=t+1
      end
      return a
    end
  end
end
