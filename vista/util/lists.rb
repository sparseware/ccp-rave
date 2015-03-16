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
    class Lists < RestrictedModule
      def initialize
        @category_fields   =["name"]
        @category_fields_linked_data=[true]
        @location_fields   =["name","facility"]
        @location_fields_linked_data=[true,true]
      end
      
    # =============================================================================
    # =============================================================================
    # BEGIN API Methods
    # =============================================================================
    # =============================================================================

      def teams(session,conn,broker,paths)
        format=extract_format(conn,paths,true)
        get_list(session,conn,broker,"teams",format)
      end
      
      def units(session,conn,broker,paths)
        format=extract_format(conn,paths,true)
        get_list(session,conn,broker,"units",format)
      end
      
      def clinics(session,conn,broker,paths)
        format=extract_format(conn,paths,true)
        get_list(session,conn,broker,"clinics",format)
      end
      
      def specialities(session,conn,broker,paths)
        format=extract_format(conn,paths,true)
        get_list(session,conn,broker,"specialities",format)
      end
      
      def providers(session,conn,broker,paths)
        format=extract_format(conn,paths,true)
        get_list(session,conn,broker,"providers",format)
      end
      
      def facilities(session,conn,broker,paths)
        format=extract_format(conn,paths,true)
        return no_data(conn,format) 
      end
      
    # =============================================================================
    # =============================================================================
    # END API Methods
    # =============================================================================
    # =============================================================================

      def get_list(session,conn,broker,name,format)
        rpc=nil
        change_case=true
        case name
        when 'teams'
          rpc='ORQPT TEAMS'
          fields=@category_fields
          ld_fields=@category_fields_linked_data
        when 'providers'
          rpc='ORQPT PROVIDERS'
          fields=@category_fields
          ld_fields=@category_fields_linked_data
        when 'clinics'
          rpc='ORQPT CLINICS'
          fields=@location_fields
          ld_fields=@location_fields_linked_data
        when 'units'
          rpc='ORQPT WARDS'
          change_case=false
          fields=@location_fields
          ld_fields=@location_fields_linked_data
        when 'specialities'
          rpc='ORQPT SPECIALTIES'
          fields=@category_fields
          ld_fields=@category_fields_linked_data
        end
        return not_found if rpc==nil
        res = broker.rpc(rpc)
        res.strip!
        return no_data(conn,format) if res.piece('^',1)==""
        
        state=start_line_data(conn,format,fields,ld_fields)
        su=StringUtils.new
        res.each_line do |line|
          line.chomp!
          line.tr!('^','|')
          line=su.title_case(line) if change_case
          send_line_data(conn,format,line,state,true)
        end
        finish_line_data(conn,state)
      end
    end
  end
end