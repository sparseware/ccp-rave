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
  class Labs < ClinicalModule
    def initialize
      @lab_categories=nil
      @fields=ClinicalUtils::LABS_FIELDS
      @fields_linked_data=ClinicalUtils::LABS_FIELDS_LINKED_DATA
      @reports_list=nil
      @specimen_defaults=nil
      @report_lab_types= {
        'chemistry' =>'CH',
        'microbiology' =>'MI',
        'hemotology' =>'HE',
        'pathology' => 'AP'
      }
    end
    
    # =============================================================================
    # =============================================================================
    # BEGIN API Methods
    # =============================================================================
    # =============================================================================

    # =============================================================================
    # Gets the most recent lab results
    #
    # @note path=most_recent
    #
    # =============================================================================
    def most_recent(session,conn,broker,dfn,paths)
      format=extract_format(conn,paths)
      count=conn.params['count']
      type=conn.params['type']
      to=broker.server_time()
      i=0
      state=start_line_data(conn,format,@fields)
      while( i<count && (to=get_labs(conn,broker,dfn,to,format,nil,type,state)))
        if to <0
          to=-to
        else
          i+=1
        end
      end
      return no_data(conn,format)  unless conn.response_body.size>0
      finish_line_data(conn,state)
    end


    # =============================================================================
    # Gets the summary of lab results
    #
    # @note path=summary
    # 
    # @note we send back the data in the same format as the list method
    # =============================================================================
    def summary(session,conn,broker,dfn,paths)
      if(conn.app.get_option("summary_shows_most_recent")==true)
        most_recent(session,conn,broker,dfn,paths)
      else
      format=extract_format(conn,paths)
      state=start_line_data(conn,format,@fields,@fields_linked_data)
      rpc = broker.rpc("ORWCV LAB", dfn)
      rpc.strip!
      return no_data(conn,format) if rpc=="^No orders found."
      rpc.each_line do |line|
        line.chomp!
        list = line.pieces("^", 1, 2, 3)
        list[2].fmdate!
        ClinicalUtils.create_labs_value_row(list, format, true, list[2], nil, "", list[0], list[1], nil)
        make_linked_data(list)
        send_line_data(conn,format,list,state)
      end
      finish_line_data(conn,state)
      end
    end
    
    # =============================================================================
    # Gets the microbiology results for a given date range
    #
    # @note path=microbiology
    # 
    # @param from [Time] from date/time - optional
    # @param to [Time] from date/time - optional
    #
    # @note we send the text report
    # =============================================================================
    def microbiology(session,conn,broker,dfn,paths)
      format=extract_format(conn,paths)
      from,to=ectract_from_to(conn.params,broker,paths);
      doc=broker.rpc("ORWLRR MICRO", dfn,to,from)
      return if doc.length() <20 and doc.include?(get_string('no_data_found','No Data Found'))
      send_text(conn,format,doc)
    end

    # =============================================================================
    # Gets the pathology results for a given date range
    #
    # @note path=pathology
    # 
    # @param from [Time] from date/time - optional
    # @param to [Time] from date/time - optional
    #
    # =============================================================================
    def pathology(session,conn,broker,dfn,paths)
      format=extract_format(conn,paths)
      from,to=ectract_from_to(conn.params,broker,paths);
      doc=broker.rpc("ORWRP REPORT TEXT", dfn,20,nil,0,nil,from,to)
      send_text(conn,format,doc)
    end
    
    # =============================================================================
    # Gets all chemistry for a given date range. If tests and specimen
    # are specified then only the results for the specified specimen/tests combination
    # will be returned
    #
    # @note path=list
    # 
    # @param from [Time] from date/time - optional
    # @param to [Time] from date/time - optional
    #
    #
    # @format id|test^value^unit^ref_range
    # =============================================================================
    def list(session,conn,broker,dfn,paths)
      format=extract_format(conn,paths,true)
      from,to=extract_from_to(conn.params,broker,paths)
      from=from.to_f if from
      to=to.to_f if to
      state=start_line_data(conn,format,@fields)
      begin
        to,header,list=get_labs(conn,broker,dfn,to,format,from)
        break unless to
        if list
          send_line_data(conn,format,header,state,false)
          list.each do |row|
          send_line_data(conn,format,row,state)
          end
        end
        to=-to if to <0
      end while to
      finish_line_data(conn,state)
    end
  
    # =============================================================================
    # =============================================================================
    # END API Methods
    # =============================================================================
    # =============================================================================
    
    # =============================================================================
    # Gets a set of labs
    #
    # @return the test date test that was found or nil if no test was found
    #         if the type parameter is not nil and a non-matching test was found
    #         then the returned value is the negative version of the test date
    # =============================================================================
    def get_labs(conn,broker,dfn,date,format,notbefore=nil,su=nil)
      @lab_categories=conn.app.get_option("lab_category_mapping") unless @lab_categories
      tz=broker.timezone()
      rpc=broker.rpc("ORWLRR INTERIMG", dfn,date,1,1)
      return if rpc.length==0
      fmdate=nil
      comment=nil
      lines=nil
      rpc.strip!
      list=rpc.split(get_string('clinical.labs.comment','Comment:'),2)
      if list.length>1
        comment=list[1]
        lines=list[0].split(/\n/)
        list=comment.split(get_string('clinical.labs.performing_lab','Performing Lab:'),2)
        comment=list[0]
        comment.strip!
      else
        list=rpc.split(get_string('clinical.labs.performing_lab','Performing Lab:'),2)
      end
      if list.length>1
        lines=list[0].split(/\n/) if !lines
        s=lines.shift
        s.strip!
        lab=list[1]
            
        if lab
          lab.strip!
          if lab.ends_with?(',')
            lab.chop!
            lab.strip!
          end
          p8=s.piece('^',8)
          lab << "^" << p8 if p8 and p8.length>0
          s.replace_piece!(lab, '^',8)
          list=s.split(/\^/)
          fmdate=list[2].to_f
          return [nil,nil,nil] if notbefore && fmdate < notbefore
          list[2].fmdate!
        end
      else
        list=list[0].split(/\n/,2)
        lines=list[1]
        list=list[0].split('^')
        fmdate=list[2].to_f
        return [nil,nil,nil] if notbefore && fmdate < notbefore
        list[2].fmdate! if list[2]
      end
      return [fmdate,nil,nil] unless lines
      if comment
        comment.lstrip!
      end
      su=su=StringUtils.new unless su
      comment="" unless comment
      category=list[1] || ""
      ldate="#{list[2]}#{tz}"
      header=Array.new(6)
      specimen=list[4] || ""
      accession=list[5] || ""
      requestor=list[6] || ""
      comment = su.title_case_escape(comment)
      specimen = su.title_case_escape(specimen)
      requestor = su.title_case_escape(requestor)
      info=create_result_info(accession,specimen,requestor,comment)
      info_name=get_string('clinical.labs.collection_info','Collection Info')
      #for the header he comment is part of the JSON d and we set comment to "true" if there is a comment
      ClinicalUtils.create_labs_value_row(header,format,ldate,nil,nil,"__CI__",info_name,info,nil,nil,nil,"true",nil,nil,nil,comment=="" ? "false" : "true")
      n=0
      out=[]
      categoryName=@lab_categories[category]
      categoryName =category unless categoryName
      if category=="CH" || category=="HE"
        lines.each do |line|
          n+=1
          break if n>2
          line.chomp!
          list=line.pieces('^',1,2,3,5,6,4)
          list[2].strip!
          list[1].downcase!
          list[1]=list[1].title_case
          abnormal=list[5]
          abnormal=nil if abnormal==""
          list[2]<< " (" << abnormal << ")" if abnormal
          row=Array.new(6)
          ClinicalUtils.create_labs_value_row(row, format, ldate, nil,nil, list[0], list[1], list[2], abnormal, list[3], list[4], nil,"#{category}|#{categoryName}")
          out << row
        end
      else
        report=lines
        ordered_string=get_string('clinical.labs.tests_ordered','Test(s) ordered:')
        test=rpc.split(ordered_string,2)
        if test.length==2
          lines=test[1].split(/\*/,2)[0]
          lines.strip!
          test=""
          if lines.lines.count <3 #if we have less the 3 tests then we extract those names
            lines.each_line do |line|
              n=line.index('completed:')
              line=line[0,n] if n
              line.strip!
              test << "; " if test.length>0
              test << line
            end
            test=su.title_case(test)
          end
          test=nil if test==""
        else
          test=nil
        end
        test=get_string("clinical.labs.#{category.downcase}_result","#{categoryName} Result") unless test
        row=Array.new(6)
        ClinicalUtils.create_labs_value_row(row, format, ldate, nil,nil, "", test, Base64.strict_encode64(text_to_html(report)), nil, nil, nil, "true","#{category}|#{categoryName}")
        out << row
      end
      return [fmdate,header,out]
    end
    def create_result_info(accession,specimen,requestor,comment)
     s=<<-MSG
     {
       "accessionNumber" : "#{accession}",
       "specimen" : "#{specimen}",
       "requestor" : "#{requestor}",
       "comment" : "#{comment}",
      }
      MSG
      return Base64.strict_encode64(s)
    end
  end
end