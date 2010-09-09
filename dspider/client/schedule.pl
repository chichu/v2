#!/usr/bin/perl -w
use strict;

my $server_root = $ARGV[0] ? $ARGV[0] : ".";

schedule("$server_root/crawclient.pl -f $server_root/crawclient.conf 2>&1 >> $server_root/client.log &", 1, 14400, "ps -ef | grep crawclient.pl | grep -v grep | wc -l");

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
