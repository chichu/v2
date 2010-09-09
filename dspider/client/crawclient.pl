#! /usr/bin/perl -w
use strict;
use IO::Socket;
use POSIX;
use File::Path;
use POSIX qw(:sys_wait_h);
use Cwd qw(realpath);
autoflush STDOUT 1;

my $self_name = $0;
sub usage {
	return
	"usage: $self_name [cfgsections] [options]\n".
	"options:\n".
	"\t-f\t\tconfig file, default is crawclient.conf\n".
	"\t-h/--help\tshow this message\n"
	;
}

# check for one instance
my $mycount=`ps -ef | grep $self_name | grep -v grep | grep -v vi | wc -l`;
if ($mycount > 1) { exit 0; }
	
# global variables
my $conf_file = "crawclient.conf";	# 所有抓取端共同的配置
my $limit_file = "limits";		# 根据机器情况可有不同
my @get_hosts;				# 服务器列表
my $get_host_index = 0;			# 当前使用的索引
my $get_port;				# 服务器端口
my $limits = [];			# 负载的限制
my $timelimits = {};			# 时段的限制
my $spacelimit = 0;			# 磁盘空间的限制
my $timeout = 120;
my $stop_get = 0;			# 停止取url的标志，用于控制程序退出
my $PREFORK                = 10;        # number of children to maintain
my $maxchild		= 10;
my $NUMSEND                = 50;        # number of file to send
my $CHECKINT		= 3600 * 24;		# 检查间隔
my %childmap               = ( );       # keys are current child process IDs
my $curchild               = 0;		# current number of children
my @data = ();				# list of recieved data
my $fileno = 1;				# current file no.
#my $savepath = 0;			# use this number as pathname
#my $workpath = realpath(".");		# 当前真实目录
my $workpath;				# 当前真实目录
my $updatemodule;			# 自动更新的远程rsync模块
my $wgetoption = " --user-agent='Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 5.1; .NET CLR 1.1.4322)' --header='Accept-Language: zh-cn' --tries=3 2>wgetlog";
my $curloption = " -A 'Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 5.1; .NET CLR 1.1.4322)' -H 'Accept-Language: zh-cn' -L --connect-timeout 30 -m 120 -v -g 2>curllog";

sub parsecmd {
        my $conf_file;
        my @names;
        while (my $arg = shift @ARGV) {
                if ($arg eq "--help") {
                        return 0;
                } elsif ($arg eq "-h") {
                        return 0;
                } elsif ($arg eq "-f") {
                        $arg = shift @ARGV or return 0;
                        $conf_file = $arg;
                } elsif ($arg =~ /^-.*/) {
                        return 0;
		}
        }
	readconf($conf_file);
        return 1;
}


#################################################

#parse cli parameter
die usage() unless parsecmd();

# Install signal handlers.
$SIG{CHLD} = \&REAPER;
#$SIG{INT}  = \&HUNTSMAN;
$SIG{INT} = $SIG{TERM} = $SIG{HUP} = \&signal_handler;
# main loop
my $time_to_die = 0;
my $loopcount = 0;
my $limited = 0;
my $g_mtime = checkmodify($conf_file);
#mkpath("data/".$savepath);

