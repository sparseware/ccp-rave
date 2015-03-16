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


require 'java'
require 'appnativa.util.jar'
module Caching
  class CachedMap < Hash
    def initialize(callback=nil,timeout=nil)
      @time=Time.now
      @callback=callback
      @timeout=timeout
    end
    def time
      @time
    end
    def mark
      @time=Time.now
    end
    def callback
      @callback
    end
    def timedout(timeout)
      return (@time+@timeout)<Time.now if @timeout
      return (@time+timeout)<Time.now

    end
  end
  class CachedConcurrentMap < java.util.concurrent.ConcurrentHashMap
    def initialize(callback=nil,timeout=nil)
      @time=Time.now
      @callback=callback
      @timeout=timeout
    end
    def time
      @time
    end
    def mark
      @time=Time.now
    end
    def callback
      @callback
    end
    def timedout(timeout)
      return (@time+@timeout)<Time.now if @timeout
      return (@time+timeout)<Time.now
    end
  end
  
  class CachedArray < Array
    def initialize(callback=nil,timeout=nil)
      @time=Time.now
      @callback=callback
      @timeout=timeout
    end
    def time
      @time
    end
    def mark
      @time=Time.now
    end
    def callback
      @callback
    end
    def timedout(timeout)
      return (@time+@timeout)<Time.now if @timeout
      return (@time+timeout)<Time.now

    end
  end
  
  class ObjectCache
    def initialize(max,purge_ratio=0.25)
      @cache=com.appnativa.util.ObjectCache.new
      @cache.setBufferSize(max)
      @cache.setPuregRatio(purge_ratio)
    end
    def get_backing_cache
      return @cache
    end
    def [](key)
      return @cache.get(key)
    end

    def []=(key,value)
      @cache.put(key,value)
    end
    def purge
      @cache.purge()
    end
  end

  class CachedLists
    def purge
      @lists={}
    end
    def initialize(timeout)
      @timeout=timeout
      @lists={}
    end

    def get_list(app,session,name)
      list=@lists[name]
      if !list or list.timedout(@timeout)
        if list && list.callback
          list=list.callback.send(name.to_sym,app,session)
          list.mark
          @lists[name]=list
        end
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
  end
end