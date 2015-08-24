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
  class Documents < ClinicalModule

    def initialize
      @fields='date^title^author^status^type^has_attachments^parent_id'.split(/\^/)
      @fields_linked_data=[true,nil,true,nil,nil,nil,nil]
      @document_class_mapping=nil
    end
    
    
    # =============================================================================
    # =============================================================================
    # BEGIN API Methods
    # =============================================================================
    # =============================================================================

    
    # =============================================================================
    # Signs the specified document
    #
    # @note path=sign/id
    #
    # @format true|false[^explanation if false]
    # =============================================================================
    def sign(session,conn,broker,dfn,paths)
      ien,format=extract_format_and_key(conn,paths)
      sig=conn.params['signature']
      bad_request unless sig
      rpc=broker.rpc("TIU SIGN RECORD",ien,broker.fix_signature(sig))
      rpc.strip!
      if rpc=="" || rpc.starts_with?("0")
        rpc.replace_piece!("true")
      else
        rpc.replace_piece!("false")
      end
      state=start_line_data(conn,format,"signed^failure_reason")
      send_line_data(conn,format,rpc,state,true)
      finish_line_data(conn,state)
    end



    # =============================================================================
    # Gets a list of clinical documents for the patient
    #
    # @note path=list[/clinical_notes | /discharge_summaries]
    #
    # @param from [Time] the start time - optional
    # @param to [Time] the end time - optional
    # @param author [FixedNum] the ien of the author  - optional
    # @param context [String] the context (signed, unsigned)
    # @param count [FixedNum] the maximum number of documents to return  - optional
    # @param filter [String] a regular expression to use to filter the documents   - optional
    # @param search_body [Boolean] true to load an search the body of documents; false to only search titles  - optional
    # 
    # @note the rows are in the form of 0=date,1=title,2=author,3=status,4=type,5=parent_id,6=has_attachments
    # =============================================================================
    def list(session,conn,broker,dfn,paths)
      format=extract_format(conn,paths)
      type=paths.shift
      array=[]
      args=create_args(conn.params,broker,paths)
      filter=args['filter']
      title_only_search=args['title_only_search']
      params=args['params']
      context=args['context']
      
      type="default" if !type || type==""
      case type
      when 'clinical_notes'
        get_list(array,conn,broker,dfn,3,context,params,filter,title_only_search)
      when 'discharge_summaries'
        get_list(array,conn,broker,dfn,244,context,params,filter,title_only_search)
      else
        get_list(array,conn,broker,dfn,3,context,params,filter,title_only_search)
        get_list(array,conn,broker,dfn,244,context,params,filter,title_only_search)
      end
      
      return no_data(conn,format) if array.length==0
      proccess_for_children(array)
      state=start_line_data(conn,format,@fields,@fields_linked_data)
      state.escape=true
      array.each do |row|
        send_line_data(conn,format,row,state)
      end
      finish_sending_data(conn,state,format)
    end
    
    # =============================================================================
    # Gets a document
    #
    # @note path=document/{id}
    #
    # @return the the text of the document
    # =============================================================================
    def document(session,conn,broker,dfn,paths)
      ien,format=extract_format_and_key(conn,paths,false)
      type=paths.shift
      if type=="detailed"
        doc=get_detailed_document(broker,ien)
      else
        doc=get_document(broker,ien)
      end
      send_text(conn,format,doc)
    end

    # =============================================================================
    # =============================================================================
    # END API Methods
    # =============================================================================
    # =============================================================================
    
    
    def fields
      return @fields
    end
    def fields_linked_data
      return @fields_linked_data
    end

    # =============================================================================
    # Gets a list of images for a document
    # broker returns:
    #  Array of "^" delimited Image information in the format :
    #   $P(1^2^3) IEN^Image FullPath and name^Abstract FullPath and Name
    #   $P(4)   SHORT DESCRIPTION field
    #   $P(5)   PROCEDURE/ EXAM DATE/TIME field
    #   $P(6)   OBJECT TYPE
    #   $P(7)   PROCEDURE field
    #   $P(8)   Procedure Date in Display format
    #   $P(9)   PARENT DATA FILE image pointer
    #   $P(10)   the ABSTYPE :  'M' magnetic 'W' worm  'O' offline
    #   $P(11)   Image accessibility   'A' accessable  or  'O' offline
    #   $P(12^13) Dicom Series number and Dicom Image Number
    #   $P(14)   Count of images in the group, or 1 if a single image
    #
    #   Note: the actuals broker response has an additional first element to the piece numbers above are offset by +1
    #
    #   rave returns:
    #    id|url^procedure_date_time^description^avaliable^dicom_series_num^dicom_image_num^num_images_in_group
    # =============================================================================
    def document_images(session,conn,broker,dfn,paths)
      ien,format=extract_format_and_key(conn,paths,false)
      lines=broker.rpc("MAG3 CPRS TIU NOTE",ien).split(/\n/)
      return if !lines || lines.length<2
      state=start_line_data(conn,format)
      lines.shift
      lines.each do |line|
        list=line.pieces('^',2,3,6,5,12,13,14,15)
        list[2].fmdate!
        list[4]=list[4]=='A' ? 'true' : 'false'
        list[1].tr!('\\','/')
        list[1]=broker.create_imaging_url(list[1])
        make_linked_data(list)
        send_line_data(conn,format,list,state,false)
      end
      finish_line_data(conn,state)

    end

    def needs_patient(symb)
      case symb
      when :document
        return false #allows us to retrieve a document without having selected a patient
      else
        return true
      end
    end
    
    # =============================================================================
    # Gets a list of documents
    #
    # @param outArray [Array] the array to use to store the documents
    # @param conn [Object] the connection
    # @param broker [Object] the broker
    # @param dfn  [String] the patient's ien
    # @param cls [String] the Vista document class
    # @param ctx [String] the Vista document context
    # @param params [Array] RPC parameters
    # @param filter [String] filter to use to filter results
    # @param title_only_search [Boolean] true if the filter is to be used on titles only; false otherwise
    # @param category [String] the category that these documents represents; this is sent back to the client
    # 
    # @note the rows are in the form of 0=id,1=date,2=title,3=author,5=status,5=type,6=parent_id,7=has_attachments,8=editable
    # =============================================================================
    def get_list(outArray,conn,broker,dfn, cls,ctx,params,filter=nil,title_only_search=false)
      retrieved=1
      found=-1
      last_id=0
      start_date=params[0].to_f
      end_date=params[1].to_f
      count=params[3].to_i
      all=false
      if count==0
        all=true
        count=9999999
      end
      retrieved=count+1 # add 1 so that we make a first pass
      su=StringUtils.new
      @document_class_mapping=conn.app.get_option("document_class_mapping") unless @document_class_mapping
      category=@document_class_mapping[cls];
      while start_date && start_date<=end_date and  count>0 and retrieved > count
        rpc = broker.rpc("TIU DOCUMENTS BY CONTEXT", cls,ctx, dfn, start_date,end_date,params[2],all ? 0 : count, params[4], params[5])
        retrieved,found,end_date,last_id=process_document_list(outArray,rpc,conn,broker,filter,title_only_search,last_id,category,su)
        count-=found
      end
    end
    
    # =============================================================================
    # Processes a list of documents and added them to the specified array
    #
    # @param outArray [Array] the array to use to store the documents
    # @param rpc [String] the response from the RPC broker
    # @param conn [Object] the connection
    # @param broker [Object] the broker
    # @param filter [String] filter to use to filter results
    # @param title_only_search [Boolean] true if the filter is to be used on titles only; false otherwise
    # @param skip  [String] the id of a document to skip (i.e. not add to this list)
    # @param category [String] the category that these documents represents; this is sent back to the client
    # @param su [Object] re-useable SirtUtils class
    # 
    # @note broker returns pieces #1=ien,2=title,3=reference date/time (int),4=patient name (last i/last 4),5=author
    #                              6=hospital location,7=signature status,8=visit date/time,9=discharge date/time
    #                              10=variable pointer to request,11=# of associated images,12=subject,
    #                              13=has children,14=ien of parent document,
    #
    # @note the rows are in the form of 0=id,1=date,2=title,3=author,5=status,5=type,6=has_attachments
    # 
    # @return [FixedNum,FixedNum, Float,FixedNum] the number of documents retrieved, the number of documents added to the array,the last FM date, and the id of the last document processed
    # =============================================================================
    def process_document_list(outArray,rpc,conn,broker,filter=nil,title_only_search=true,skip=0,category=nil,su=nil)
      su=StringUtils.new unless su
      found=0
      retrieved=0
      last_date=0
      unless category
      @document_class_mapping=conn.app.get_option("document_class_mapping") unless @document_class_mapping
        category=@document_class_mapping["3"];
      end
      title_only_search=true # no body search for
      rpc.each_line do |line|
        line.chomp!
        list = line.pieces("^", 1,3,2,5,7,6,11,14)
        if skip==list[0].to_i
          next
        end
        next if list[4]=="retracted"
        retrieved+=1
        if(filter)
          if not filter.match(list[2])
            next if title_only_search
            next if not filter.match(get_document(broker,list[0]))
          end
        end
        found+=1
        if list[6] and list[6].index(';')
          list[6]=list[6].split(/;/,2).reverse!.join('|')
        end
        last_date=list[1].to_f
        list[1].fmdate!
        list[5]=category
        skip=list[0].to_i
        list[2]=su.title_case(list[2])
        list[4]=su.title_case(list[4])
        s=list[3].pieces(';',1,3)
        list[3]=s.join('|')
        list[6]= list[6].to_i>0 ? "true" : "false"
        s=list[7]
        list[7]="" if s=="1"
        outArray << list
      end
      return [retrieved,found,last_date,skip]
    end

    protected
     def proccess_for_children(outArray)
       len=outArray.length
       hash={}
       (len-1).downto(0) do|i|
         list=outArray[i]
         pid=list[-1]
         if pid.to_i>1
           hash[pid]=pid;
         end
       end
       outArray.each do |list|
         pid=list[0]
         list[6]="true" if hash[pid]
         make_linked_data(list)
       end
     end
     
    def get_document(broker,ien)
      rpc = broker.rpc("TIU GET RECORD TEXT", ien)
      return rpc
    end

    def get_detailed_document(broker,ien)
      rpc = broker.rpc("TIU DETAILED DISPLAY", ien)
      return rpc
    end
    
    def finish_sending_data(conn,state,format)
      if conn.response_body.size==0
        no_data(conn,format) 
      end
      finish_line_data(conn,state)
    end
    
    def create_args(qp,broker,paths)
      type=paths.shift
      params=extract_from_to(qp, broker, paths)
      params[2]=qp['author']
      params[2]=0 if !params[2]
      params[3]=qp['count']
      params[4]='D'
      params[5]=1
      type=qp['context']
      filter=qp['filter']
      title_only_search=false
      title_only_search=true if qp['search_body'] and qp['search_body']=="false"
      begin
        filter=Regexp.new(filter, Regexp::IGNORECASE | Regexp::MULTILINE) if filter
      rescue
        bad_request
      end

      if type
        case type
        when 'uncosigned'
          ctx=3
        when 'unsigned'
          ctx=2
        when 'default'
          ctx=-5
        else
          if params[2]!=0
            ctx=4
          else if params[0]!=0 || params[1]!=0
              ctx=5
            else
              ctx=1
            end
          end
        end
      else
        ctx=1
      end
      return {
        'params'=>params,
        'filter'=>filter,
        'title_only_search'=>title_only_search,
        'context'=>ctx
      }
    end

    def fix_visit_string(visit)
      d=visit.piece(';')
    end

  end
end