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
class StringUtils
  def initialize
    @ca=com.appnativa.util.CharArray.new
    @ca_out=com.appnativa.util.CharArray.new
  end
  def title_case(s)
    return "" unless s && s.length >0
    return @ca.set(s).toTitleCase().toString()
  end
  def title_case_escape(s)
    return "" unless s && s.length >0
    ca=@ca
    ca.set(s)
    ca.toTitleCase()
    @ca_out._length=0
    return com.appnativa.util.CharScanner.escape(ca.A,0,ca._length,true,@ca_out).toString()
  end
  
  def title_case_escape_html(s)
    return "" unless s && s.length >0
    ca=@ca
    ca.set(s)
    ca.toTitleCase()
    @ca_out._length=0
    return com.appnativa.util.XMLUtils.escape(ca.A,0,ca._length,true,@ca_out).toString()
  end

  def to_base64(s)
    return "" unless s && s.length >0
    com.appnativa.util.Base64.encodeUTF8(s)
  end
  
  def from_base64(s)
    return "" unless s && s.length >0
    com.appnativa.util.Base64.decodeUTF8(s)
  end
  
  def self.html_to_text(html)
    kit=javax.swing.text.html.HTMLEditorKit.new()
    doc=kit.createDefaultDocument()
    r=java.io.StringReader.new(html)
    kit.read(r,doc,0)
    return doc.getText(0,doc.getLength())
  end
end
class DateUtils
  def initialize
    @cal=java.util.Calendar.getInstance()
  end
  def now
    @cal.setTimeInMillis(java.lang.System.currentTimeMillis())
    return @cal
  end
  def to_display_string(standard_format)
    com.appnativa.util.Helper.setDateTime(standard_format,@cal,true)
    @d_format=com.appnativa.util.SimpleDateFormatEx.new("MMM dd, yyyy'@'HH:mm") unless @d_format
    return @d_format.format(@cal.getTime())
  end
  def to_standard_string(spec)
    @format=com.appnativa.util.SimpleDateFormatEx.new("yyyy-MM-dd'T'HH:mm:ss.SSSZ") unless @format
    return @format.format(com.appnativa.util.Helper.createCalendar(spec).getTime())
  end
end