loadandsave(1);
while(!$time_to_die) {
	if ($loopcount % 5 == 0) {
		print "curchild:$curchild,maxchild:$maxchild,time_to_die:$time_to_die,stop_get:$stop_get,limited:$limited\n";
		# check modify
		my $mtime = checkmodify($conf_file);
		if ($g_mtime < $mtime || $mtime == 0) { $stop_get = 1; }
		# check limit
		if (checklimit() == 1 || checkspacelimit() == 1) {
			$limited = 1;
			print "limited------------------------ \n";
		} else {
			$limited = 0;
		}
		# check time
		checktimelimit();
	} 
	if ($loopcount % 60 == 0) {
		# check for upload process
		my $hiscount=`ps -ef | grep upload.pl | grep -v grep | grep -v vi | wc -l`;
		if ($hiscount < 1) { system("./upload.pl 2>>uplog 1>>uplog &"); }
	} 
	if ($loopcount % 1000 == 0) {
		# check update
		checkupdate();
		checklogfile();
	}

	$loopcount++;
	$loopcount = $loopcount % $CHECKINT;

	if ($limited && scalar @data == 0) {
		#print "limited and no data\n";
		sleep 1;
		if ($stop_get && $curchild == 0) {
			$time_to_die = 1;
		}
		next;
	}

	#if ($fileno / $NUMSEND > $savepath) {
		#$savepath++;
		#mkdir("data/".$savepath);
		#}

	if (scalar @data > $maxchild * 1.5) {  # too many data
		print "too many data:". scalar(@data)."\n";
		
	} elsif (!$stop_get && !$limited) {
		getdata();	# connect to server
	}

	if ($curchild >= $maxchild) {
		sleep 1;
	}
	# no data avaliable
	unless (scalar @data) {
		print "no data\n";
		sleep 5;
		if ($stop_get && $curchild == 0) {
			$time_to_die = 1;
		}
		next;
	}

	if ($stop_get && $curchild == 0) {
		$time_to_die = 1;
		next;
	}

	processdata();
}
loadandsave(0);
sub loadandsave {
	if ($_[0]) {
		if (-e "save") {
			open my $fh, "<:raw", "save";
			while (<$fh>) {
				chomp;
				push(@data, $_);
			}
			close $fh;
		}
	} else {
		open my $fh, ">:raw", "save";
		foreach my $d (@data) {
			print $fh $d."\n";
		}
		close $fh;
	}
}
# conf
sub readconf {
	$conf_file = shift @_ if defined $_[0];
	my %g_conf = ( );
	open CONF, "<$conf_file" or die "Can't read $conf_file\n";
	while(<CONF>) {
		my($k,$v) = /(\S+)\s*=\s*(.+)/;
		$g_conf{$k} = $v;
	}
	close CONF;
	if (open CONF, "<$limit_file") {
		while(<CONF>) {
			my($k,$v) = /(\S+)\s*=\s*(.+)/;
			$g_conf{$k} = $v;
		}
		close CONF;
	}
	@get_hosts = split(/,/, $g_conf{'get_host'}) or die "get_host not defined\n";
	$workpath = $g_conf{'workpath'} ? realpath($g_conf{'workpath'}) : realpath(".");
	$get_port = $g_conf{'get_port'};
	my $loadlimit = $g_conf{'loadlimit'};
	my $timelimit = $g_conf{'timelimit'};
	$spacelimit = $g_conf{'spacelimit'};
	$updatemodule = $g_conf{'updatemodule'};
	parseloadlimit($limits, $loadlimit);
	parsetimelimit($timelimits, $timelimit);
	if (-e "fileno") {
		if (open FH, "fileno") {
			while (my $line = <FH>) {
				chomp $line;
				if ($line =~ /^\d+$/) {
					$fileno = $line;
				}
			}
		}
	}
}
# handle child exit
sub REAPER {                        # takes care of dead children
	$SIG{CHLD} = \&REAPER;
	while ((my $pid = waitpid(-1, WNOHANG)) > 0) {
		#if ($pid != -1) {print $?."\n"};
		if (defined $childmap{$pid}) { 
			$curchild -- ;
		} else {
			#print "pid not defined:$pid\n";
		}
		delete $childmap{$pid};
	}
}

