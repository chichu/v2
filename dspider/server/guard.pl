#!/usr/bin/perl -w
use strict;

my $server_root = $ARGV[0] ? $ARGV[0] : ".";

#for Start dspider Sserver process
foreach my $p_name ("crawserver.pl", "reciever.pl")
{
	$p_name =~ /(.*)\.pl/m;
	my $log_name = $1 . ".log";

	schedule("$server_root/$p_name >> log/$log_name 2>&1 &", 1, 14400, "ps -ef | grep $p_name | grep -v grep | wc -l");
}


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
