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
  class Consults < ClinicalModule

    def initialize
      @service_types={
        'C' => 'C',
        'P' => 'P',
        'M' => 'CP',
        'I' => 'FC',
        'R' => 'FP',
      }
      #      @@service_types={
      #         'C' => 'Consult',
      #         'P' => 'Procedure',
      #         'M' => 'Clinical Procedure',
      #         'I' => 'Foreign Consult',
      #         'R' => 'Foreign Procedure',
      #      }
      @info_fields="document_count^consult_type^user_level^can_assoc_med^can_disassoc_med^can_restore_canceled^reason|can_edit^service_user^to_service^from_service^urgency^consult_location^id|requestor^result^in_out^findings"
      @fields='date^title^author^status^type^has_attachments^parent_id'.split(/\^/)
      @fields_linked_data=[true,nil,true,nil,nil,nil,nil]
    end

    # =============================================================================
    # =============================================================================
    # BEGIN API Methods
    # =============================================================================
    # =============================================================================

    
    #=============================================================================
    # Gets a consult
    # 
    # @note path=consult/{id}
    # 
    # @nore we send the text of the consult
    #=============================================================================
    def consult(session,conn,broker,dfn,paths)
      ien,format=extract_format_and_key(conn,paths)
      send_text(conn,format,broker.rpc("ORQQCN DETAIL", ien))
    end

    #=============================================================================
    # Gets a document that was attached to a consult.
    # This is the same as calling documents/document/{id}
    # 
    # @note path=document/{id}
    # 
    # @nore we send the text of the document
    #=============================================================================
    def document(session,conn,broker,dfn,paths)
      mod=conn.app.get_module_for("documents/list")
      mod.document(session,conn,broker,dfn,paths)
    end

  
    #=============================================================================
    # Gets a list of consults
    #
    # @note path=list
    # 
    # @param  from [Time] from date - optional 
    # @param  to [Time] to date - optional 
    # @param  service [String] service to use to restrict output - optional 
    # @param  status [String] status to use to restrict output - optional 
    # 
    # @note broker returns pieces 1=id,2=date/time of request,3=status,4=consulting service,5=type,6=service,7=display_name,8=order_id,9=type
    #
    # @note the rows are in the form of 0=date,1=title,2=author,3=status,4=type,5=parent_id,6=has_attachments
    #=============================================================================
    def list(session,conn,broker,dfn,paths)
      format=extract_format(conn,paths)
      from,to=extract_from_to(conn.params,broker,paths,true)
      status=conn.params["status"]
      service=conn.params["service"]
      if service
        os=service
        if service.to_i==0
          service=conn.app.get_cached_list(broker,"service_name_id_map")[service.upcase]
        else service=nil if !conn.app.get_cached_list(broker,"service_id_name_map").has_key?(service)
        end
        bad_request("invalid service:#{os}") if !service
      end

      rpc = broker.rpc("ORQQCN LIST", dfn, from,to,service,status)
      rpc.lstrip!
      return no_data(conn,format) if rpc.starts_with?("< PATIENT DOES NOT HAVE ANY CONSULTS/REQUESTS  ON FILE")
      mod=conn.app.get_module_for("documents/list")
      array=[]
      rpc.each_line do |line|
        line.chomp!
        list = line.pieces("^",1,2,7,999,3,5)
        list[1].fmdate!
        ien=list[0].dup
        make_linked_data(list)
        s=conn.app.get_cached_list(broker,"order_status_code_map")[list[3]]
        s='Other' if !s
        list[3]=s
        s=@service_types[list[7]]
        s=list[7]=="Consult" ? "C" : "P" if !s
        list[4]=s
        list[7]=""
        array << list
        process_consult(mod,array,conn,broker,ien)
      end
      state=start_line_data(conn,format,@fields,@fields_linked_data)
      array.each do |row|
        send_line_data(conn,format,row,state)
      end
      finish_line_data(conn,state)
    end

    # =============================================================================
    # =============================================================================
    # END API Methods
    # =============================================================================
    # =============================================================================
    
    
    ##
    # Processes a consult looking for child documents
    # 
    # @param [String] id the id of the consult
    ##
    def process_consult(mod,outArray,conn,broker,ien)
      rpc = broker.rpc("ORQQCN GET CONSULT", ien)
      #Broker documented return
      #     1    2    3     4     5     6    7    8   9    10   11  12   13     14    15
      #   EntDt^Pat^OrIFN^PtLoc^ToSvc^From^ReqDt^Typ^Urg^Place^Attn^Sts^LstAct^SndPrv^Rslt^
      #    16      17     18    19     20     21      22
      #  ^EntMode^ReqTyp^InOut^SigFnd^TIUPtr^OrdFac^FrgnCslt}
      return if rpc.starts_with?("-1")
      list=rpc.split(/\n/,2)
      return if list.length==1;
      rpc=list[1]
      rpc.strip!
      pos=outArray.length-1;
      row=outArray[pos]
      row[2]=list[0].piece('^',14);
      row[2].replace_char!(';','|')
      return if rpc==""
      row[5]="true"
      mod.process_document_list(outArray,rpc,conn,broker)
      pos+=1
      len=outArray.length-1;
      pos.upto(len) do |i|
        row=outArray[i]
        make_linked_data(row)
        row[6]=ien
      end
    end
  end
end
