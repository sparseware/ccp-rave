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

class XMLElement
  #@@dbf = com.appnativa.util.XMLUtils.getDocumentBuilderFactory()
  def initialize(node=nil,doc=nil)
    @node=node
    @doc=doc
  end
  def text
    s=@node.text_content
    return s ? s : ""
  end
  def set(node)
    @node=node
    @parent=nil
    return self
  end
  def document_element
    @node.child_nodes
  end
  def children
    @node.child_nodes
  end
  def to_s
    return com.appnativa.util.XMLUtils.toString(@node)
  end
  def parent
    @parent=XMLElement.new(@node.parent_node) unless @parent
    return @parent
  end
  def parent_node
    return @node.parent_node
  end
  def name
    @node.node_name
  end
  
  def node
    @node
  end

  def get_value(*name)
    item=get_ex(*name)
    s=item==nil ? nil : item.text_content
    return s ? s : ""
  end

  def get_value_ex(*name)
    item=get_ex(*name)
    s=item==nil ? nil : item.text_content
    return s
  end
  
  def dup
    return XMLElement.new(@node)
  end

  def get_nodes(name)
    return @node.getElementsByTagName(name)
  end

  def get_element(*name)
    node=get(*name)
    return node ? XMLElement.new(node) : nil
  end
  def get_element_ex(*name)
    node=get_ex(*name)
    return node ? XMLElement.new(node) : nil
  end
  
  def get_as_s(*name)
    node=get(*name)
    return node ? com.appnativa.util.XMLUtils.toString(node) : ""
  end
  def get(*name)
    len=name.length
    return nil unless len>0
    len-=1
    node=@node
    for i in 0..len
      list=node.getElementsByTagName(name[i])
      return nil if !list || list.length==0
      node=list.item(0)
    end
    return list.item(0)
  end
  def get_ex(*name)
    len=name.length
    return nil unless len>0
    len-=1
    node=@node
    for i in 0..len
      node=XMLElement::get_one(node,name[i])
      return nil unless node
    end
    return node
  end
  def self.get_one(node,name)
    list=node.child_nodes
    len=list==nil ? 0 : list.length-1
    for i in 0..len
      node=list.item(i)
      return node if node.node_name==name
    end
    return nil
  end

  def each(name=nil)
    list=name ? @node.getElementsByTagName(name) : @node
    i=0
    len=list.getLength()
    while i<len
      item=list.item(i)
      i+=1
      yield item
    end
  end
  def attributes(name)
    node=@node.getAttributes().getNamedItem(name)
    return node ? node.node_value : nil
  end
  def get_namespace_uri
    return @node.getNamespaceURI()
  end
  def self.from_string(s)
    doc = com.appnativa.util.XMLUtils.documentFromString(s)
    node = doc.get_document_element
    return XMLElement.new(node,doc)
  end
  def self.from_java_stream(stream)
    doc = com.appnativa.util.XMLUtils.documentFromStream(stream)
    node = doc.get_document_element
    return XMLElement.new(node,doc)
  end
  def self.from_href(href)
    doc = com.appnativa.util.XMLUtils.documentFromHref(href)
    node = doc.get_document_element
    return XMLElement.new(node,doc)
  end
  def self.from_input_source(source)
    doc = com.appnativa.util.XMLUtils.getDocumentBuilderFactory().new_document_builder.parse(source)
    node = doc.get_document_element
    return XMLElement.new(node,doc)
  end
end