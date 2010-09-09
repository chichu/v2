#! /usr/bin/perl -w
use strict;
use IO::Socket;
use File::Path;
use POSIX;

# check for one instance

my $mycount=`ps -ef | grep upload.pl | grep -v grep |grep -v vi| wc -l`;
if ($mycount > 1) { exit 0; }

# conf
my %g_conf = ( );
my $conf_file="crawclient.conf";
open CONF, "<$conf_file" or die "Can't read $conf_file\n";
while(<CONF>) {
	my($k,$v) = /(\S+)\s*=\s*(.+)/;
	$g_conf{$k} = $v;
}
close CONF;
my @put_hosts = split(/,/, $g_conf{'put_host'}) or die "put_host not defined\n";
my $host_map = {};
#my $put_host_index = 0;
my $put_host;
my $put_port = $g_conf{'put_port'};
my $timeout = $g_conf{'timeout'};
my $g_mtime = checkmodify($conf_file);
chomp(my $cwd = `pwd`);

# global variables
# main loop
my $pathno = 0;
my $fileno = 0;
if (-e "pathno") {
	if (open FH, "pathno") {
		while (<FH>) {
			chomp;
			if (/^\d+$/) {
				$pathno = $_;
				$fileno = $pathno * 50;
			}
		}
	}
}
mkpath("$cwd/data/$pathno");
print "path: $pathno\n";

while(1) {
	my $mtime = checkmodify($conf_file);
	if ($g_mtime < $mtime || $mtime == 0) { last; }

	testspeed();
	my $dir = "$cwd/data";
	opendir(DIR, $dir) or die "Can't open $dir: $!";

	while ( defined (my $file = readdir DIR) ) {
		next if $file =~ /^\.\.?$/;     # skip . and ..
		if ($file =~ /(\d+)\.index\.flag$/) {
			if ($fileno / 50 > $pathno) {
				#tar_content($dir,$pathno);
				$pathno++;
				print "path: $pathno\n";
				system("echo $pathno >pathno");
				mkpath("$cwd/data/$pathno");
			}
			print "mv $1\n";
			$fileno++;
			system("cd data && rm $1.index.flag && cat $1.index >>$pathno/index && rm $1.index && mv $1.html $pathno/;");
		} elsif ($file =~ /^\d+$/) { 
			print "tar $file\n";
			tar_content($dir, $file) unless ($file == $pathno);
		} elsif ($file =~ /^\d+\.tar\.gz$/) {
			print "send $file\n";
			send_content("$dir/$file", $file);
		}
	}
	closedir(DIR);
	if (-e "$dir/$pathno/index") {
		#tar_content($dir, $pathno);
		$pathno++;
		print "path: $pathno\n";
		$fileno = $pathno * 50;
		system("echo $pathno >pathno");
		mkpath("$cwd/data/$pathno");
	}
	sleep $timeout;
}
sub tar_content {
	my ($dir, $name) = @_;
	my $file = "$name.tar.gz";
	unless (-e "$dir/$name/index") {
		return;
	}
	system("cd $dir && tar czf $file $name && rm $name -f -R") == 0 or die "Can't tar $file\n";
}
sub testspeed {
	for my $h (@put_hosts) {
		$h =~ s/[^\d.]//g;
		next unless length $h;
		$host_map->{$h} = 100000;
		my $r = `ping $h -c 4`;
		if (defined $r) {
			if ($r =~ /min\/avg\/max\/mdev\s+=\s+\d+\.\d+\/(\d+\.\d+)/) {
				$host_map->{$h} = $1;
			}
		}
	}
	@put_hosts = sort { $host_map->{$a} <=> $host_map->{$b} } @put_hosts;
	die "no put_host\n" unless scalar @put_hosts;
	$put_host = $put_hosts[0];
}
sub send_content {
	my ($file, $name) = @_;

	open(IN, "< :raw", $file) or die "Can't open $file\n"; 	
	# ... do something with the socket
	my ($size) = (stat($file))[7];
	my $blksize = (stat IN)[11] || 16384;

	my $socket = IO::Socket::INET->new(PeerAddr => $put_host,
		PeerPort => $put_port,
		Proto    => "tcp",
		Type     => SOCK_STREAM)
		or print "Couldn't connect to $put_host:$put_port : $@\n";

	return -1 unless ($socket);

	print $socket "put $name $size\n";

	my $buf;
	while (1) {
		my $len = sysread (IN, $buf, $blksize);
		if (!defined $len) {
			next if $! =~ /^Interrupted/;       # ^Z and fg on EINTR
			die "System read error: $!\n";
		}
		last unless $len;

		my $offset = 0;
		while ($len) {          # Handle partial writes.
			defined(my $written = syswrite $socket, $buf, $len, $offset)
				or die "System write error: $!\n";
			$len    -= $written;
			$offset += $written;
		};
	}
	close IN;
	close($socket);
	system("rm $file -f");
	return 0;
}

sub checkmodify {
	my $file = shift;
	return 0 unless -e $file;
	my ($mtime) = (stat($file))[9];
	return $mtime;
}
