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


class ClinicalUtils
  VITALS_FIELDS="date^vital^result^unit^range^sort_order^result_id".split(/\^/)
  VITALS_FIELDS_LINKED_DATA=[true,true,true,nil,nil]

  LABS_FIELDS="date^lab^result^unit^range^is_document^category^panel^sort_order^result_id^comment".split(/\^/)
  LABS_FIELDS_LINKED_DATA=[true,true,true,nil,nil,nil,true,true,nil]

  def self.create_value_row(is_lab,out,format,date,order_id,result_id,key,name,val,abnormal,unit=nil,range=nil,is_document=nil,category=nil,panel=nil,sort_order="99999",comment=nil)
    color=abnormal=="*" ? "unknown" : "abnormal"

    out=Array.new(is_lab==true ? 10: 6) unless out
    out[0]=nil 
    case format
    when 'json'
      name.escape_string!
      val.escape_string!
      if order_id
        out[0] ="{\"value\":\"#{date}\",\"linkedData\":\"#{order_id}\"}"
      else
        out[0] =date
      end
      unit.escape_string! if unit
      range.escape_string! if range
      out[1] ="{\"value\":\"#{name}\",\"linkedData\":\"#{key}\"}"
      if abnormal
        val ="{\"value\":\"#{val}\",\"linkedData\":\"#{abnormal}\",\"fgColor\":\"#{color}\"}"
      end
    when 'none'
      out[0]="#{order_id}|#{date}"
      out[1]="#{key}|#{name}" 
      val ="#{abnormal}|#{val}" if abnormal
    when 'txt'
      out[0]="#{date}"
      out[1]="#{name}" 
      if is_lab==true
        out[10]=abnormal
    else
        out[7]=abnormal
      end
    else
      name.escape_string_quote_if_necessary!
      val.escape_string_quote_if_necessary!
      out[1]="#{key}|#{name}" 
      val="#{abnormal}|#{val}{fgColor: #{color}}" if abnormal
      if order_id
        out[0]="#{order_id}|#{date}"
      else
        out[0]=date
      end
      unit.escape_string_quote_if_necessary! if unit
      range.escape_string_quote_if_necessary! if range
    end
    out[2]=val
    out[3]=unit
    out[4]=range
    if is_lab==true
      out[5]=is_document
      out[6]=category
      out[7]=panel
      out[8]=sort_order
      out[9]=result_id
      out[10]=comment
    else
      out[5]=sort_order
      out[6]=result_id
    end
    return out
  end
  def self.create_labs_value_row(out,format,date,order_id,result_id,key,name,val,abnormal,unit=nil,range=nil,is_document=nil,category=nil,panel=nil,sort_order="99999",comment=nil)
    ClinicalUtils.create_value_row(true,out,format,date,order_id,result_id,key,name,val,abnormal,unit,range,is_document,category,panel,sort_order,comment)
  end

  def self.create_vitals_value_row(out,format,date,order_id,result_id,key,name,val,abnormal,unit=nil,range=nil,sort_order="99999")
    ClinicalUtils.create_value_row(false,out, format,  date, order_id, result_id,key, name, val, abnormal, unit, range, nil,nil,nil,sort_order)
  end
  
end