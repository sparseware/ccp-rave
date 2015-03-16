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


require 'socket'
require 'date'
require 'digest/sha1'
require 'date'
# =============================================================================
# Modified string class
# =============================================================================
class String
  @@months={
    "JAN"=>"01",
    "FEB"=>"02",
    "MAR"=>"03",
    "APR"=>"04",
    "MAY"=>"05",
    "JUN"=>"06",
    "JUL"=>"07",
    "AUG"=>"08",
    "SEP"=>"09",
    "OCT"=>"10",
    "NOV"=>"11",
    "DEC"=>"12"
  }
  def is_numeric?
    n=self.to_i
    self=="0" ? true : false
    return (self=="0" ? true : false) if n==0
    return self.gsub(/[^\d+]/,'')==self if n>0
    return self.gsub(/[^\d+]/,'')==self[1..-1]
  end
  def html_to_text
    s=self.dup
    s.html_to_text!
    return s
  end

   def html_to_text!
    self.gsub!(/\n/,"")
    self.gsub!(/<(br|BR)\s*[^>]+>/,"\n")
    self.gsub!(/<(p|P)\s*[^>]+>/,"\n\n")
    self.gsub!(/<\s*\/?\s*[^>]+>/,'')
    self.unescape_html!
    return self
  end

  def escape_html
    s=self.dup
    s.escape_html!
    return s
  end
  def escape_html!
    if self.length>0
      self.gsub!(/&/n, '&amp;')
      self.gsub!(/\"/n, '&quot;')
      self.gsub!(/>/n, '&gt;')
      self.gsub!(/</n, '&lt;')
      self.gsub!(/\t/n, '&#x0009;')
    end
    return self
  end
  def escape_string
    s=self.dup
    s.escape_string!
    return s
  end
  def escape_string_quote_if_necessary
    s=self.dup
    s.escape_string_quote_if_necessary!
    return s
  end
  def escape_string!
    if self.length>0
      self.gsub!(/\r/n, "")
      self.gsub!(/\n/n, "\\n")
      self.gsub!(/\t/n, "\\n")
      self.gsub!(/\"/n, "\\\"")
    end
    return self
  end
  def escape_string_quote_if_necessary!
    len=self.length
    if len>0
      self.gsub!(/\r/n, "")
      self.gsub!(/\n/n, "\\n")
      self.gsub!(/\t/n, "\\n")
      self.gsub!(/\"/n, "\\\"")
      if len!=self.length || self.index('\'') || self.index('^')
        self.insert(0,"\"")
        self  << "\""
      end
    end
    return self
  end
  def unescape_html
    s=self.dup
    s.unescape_html!
    return s
  end
  def unescape_html!
    if self.length>0
      self.gsub!(/&(amp|quot|gt|lt|nbsp|\#[0-9]+|\#x[0-9A-Fa-f]+);/n) do
        match = $1.dup
        case match
        when 'amp'                 then '&'
        when 'quot'                then '"'
        when 'gt'                  then '>'
        when 'nbsp'                  then ' '
        when 'lt'                  then '<'
        when /\A#0*(\d+)\z/n       then
          if Integer($1) < 256
            Integer($1).chr
          else
            if Integer($1) < 65536 and ($KCODE[0] == ?u or $KCODE[0] == ?U)
              [Integer($1)].pack("U")
            else
              "&##{$1};"
            end
          end
        when /\A#x([0-9a-f]+)\z/ni then
          if $1.hex < 256
            $1.hex.chr
          else
            if $1.hex < 65536 and ($KCODE[0] == ?u or $KCODE[0] == ?U)
              [$1.hex].pack("U")
            else
              "&#x#{$1};"
            end
          end
        else
          "&#{match};"
        end
      end
    end
    return self
  end
  
  def char_at(pos)
    return self[pos,1]
  end
  
  def starts_with?(str)
    return false if !str or str.length>self.length
    return self[0,str.length]==str
  end
  def ends_with?(str)
    return false if !str or str.length>self.length
    return self.index(str,self.length-str.length)!=nil
  end
  def fix_expanded_date(sep='@',sep2='/')
    return self.dup.fix_expanded_date!(sep,sep2)
  end
  def fix_expanded_date!(sep='@',sep2='/')
    return if empty?
    self.strip!
    begin
      line=self.split(sep,2)
      s=line[0].pieces(sep2,3,1,2)
      s[2] << 'T' << line[1] if line[1]
      if s[0].length==2
        i=s[0].to_i() +1900
        i=i+100 if i <1950
        s[0]=i.to_s
      elsif s[0].length==0
         s[0]=@@months[s[1].piece(' ',1)]
         s[1]=s[1].piece(' ',2)
         if s[1].length==1
           s[1]="0#{s[1]}"
         end
      end
      self.replace(s.join('-'))
    rescue #leave unchanged (other than the strip)
    end
  end
  def to_fmdate!
    return "" if empty?
    if self=="0"
      self.chop!
      return self
    end
    self.replace(to_fmdate)
  end

  def to_fmdate
    return "" if empty? || self=="0"
    if self.index ' '
      /^(\d\d\d\d)-(\d\d)-(\d\d)[ T](\d\d):(\d\d)(?::(\d\d))?(?: (AM|PM))?(?: ([+-]\d\d\d\d))?$/.match(self)
    else
      /^(\d\d\d\d)-(\d\d)-(\d\d)$/.match(self)
    end
    year    =$1
    month   =$2
    day     =$3
    hour    =$4
    min     =$5
    sec     =$6
    am_pm   = $7
    tz      = $8

    raise "invalid date (#{self})" if year==nil || month==nil or day==nil

    date=year.to_i
    date -= 1700
    date *= 10000
    date += 100 * month.to_i
    date += day.to_i
    if hour
      hour=hour.to_i
      hour=hour+12 if am_pm=="PM"
      hour=hour%24
      time = hour *10000
      time += (min.to_i * 100) if min
      time += sec.to_i if sec
      date=date.to_s+"."+time.to_s
    else
      date=date.to_s
    end
    return date
  end

  def fmdate(fmt=nil, hms=nil)
    return "" if empty?
    if self.strip =~ /^(\d{3})(\d{2})(\d{2})(?>.(\d+))?$/
      year  = 1700 + $1.to_i
      month = $2.to_i
      day   = $3.to_i
      time  = $4
      if time
        fmt||= "%Y-%m-%dT%H:%M"
        fmt += hms if hms
        time = time.ljust(6, "0")
        hour = time[0,2].to_i
        mins = time[2,2].to_i
        secs = time[4,2].to_i
      else
        fmt||= "%Y-%m-%d"
        hour = mins = secs = 0
      end
      month = 1 if month == 0 #!# need to be able to handle "fuzzy" dates
      day   = 1 if day   == 0 #!# need to be able to handle "fuzzy" dates
      return DateTime.new(year, month, day, hour, mins, secs).strftime(fmt)
    else
      return self
    end
  end

  def fmdate!(*args)
    return "" if empty?
    self.replace(fmdate(*args))
  end

  def count_token(tok='^')
    n  = 1
    i  = 0
    tl = tok.length

    while (i = self.index(tok, i))
      i += tl
      n +=1
    end

    return n
  end

  def piece(tok="^", first=1,last=nil)
    i   = 0
    n   = 1
    oi  = 0
    pos = 0
    tl  = tok.length
    last=first if !last

    return "" if last < 1 or last < first or tl == 0

    while n < first and (i = self.index(tok, i))
      i += tl
      n=n+1
    end

    return "" if n < first or !i

    oi = i
    i  = self.index(tok, i)

    return self[oi..-1] if !i

    if first == last
      return "" if oi == i
      return self[oi..i-1]
    end

    pos = oi
    i   += tl

    while n < last and (i = self.index(tok, i))
      n += 1
      i += tl
    end

    return self[pos..-1] if !i

    i -= tl

    return "" if pos == i
    return self[pos..i-1]
  end
  
  def change_char_delim(from='^',to='|' *who)
    return self.dup.change_char_delim!(from,to,who)
  end
  
  def change_char_delim!(from='^',to='|', *who)
    who = [1] if who.empty?
    len=who.length
    n=1
    i=0
    num=who[0]
    while len>0 and (i = self.index(from, i))
      if n==num
        self[i] = to
        len     -=1
        num     =who[n]
      end
      n += 1
      i += 1
    end
    return self
  end

  ##
  # Replaces one character with another
  #
  # @param what the character to replace
  # @param with the replacement character
  # @return the number of characters replaced
  #
  def replace_char!(what,with)
    return 0 if empty?
    n=0
    i=0
    while (i = self.index(what, i))
      self[i]=with
      i += 1
      n +=1
    end
    return n
  end
  def replace_piece(val,tok="^",first=1,last=nil)
    self.dup.replace_piece!(val,to,first,last)
  end
  def replace_piece!(val,tok="^",first=1,last=nil)
    i   = 0
    n   = 1
    oi  = 0
    pos = 0
    tl  = tok.length
    last=first if !last
    return self if last < 1 or last < first or tl == 0

    while n < first and (i = self.index(tok, i))
      i += tl
      n += 1
    end

    if n < first or !i
      while n!=first
        n +=1
        self << tok
      end
      return self << val
    end

    oi = i
    i  = self.index(tok, i)
    if !i
      self[oi..-1]=val
      return self
    end

    if first == last
      self[oi..i-1]=val
      return self
    end

    pos = oi
    i   += tl

    while n < last and (i = self.index(tok, i))
      n += 1
      i += tl
    end

    if !i
      self[pos..-1]=val
      return self
    end
    return self[pos..-1] if !i

    i -= tl

    if pos == i
      self << val
    else
      self[pos..i-1]=val
    end
    return self
  end
  def pieces(del="^", *who)
    out = split(del, -1).unshift('')
    if who == [0]
      def out.[](pos)
        self.fetch(pos, '')
      end
    else
      who = [1] if who.empty?
      out = out.values_at(*who).map {|val| val||''}
    end
    out.size == 1 ? out.first : out
  end
  
  # Copyright (c) 2006-2007 Justin French
  #
  # Permission is hereby granted, free of charge, to any person obtaining
  # a copy of this software and associated documentation files (the
  # "Software"), to deal in the Software without restriction, including
  # without limitation the rights to use, copy, modify, merge, publish,
  # distribute, sublicense, and/or sell copies of the Software, and to
  # permit persons to whom the Software is furnished to do so, subject to
  # the following conditions:
  #
  # The above copyright notice and this permission notice shall be
  # included in all copies or substantial portions of the Software.
  #
  # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
  # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
  # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
  # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
  # LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
  # OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
  # WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

  #require 'html/tokenizer'
  #require 'html/node'


  # Capitalizes only the first character of a string (unlike "string".capitalize), leaving the rest
  # untouched.  spinach => Spinach, CD => CD, cat => Cat, crAzY => CrAzY
  def capitalize_first
    string = self[0,1].capitalize + self[1, self.length]
    return string
  end

  # Capitalizes the first character of all words not found in words_to_skip_capitalization_of()
  # Examples of skipped words include 'of', 'the', 'or', etc.  Also capitalizes the first character
  # of the string regardless.
  def capitalize_most_words
    self.split.collect{ |w| words_to_skip_capitalization_of.include?(w.downcase) ? w : w.capitalize_first }.join(" ").capitalize_first
  end
  def title_case
    return "" if self.length==0
    self.split.collect{ |w| words_to_skip_capitalization_of.include?(w.downcase) ? w : w.capitalize_first }.join(" ").capitalize_first
  end

  # Capitalizes the first character of all words in string
  def capitalize_words
    self.split.collect{ |s| s.capitalize_first }.join(" ")
  end

  def strip_html
    if self.index("<")
      result = ""
      tokenizer = HTML::Tokenizer.new(self)

      while token = tokenizer.next
        node = HTML::Node.parse(nil, 0, 0, token, false)
        # result is only the content of any Text nodes
        result << node.to_s if node.class == HTML::Text
      end
      # strip any comments, and if they have a newline at the end (ie. line with
      # only a comment) strip that too
      result.gsub!(/<!--(.*?)-->[\n]?/m, "")
      return result
    else
      return self # already plain text
    end
  end

  private

  # Defines an array of words to which capitalize_most_words() should skip over.
  # TODO: Should "it" be included in the list?
  def words_to_skip_capitalization_of
    [
      'of','a','the','and','an','or','nor','but','if','then','else','when','up','at','from','by','on',
      'off','for','in','out','over','to'
    ]
  end
end
class DateTime
  def to_fmdate(time=true)
    date=year()
    date -= 1700
    date *= 10000
    date += 100 * month()
    date += day()
    if time
      hour=hour()
      time = hour *10000
      time += (min() * 100)
      time += sec()
      dec = 0 #Math.log10(time)%60

      dec+=1;
      if hour<10
        date=date.to_s+".0"+time.to_s
      else
        date=date.to_s+"."+time.to_s
      end
    else
      date=date.to_s
    end
    return date

  end
  def self.from_fmdate(str)
    return nil if str.empty?
    if str.strip =~ /^(\d{3})(\d{2})(\d{2})(?>.(\d+))?$/
      year  = 1700 + $1.to_i
      month = $2.to_i
      day   = $3.to_i
      time  = $4
      if time
        time = time.ljust(6, "0")
        hour = time[0,2].to_i
        mins = time[2,2].to_i
        secs = time[4,2].to_i
      else
        hour = mins = secs = 0
      end
      month = 1 if month == 0 #!# need to be able to handle "fuzzy" dates
      day   = 1 if day   == 0 #!# need to be able to handle "fuzzy" dates
      return DateTime.new(year, month, day, hour, mins, secs)
    else
      return nil
    end
  end
end