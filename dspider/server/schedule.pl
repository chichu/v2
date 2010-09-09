#!/usr/bin/perl -w
use strict;

my $server_root = $ARGV[0] ? $ARGV[0] : ".";

#for parser process
schedule("$server_root/parser_v3.pl -i 600 -f parser.cfg > log/parser.log 2>&1 &", 1, 14400, "ps -ef | grep parser_v3.pl | grep -v grep | wc -l");


sub schedule {
    my ($cmd, $count, $timeout, $ps_grep) = @_;
 
    my $cur_count = `${ps_grep}`;
    if ($cur_count < $count) {
        for (my $i=$cur_count;$i<$count;$i++) {
            #print "start process: " . $pid_file_prefix . "\n";
            system($cmd);
        }
    }   
}       
