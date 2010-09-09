#!/usr/bin/perl -w
# nonforker - server who multiplexes without forking
use strict;
use POSIX;
use IO::Socket;
use IO::Select;
use Socket;
use Fcntl;
use Tie::RefHash;
use IO::Handle;
use List::Util qw(shuffle);
autoflush STDOUT 1;

#################### usage ###################
#print "Usage : ./crawserver.pl \n";

# ref to @res1, array of all resource
my @res1 = ( );
my $g_res = \@res1;
my $fifo = 0;

my $port = 8082;               # change this at will
my $g_count = 20;		    # count of resource send to client per times
my $conffile = "server.conf";

my $backup = "data.txt";
#initserver($ARGV[0]);

# begin with empty buffers
my %inbuffer  = ( );
my %outbuffer = ( );
my %ready     = ( );
tie %ready, 'Tie::RefHash';
# each client's data
my %g_client = ();
# each site's data
my $g_sites = {};
my $g_sitelist = [];
my $g_sitelist_index = 0;

# settings
my $avoid_limit = 3;
my $default_limit = 500;
my $avoid_rapid = {};

# init server (load backup file)
initserver();
# Listen to port.
my $server = IO::Socket::INET->new(LocalPort => $port,
	Listen    => 100 ,
	ReuseAddr => 1)
	or die "Can't make server socket: $@\n";
nonblock($server);
my $select = IO::Select->new($server);

################## signal handler ##########################################
my $time_to_die = 0;
sub signal_handler {
    $time_to_die = 1;
}
$SIG{INT} = $SIG{TERM} = $SIG{HUP} = \&signal_handler;
$SIG{PIPE} = 'IGNORE';
#$openfifo = 0;
# Main loop: check reads/accepts, check writes, check ready to process
until ($time_to_die) {

	my $client;
	my $rv;
	my $data;

	# check for new information on the connections we have
	
	if (0 && !$fifo) {
		print "open fifo...\n";
		if (sysopen(DATA, $ARGV[0], O_NONBLOCK|O_RDONLY)) {
			$fifo = *DATA;
			#print "open fifo $fifo $?\n";
			$fifo->blocking(0);
			$select->add($fifo);
			print "done\n";
		}
	}	

	# anything to read or accept?
	foreach $client ($select->can_read(1)) {

		#my $test = *$client{IO};
		#if (defined($test)) { # local file
		if (0 && $client eq $fifo) { # local file
			if ($client eq $fifo) {
				#print "read...";
				$data = '';
				$rv = sysread($client, $data, POSIX::BUFSIZ);
				unless (1 && defined($rv) && length $data) {
					if (length $inbuffer{$client}) {
						# each line must follow a '\n'
						#push (@{$g_res}, $inbuffer{$client});
					}
					delete $inbuffer{$client};
					$select->remove($client);
					close $client;
					$fifo = 0;
					next;
				}
				$inbuffer{$client} .= $data;
				while ($inbuffer{$client}  =~ s/(.*\n)//) {
					my $line = $1;
					chomp ($line);
					if ($line =~ /^(\w+)\t/) {
						inputline($1, $line);
					}
					#push(@{$g_res}, $line);
					#print $line."\n";
				}

			} 
			next;
		}
		
		if ($client == $server) {
			# accept a new connection

			$client = $server->accept( );
			$g_client{$client} = {};
			$select->add($client);
			nonblock($client);
		} else {
			#print $client->peerhost()."\n";

			# read data
			$data = '';
			$rv   = $client->recv($data, POSIX::BUFSIZ, 0);

			unless (defined($rv) && length $data) {
				# This would be the end of file, so close the client
				delete $inbuffer{$client};
				delete $outbuffer{$client};
				delete $ready{$client};
				delete $g_client{$client};

				$select->remove($client);
				close $client;
				next;
			}

			$inbuffer{$client} .= $data;

			# test whether the data in the buffer or the data we
			# just read means there is a complete request waiting
			# to be fulfilled.  If there is, set $ready{$client}
			# to the requests waiting to be fulfilled.
			while ($inbuffer{$client} =~ s/(.*\n)//) {
				my $line = $1;
				#chomp $line;
				$line =~ s/[\n\r]//g;
				push( @{$ready{$client}}, $line );
			}
		}
	}

	# Any complete requests to process?
	foreach $client (keys %ready) {
		handle_input($client);
	}

	# Buffers to flush?
	foreach $client ($select->can_write(1)) {
		# Skip this client if we have nothing to say
		next unless exists $outbuffer{$client};

		$rv = $client->send($outbuffer{$client}, 0);
		unless (defined $rv) {
			# Whine, but move on.
			warn "I was told I could write, but I can't.\n";
			next;
		}
		if ($rv == length $outbuffer{$client} ||
			$!  == POSIX::EWOULDBLOCK )  
		{
			substr($outbuffer{$client}, 0, $rv) = '';
			unless (length $outbuffer{$client}) {
				delete $outbuffer{$client}; 
				# TODO:
				# short connect
				$client->shutdown(1);

				#delete $inbuffer{$client};
				#delete $ready{$client};
				#$select->remove($client);
				#close($client);
			}
		} else {
			# Couldn't write all the data, and it wasn't because
			# it would have blocked.  Shutdown and move on.
			delete $inbuffer{$client};
			delete $outbuffer{$client};
			delete $ready{$client};
			delete $g_client{$client};

			$select->remove($client);
			close($client);
			next;
		}
	}

	# Out of band data?
	foreach $client ($select->has_exception(0)) {  # arg is timeout
		# Deal with out-of-band data here, if you want to.
	}
}