# handle stop
sub signal_handler {
	$stop_get = 1;
}
# connect to server
sub getdata {
	my $socket;
	my $get_host = $get_hosts[$get_host_index];
	$get_host_index++;
	$get_host_index = $get_host_index % scalar @get_hosts;
	until (
		$socket = IO::Socket::INET->new(PeerAddr => $get_host,
			PeerPort => $get_port,
			Proto    => "tcp",
			Timeout  => 5,
			Type     => SOCK_STREAM)
			or (!($!{EINTR}) && !($!{ECHILD}) && print "Couldn't connect to $get_host:$get_port : $@\n")) {}

	if ($socket) {
		# ... do something with the socket
		print $socket "get\n";
		print "get...";

		eval { 
			local $SIG{ALRM} = sub { die "alarm clock restart" };
			alarm 10;                   # schedule alarm in 10 seconds 
			eval { 
				while (<$socket>) {
					chomp;
					push(@data, $_);
				}
			};
			alarm 0;                    # cancel the alarm
		};
		alarm 0;                        # race condition protection
		die if $@ && $@ !~ /alarm clock restart/; # reraise

		print "done\n";
		close($socket);
	}
}
sub processdata {
	for (my $i = $curchild; $i < $maxchild; $i++) {
		my $line = shift @data or last;
		my @info = split("\t", $line);

		my $str = "$fileno.html";
		foreach my $s (@info) {
			$str .= "\t$s";
		}
		$str .= "\n";
		# make command
		my $url = $info[$#info];
		my $saveas = "data/$fileno.html"; 
		my $cmd;
		if ($url =~ /^\S+:\/\/.+/) {
			$cmd = "curl ".urlstr($url)." -o \"$saveas\"".$curloption;
		} elsif ($url =~ /^wget.+/) {
			$cmd = $url . " -O \"$saveas\"".$wgetoption;
		} elsif ($url =~ /^curl.+/) {
			$cmd = $url . " -o \"$saveas\"".$curloption;
		} else {
			next;
			#my $rand = int( rand(1)) + 1;
			#$cmd = "echo a>/dev/null";
		}
		print $cmd."\n";
		my $pid = make_new_child($cmd, "data/$fileno.index", $str);
		$fileno++;
		system("echo $fileno >fileno");
	}
}
sub urlstr {
	my ($str) = @_;
	#$str =~ s/([\$`\\"])/\\$1/g;
	$str =~ s/'/%27/g;
	return "'$str'";
}
sub make_new_child {
	my ($cmd, $index, $str) = @_;
	my $pid;
	my $sigset;

	# block signal for fork
	$sigset = POSIX::SigSet->new(SIGINT,SIGCHLD);
	sigprocmask(SIG_BLOCK, $sigset)
		or die "Can't block SIGINT for fork: $!\n";

	die "fork: $!" unless defined ($pid = fork);

	if ($pid) {
		# Parent records the child's birth and returns.
		$childmap{$pid} = 0;
		$curchild++;
		sigprocmask(SIG_UNBLOCK, $sigset)
			or die "Can't unblock SIGINT for fork: $!\n";
		return $pid;
	} else {
		# Child can *not* return from this subroutine.
		$SIG{INT} = 'DEFAULT';      # make SIGINT kill us as it did before

		# unblock signals
		sigprocmask(SIG_UNBLOCK, $sigset)
			or die "Can't unblock SIGINT for fork: $!\n";
		system "$cmd";
		open FH, ">$index" or die "Can't write $index\n";
		print FH $str;
		close FH;
		system "touch $index.flag";
		exit 0;
	}
}
sub checklimit {
	my $uptime = `uptime`;
	if ($uptime =~ /average:\s(.+),\s(.+),\s(.+)$/) {
		if ($1 > $limits->[0] || $2 > $limits->[1] || $3 > $limits->[2]) {
			return 1;
		}
		return 0;
	}
	die "bad uptime\n";
	return 0;
}
sub checkspacelimit {
	my $spaceinfo = `df`;
	our $pathreg;
	unless (defined $pathreg) {
		$workpath =~ /^(\/.*?)(\/.*)?$/ or die "Bad path $workpath\n";
		$pathreg = qr/(\d+)\s+\d+%\s+$1\s*$/;
	}
	if ($spaceinfo =~ /$pathreg/sm) {
		if ($1 < $spacelimit) {
			return 1;
		} else {
			return 0;
		}
	}
	die "Bad code or Mount or path\n";
	return 0;
}
sub checktimelimit {
	my ($HOUR) = (localtime)[2];
	my $x = $timelimits->{$HOUR};
	$maxchild = $PREFORK * $x;
}
sub checkmodify {
	my $file = shift;
	return 0 unless -e $file;
	my ($mtime) = (stat($file))[9];
	return $mtime;
}
sub checkupdate {
	return unless (defined $updatemodule);
	my $cmd = "rsync -rc --exclude='limits' $updatemodule/ ./";
	system($cmd);
}
sub checklogfile {
	if (-s "log" > 20000000) {
		system "echo >log";
	}
	if (-s "uplog" > 20000000) {
		system "echo >uplog";
	}
}	
sub parseloadlimit {
	my ($array, $str) = @_;

	my @a = split(/,/, $str);
	unless (scalar @a == 3 
		&& $str =~ /^\s*(\d+(\.\d+)?\s*,\s*){2}\d+(\.\d+)?\s*$/) {
		die "Syntax error: loadlimit should be float,float,float\n";
	}
	@{$array} = @a;
}

sub parsetimelimit {
	my ($hash, $str) = @_;
	for (my $i = 0; $i <= 23; $i++) {
		$hash->{$i} = 1.0;
	}
	my @a = split(/,/, $str);
	foreach my $b (@a) {
		next if ($b =~ /^\s*$/);
		if ($b =~ /^\s*(\d+)\s*(-\s*(\d+)\s*)?:\s*(\d+(\.\d+)?)\s*$/) {
			if (defined $3) {
				die "Range error in timelimit: $b\n" unless ($1 >= 0 && $3 <= 23 && $1 < $3);
				for (my $i = $1; $i <= $3; $i++) {
					$hash->{$i} = $4;
				}
			} else {
				die "Range error in timelimit: $b\n" unless ($1 >= 0 && $1 <= 23);
				$hash->{$1} = $4;
			}

		}
	}
}
