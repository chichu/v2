#!/usr/bin/perl -w
# nonforker - server who multiplexes without forking
use strict;
use POSIX;
use IO::Socket;
use IO::Select;
use Socket;
use Fcntl;
use Fcntl qw/:flock/; 
#use POSIX qw(:sys_wait_h);
use IO::Handle;
use File::Path;
autoflush STDOUT 1;
#################### usage ###################
# "Usage : ./reciever.pl \n"

my $port = 8081;               # change this at will
my $recvdir = "recv"; # change this at will
my $swapdir = "swap"; # change this at will
my $readydir = "ready"; # 这里要与parser保持一致
my $conffile = "server.conf";

my $server = IO::Socket::INET->new(LocalPort => $port,
	Listen    => 100 ,
	ReuseAddr => 1)
	or die "Can't make server socket: $@\n";

################## signal handler ##########################################
my $time_to_die = 0;
my $childpid = 0;
sub signal_handler {
	$time_to_die = 1;
}
$SIG{INT} = $SIG{TERM} = $SIG{HUP} = \&signal_handler;
$SIG{PIPE} = 'IGNORE';
$SIG{CHLD} = 'IGNORE';
################# inital setting ##########################################
my $cwd;
my %pipemap;
unless (-e $recvdir) {
	mkpath $recvdir or die "can't mkdir $recvdir\n";
}
unless (-e $swapdir) {
	mkpath $swapdir or die "can't mkdir $swapdir\n";
}
chomp($cwd = `pwd`);
my $myip = (getips())[0];
my $defaulttarget = "";
my $map = readconf();
my $mvmap = makemvmap($map);
print "$myip\t$cwd\n";
################### main loop #############################################
$childpid = make_child();
my $client;
while (!$time_to_die) {
	next unless $client = $server->accept();
	#print "accept\n";
	next if my $pid = fork;                    # parent
	die "fork: $!" unless defined $pid;     # failure
	# otherwise child
	local($SIG{CHLD}) = 'DEFAULT';  
	close($server);                          # no use to child
	eval {
		handle($client);
	};
	print $@;
	# ... do something
	#print "child exit\n";
	exit;                                   # child leaves
} continue { 
	close($client) if defined $client;                          # no use to parent
}

