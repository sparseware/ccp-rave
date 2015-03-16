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
module Rave
  require "caching"

  #=============================================================================
  # This class represents cached lists that are populated via RPC calls.
  # These RPC are for data that is fairly static. If a list is requested an
  # it is not found in the name map then the name of the list is converted to
  # a symbol and this class is check for a method matching that symbol. If one
  # is found, that method is invoked to populate the list.
  # 
  # NOTE: If the last underscore piece of a list name is 2 characters of less 
  #       then those characters are treated as sorting/case conversion
  #       instructions. Use 's' to sort and an 't' to convert to title case
  # 
  # 
  #=============================================================================
  class CachedLists < Caching::CachedLists
    def initialize(timeout,rpc_lists=nil)
      super timeout
      @rpc_lists=rpc_lists==nil ? {} : rpc_lists.dup
    end
    
    #=============================================================================
    # Adds a list to be cached
    # 
    # @param name the name of the list
    # @param rpc the name of the RPC to use to populate the list
    #=============================================================================
    def add_rpc_list(name, rpc)
      @rpc_lists[name]=rpc
    end
    
    #=============================================================================
    # Creates query parameters fro a FM search using the "DDR LISTER" RPC
    # 
    # @param file the FM file (native FM format)
    # @param fields the FM fields (native FM format)
    # @param flags the FM search flags
    # @param xref the FM cross reference to search
    #=============================================================================
    def query_params(file,fields=nil,flags=nil,xref=nil)
      params={}
      fields=".01" if !fields
      params[FM::FILE]=file
      params[FM::FIELDS]= fields
      params[FM::FLAGS]=flags if flags
      params[FM::XREF]=xref if xref
      params[FM::FIELDS]="@;"+params[FM::FIELDS]
      return params
    end

    def get_list(app,session,name)
      return get_broker_list(app,session.broker,name)
    end
    def get_list_ex(app,broker,name)
      list=@lists[name]
      if !list or list.timedout(@timeout)
        if list && list.callback
          list=list.callback.send(name.to_sym,app,broker)
        else
          rpc=@rpc_lists[name]
          if rpc
            list=create_rpc_list(broker,rpc,name)
          else
            list=self.send(name.to_sym,app,broker)
          end
        end
        list.mark
        @lists[name]=list
      end
      return list
    end

    def has_list?(name)
      return @lists[name]!=nil || @rpc_lists[name]!=nil
    end

    def set_list(name,list)
      ol=@lists[name]
      @lists[name]=list
      return ol
    end

    def order_status_id_list(app,broker)
      rpc=broker.rpc("ORQQCN STATUS")
      rpc.strip!
      map=Caching::CachedMap.new()
      rpc.each_line do |line|
        line.chomp!
        id,name=line.pieces('^',1,2)
        name.strip!
        map[id]=name
      end
      list=Caching::CachedArray.new()
      map.sort{|a,b| a[1]<=>b[1]}.each { |elem|
        list << (elem[0]+"|"+elem[1])
      }
      return list
    end

    def order_status_code_map(app,broker)
      rpc=broker.rpc("DDR LISTER",query_params("100.01",".1;.01"))
      rpc.strip!
      su=StringUtils.new

      map=Caching::CachedMap.new
      rpc.each_line do |line|
        next if line.starts_with?("[Data]")
        line.chomp!
        id,name=line.pieces('^',2,3)
        name.strip!
        map[id]=su.title_case(name)
      end
      return map

    end
    def service_name_id_map(app,broker)
      nmap=get_list_ex(app,broker,"service_id_name_map")
      map=Caching::CachedMap.new()
      su=StringUtils.new
      nmap.each do |k,v|
        map[v]=su.title_case(k)
      end
      return map
    end
    def service_name_id_list(app,broker)
      map=get_list_ex(app,broker,"service_id_name_map")
      list=Caching::CachedArray.new()
      map.sort{|a,b| a[1]<=>b[1]}.each { |elem|
        list << (elem[0]+"|"+elem[1])
      }
      return list
    end
    def service_id_name_map(app,broker)
      map=Caching::CachedMap.new()
      start=""
      finished=false
      count=0
       su=StringUtils.new
      while !finished || count>10000
        count+=1
        rpc=broker.rpc("ORQQCN SVCLIST",start,1)
        rpc.strip!
        break if rpc.length()==0
        rpc.each_line do |line|
          line.chomp!
          id,name=line.pieces('^',1,2)
          if id==""
            finished=true
            break
          end
          name.strip!
          map[id]=su.title_case(name)
          start=name
        end
      end
      return map
    end
    def exam_result_list(app,broker)
      rpc=broker.rpc("ORWPCE GET SET OF CODES", "9000010.13", ".04", "1")
      return build_list(rpc,"exam_result_list")
    end
    def education_understanding_level_list(app,broker)
      rpc=broker.rpc("ORWPCE GET SET OF CODES", "9000010.16", ".06", "1")
      return build_list(rpc,"education_understanding_level_list")
    end
    def skin_test_result_list(app,broker)
      rpc=broker.rpc("ORWPCE GET SET OF CODES", "9000010.12", ".04", "1")
      return build_list(rpc,"skin_test_result_list")
    end
    def immunization_series_list(app,broker)
      rpc=broker.rpc("ORWPCE GET SET OF CODES", "9000010.11", ".04", "1")
      return build_list(rpc,"immunization_series_list")
    end
    def immunization_reaction_list(app,broker)
      rpc=broker.rpc("ORWPCE GET SET OF CODES", "9000010.11", ".06", "1")
      return build_list(rpc,"immunization_reaction_list")
    end
    def hf_severity_items_list(app,broker)
      rpc=broker.rpc("ORWPCE GET SET OF CODES", "9000010.23", ".04", "1")
      return build_list(rpc,"hf_severity_items_list")
    end
    def create_rpc_list(broker,rpc,name)
      return build_list(broker.rpc(rpc),name)
    end

    def build_list(rpc,name)

      rpc.replace_char!('^','|')
      n=name.rindex('_')
      title_case=false
      sort=false
      if n
        name=name[n+1..-1]
        if name.length<3 # if the last underscore piece is 2 characters of less then treat as sorting/case conversion instructions
          sort=name.include?("s")
          title_case=name.include?("t")

        end
      end
      list=Caching::CachedArray.new()
      map={} if sort
      rpc.each_line do |line|
        line.chomp!
        unless title_case || sort
          list << line.piece('|',1,2)
        else
          a=line.pieces('|',1,2)
          if title_case
            a[1].downcase!
            a[1]=a[1].title_case
          end
          if sort
            map[a[0]]=a[1]
          else
            list << a.join('|')
          end
        end
      end
      if sort
        map.sort{|a,b| a[1]<=>b[1]}.each { |elem|
          list << (elem[0]+"|"+elem[1])
        }
      end
      return list
    end
  end
end