print "closing...";
#delete $server;
close $server;
for my $handle ($select->handles) {
	$select->remove($handle);
	#print "$handle\n";
	close $handle;
}
close $fifo if $fifo;
print "done.\n";
save_status();
# handle($socket) deals with all pending requests for $client
sub handle_input {
	# requests are in $ready{$client}
	# send output to $outbuffer{$client}
	my $client = shift;
	my $request;
	my $isin = $g_client{$client}->{'incount'};
	#unless (defined($isin)) { $isin = 0; }
	my $peer = $client->peerhost();
	$peer = "" unless defined $peer;
	#print "[$peer]";

	foreach $request (@{$ready{$client}}) {
		# $request is the text of the request
		# put text of reply into $outbuffer{$client}
		if (defined ($isin) && $isin) {
			if ($request =~ /^(\w+)\t/) {
				inputline($1, $request);
				$isin--;
			}
			#push(@{$g_res}, $request);
			#print("$request\n");
		} elsif ($request eq "get") {
			print "[$peer]$request\n";
			unless (exists $outbuffer{$client}) { $outbuffer{$client} = ""; }
			next unless @{$g_sitelist}; 
			my $i = 0;
			my $count = 0;
			while ($count < $g_count) {
				$g_sitelist_index %= scalar @{$g_sitelist};
				my $s = $g_sitelist->[$g_sitelist_index];
				$g_sitelist_index++;
				if (@{$s}) {
					my $line = shift @{$s};
					#print "$line\n";
					$outbuffer{$client} .= $line."\n";
					$count++;
					$i = 0;
				} else {
					$i++;
					last unless ($i < scalar @{$g_sitelist});
				}
			}
		} elsif ($request eq "testget") {
			for (my $i = 0; $i < $g_count; $i++) {
				my $line = int( rand(5001)) + 2500;
				#print "$line\n";
				$outbuffer{$client} .= $line."\n";
			}
		} elsif ($request =~ /^put (\d+)$/) { # 老方式被禁止
			#print $request."\n";
			$outbuffer{$client} = "202\n";
		} elsif ($request =~ /^put (\d+) (\w+)$/) {
			#print $request."\n";
			if (exists $avoid_rapid->{$2} and $g_sites->{$2} and scalar @{$g_sites->{$2}} > $avoid_limit) {
				$outbuffer{$client} = "202\n";
			} elsif ($g_sites->{$2} and scalar @{$g_sites->{$2}} > $default_limit) {
				$outbuffer{$client} = "202\n";
			} else {
				$outbuffer{$client} = "200\n";
				$g_client{$client}->{'incount'} = $1;
				$isin = $1;
			}
		}

	}
	
	if (defined($isin)) {
		if ($isin) {
			$g_client{$client}->{'incount'} = $isin;
		} else {
			#print "close\n";
			delete $inbuffer{$client};
			delete $outbuffer{$client};
			delete $ready{$client};
			delete $g_client{$client};
			$select->remove($client);
			close($client);
		}
	}
	delete $ready{$client};
}

# nonblock($socket) puts socket into nonblocking mode
sub nonblock {
	my $socket = shift;
	my $flags;

	$flags = fcntl($socket, F_GETFL, 0)
		or die "Can't get flags for socket: $!\n";
	fcntl($socket, F_SETFL, $flags | O_NONBLOCK)
		or die "Can't make socket nonblocking: $!\n";
}
sub inputline {
	my $s = $g_sites->{$_[0]};
	unless (defined $s) {
		#print "first $_[0]\n";
		$s = [];
		$g_sites->{$_[0]} = $s;
		push (@{$g_sitelist}, $s)
	}
	push(@{$s}, $_[1]);
	#print "push $_[1]\n";
}
sub initserver {
	#my ($resfile) = @_;
	#print "use fifo:$resfile\n";
	#print "initing...";
	#(-e $resfile && -r $resfile) or die "Can't read $resfile!\n";

	if (open DATA, "<$backup") {
		while(<DATA>) {
			chomp;
			my $line = $_;
			if ($line =~ /^(\w+)\t/) {
				inputline($1, $line);
			}
			#push(@{$g_res}, $_);
		}

	}
	readconf();

	print "done!\n";

}
sub readconf {
	open FH, $conffile or die "Can't open $conffile\n";
	while (<FH>) {
		chomp;
		next if (/^\s*#.*$/);
		next unless (/^(.*?)\s*=\s*(.*)$/);
		my $k = $1;
		my $v = $2;
		if ($k eq 'avoid_rapid') {
			while ($v =~ /(\w+)/g) {
				$avoid_rapid->{$1} = 1;
			}
		} elsif ($k eq 'avoid_limit') {
			if ($v =~ /(\d+)/) {
				$avoid_limit = $1;
			}
		}
	}
	close FH;
}
sub save_status {
	print "saving...\n";
	open DATA, ">$backup" or die "can't open $backup\n";
	while (my ($n, $v) = each(%{$g_sites})) {
		foreach my $key (@{$v}) {
			print DATA $key."\n";
		}
	}
=aaa
	foreach my $key (@{$g_res}) {
		print DATA $key."\n";
	}
=cut
	print "done.\n";
}