print "$!closing...";
close $server;
kill 'INT' => $childpid;
print "done.\n";
# 多个子进程中负责接收文件到接收目录，完成后mv到swap目录
sub handle {
	my ($client) = @_;
	my $peername = $client->peerhost();
	chdir($cwd);
	my $dirname = $recvdir."/".$peername;
	mkdir $dirname;
	#print $dirname."\n";
	# flag for mark first line
	my $flag=0;
	my $filename;
	my $size;
	my $fh;
	my $inbuffer = '';
	my $data;
	# recieve
	while (1) {

		my $rv = $client->recv($data, POSIX::BUFSIZ, 0);
		unless (defined($rv) && length $data) {
			if ((length $inbuffer) != $size) {
				close($client);
				return;
			}
			open FH, "> :raw", "$dirname/$filename" or die "Can't write $dirname/$filename\n";
			print FH $inbuffer;
			close FH;
			last;
		}
		$inbuffer .= $data;
		if ($flag == 1) {
			next;
		}
		if ($inbuffer =~ s/(.*\n)//) {
			my $line = $1;
			chomp $line;
			if ($line =~ /^put (.+) (\d+)$/) {
				$flag = 1;
				$filename = $1;
				$size = $2;
				next;
			} else { # bad request
				close($client);
				return;
			}

		}
	}
	close($client);
	system("mv -f $dirname/$filename $swapdir/".$peername."_".$filename) ==0 or die "Can't mv file $dirname/$filename to $swapdir $!\n";
}
# 检查swap目录如果有tar.gz文件，把它们解压并写入recordtmp文件，而如果有recordtmp文件，则mv到$readydir下面或是rsync
sub checkready {
	my $dir = "$cwd/$swapdir";
	opendir(DIR, $dir) or die "Can't open $dir: $!";
	while ( defined (my $file = readdir DIR) ) {
		next if $file =~ /^\.\.?$/;     # skip . and ..
		next if (-d "$dir/$file");
		if ($file =~ /^recordtmp_(.+)$/) {
			mv_or_rsync($dir, $file, $1);
			next;
		}
		next unless ($file =~ /.*\.tar\.gz$/);
		my $a = time;
		dispatch($dir,$file);
		my $b = time;
		my $c = $b -$a;
		#print "total---------$file:$c"."\n";
	}
	closedir(DIR);
}
# 负责mv或者rsync文件
sub mv_or_rsync {
	my ($dir, $file, $pipe) = @_;
	my $fn = `date "+%s%N"`;
	chomp $fn;
	my $target = $mvmap->{$pipe};
	if (defined $target) {
		my $cmd = "rsync $dir/$file $target/$pipe/$fn$myip.html";
		system($cmd) == 0 && unlink("$dir/$file");
	} elsif ($defaulttarget != "") {
		$target = $defaulttarget;
		my $cmd = "rsync $dir/$file $target/$pipe/$fn$myip.html";
		system($cmd) == 0 && unlink("$dir/$file");
	} else {
		mkpath("$cwd/$readydir/$pipe");
		system("mv $dir/$file $cwd/$readydir/$pipe/$fn.html\n");
	}
}
# 唯一的子进程不停的检查swap目录
sub make_child { 
	my $pid; 
	die "fork: $!" unless defined ($pid = fork);
	if ($pid) {
		return $pid;
	} else {
		# Child can *not* return from this subroutine.
		local($SIG{CHLD}) = 'DEFAULT';  
		while (!$time_to_die) {
			eval {
				checkready();
			};
			print $@;
			sleep(5);
		}
		exit 0;
	}
}
sub dispatch {
	my ($dirname, $filename) = @_;

	chdir($dirname);
	# untar
	print "tar xzf $filename\n";
	system("tar xzf $filename 2>/dev/null") == 0 or die "Can't untar $dirname/$filename $!\n";
	my ($tardir) = $filename =~ /^.+_(.+)\.tar\.gz$/ or die "Unexpect filename:$filename\n";
	print "tardir:$tardir\n";
	# open index
	if (open FH, "<$tardir/index") { 
		while (<FH>) {
			chomp;
			#my ($file, $pipe, $id, $url) = split(/\t/) or next;
			my (@a) = split(/\t/) or next;
			writedir($tardir, @a);
		}
		close FH;
	} else {
		print "Can't open index:$!\n";
	}
	# remove tmp
	system("rm $tardir/ -R -f");
	system("rm $filename -f");
}
sub writedir {
	#my ($file, $pipe, $id, $url, $tardir) = @_;
	my ($tardir, @a) = @_;
	my $file = shift @a;
	my $pipe = $a[0];

	my $a = time;

	open (my $ph, ">>", "recordtmp_$pipe") or die "Can't write recordtmp\n";
	binmode $ph, ":raw";
	my $line = join "\t", @a;
	#print "<$line>\n";
	print $ph "<$line>\n";
	if (-e "$tardir/$file") {
		open FH2, "<$tardir/$file";
		binmode FH2, ":raw";
		my $buf;
		while(read(FH2, $buf, 16384)) {
			print $ph $buf;
		}
		close FH2;
	}
	print $ph "\n</$line>\n";
	close $ph;
	#print "</$line>\n";
	my $b = time;
	my $c = $b -$a;
	#print "write dir---------------$c\n";
}
# 得到本机ip的一个数组，除去127.0.0.1
sub getips {
	my $str = `/sbin/ifconfig`;
	my @a;
	while ($str =~ /inet\s+addr:([\d.]+)/g) {
		unless ($1 eq "127.0.0.1") {
			push @a, $1;
		}
	}
	die "Can't get ip\n" unless scalar @a;
	return @a;
}
# 得到一个hash, 由应用名对应其rsync地址
sub makemvmap {
	my ($inmap) = @_;
	my $outmap = {};
	my @myip = getips();
	my $ipstr = join(' ', @myip);
	for my $r (keys %{$inmap}) {
		next unless ($r =~ /([\d.]+)::/);
		my $this = $1;
		next if ($ipstr =~ /\b$this\b/);
		my @b = split(/\s/, $inmap->{$r});
		for my $app (@b) {
			$outmap->{$app} = $r;
		}
	}
	return $outmap;
}
sub readconf {
	my $map = {};
	open FH, $conffile or die "Can't open $conffile\n";
	while (<FH>) {
		chomp;
		next if (/^\s*#.*$/);
		next unless (/^(.*?)\s*=\s(.*)$/);
		my $k = $1;
		my $v = $2;
		if ($k =~ /[\d.]+::.+/) {
			$map->{$k} = $v;
		}
		elsif ($k eq "defaulttarget" && $v =~ /[\d.]+::.+/) {
			$defaulttarget = $v;
		}
	}
	close FH;
	return $map;
}
