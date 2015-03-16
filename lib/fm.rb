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
   module FM
      FILE='"FILE"'.freeze
      FIELDS='"FIELDS"'.freeze
      FROM='"FROM"'.freeze
      MAX='"MAX"'.freeze
      PART='"PART"'.freeze
      FLAGS='"FLAGS"'.freeze
      IENS='"IENS"'.freeze
      XREF='"XREF"'.freeze
      VALUE='"VALUE"'.freeze
      SCREEN='"SCREEN"'.freeze
      FILE_MAPINGS=YAML.load_file(File.join(File.dirname(__FILE__), "fm_file_mappings.yml"))
      FILE_DEFAULT_FIELDS_MAPINGS=YAML.load_file(File.join(File.dirname(__FILE__), "fm_file_def_fields_mappings.yml"))
      MAX_DEFAULT = 100
   end
end
