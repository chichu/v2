package INI;
use strict;
BEGIN {
    use Exporter ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    $VERSION    = 1.00;
    @ISA        = qw(Exporter);
    @EXPORT     = qw(&iniToHash);
    @EXPORT_OK  = qw(&iniToHash);
}

#usage:
#      my %hash=iniToHash('/tmp/myini.ini');
#      print $hash{'TITLE'}->{'Name'},"\n";
#
sub iniToHash {
	open(MYINI,$_[0]) or die "Can't open $_[0]:$!\n";
	binmode MYINI, ":raw";
	my %hash1;
	my $hashref;
	while( <MYINI> ){
		chomp;
		if( my($key) = /^\[(.+)\]$/ ){
			$hashref = $hash1{$key} ||= {};
		}elsif( my($k,$v) = /^(\w+)\s*=\s*(.+)$/ ){
			#print "key:$k,v:$v\n";
			$hashref->{$k}=$v;
		}
	}
	close MYINI;
	return %hash1;
}
1;
