#=============================================================================
#Copyright (c) SparseWare. All rights reserved.
#
#Use is subject to license terms.
#=============================================================================
#!/usr/bin/ruby
ARGV.push '--verbose'

ARGV.push '-b'
ARGV.push 'local'
ARGV.push '-m'
ARGV.push 'main'
$LOAD_PATH << File.expand_path(File.dirname(__FILE__)+'/sirf')
load 'server.rb'
run_rave()

