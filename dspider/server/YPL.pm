package YPL;
use strict;
BEGIN {
    use Exporter ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    $VERSION    = 1.00;
    @ISA        = qw(Exporter);
    @EXPORT     = qw(&findypl &initypl &uninitypl &parseypl);
    @EXPORT_OK  = qw(&findypl &initypl &uninitypl &parseypl);
}
my $ypllist = {};

sub findypl {
	my ($name) = @_;
	return $ypllist->{$name};
}
sub initypl {
	my ($dir) = @_;
	opendir DIR, $dir;
	while (defined (my $file = readdir(DIR))) {
		next unless $file =~ /.*\.ypl$/;
		open FH, "$dir/$file";
		#local $/ = "%%";
		my $content = "";
		while(<FH>) {
			if (/^%%.*$/) {
				$content =~ s/^\s*#.*?$//gm;
				#$content =~ s/\s*#.*$//gm;
				if ($content =~ s/^\s*name\s*:\s*(\w+)\s*$//m) {
					$ypllist->{$1} = $content;
				}
				$content = "";
			} else {
				$content .= $_;
			}
		}
		unless ($content eq "") {
			$content =~ s/^\s*#.*?$//gm;
			if ($content =~ s/^\s*name\s*:\s*(\w+)\s*$//m) {
				$ypllist->{$1} = $content;
			}
		}
	}
}
sub uninitypl {
	$ypllist = {};
}
sub parseypl {
	my ($content, $arg) = @_;
	if ($content =~ s/^\s*args\s*:\s*((\w+(\s*,\s*\w+)*)*)//) {
		my $arglist = $1;
		$arglist =~ s/\s//g;
		my @a = split(/,/, $arglist);
		for my $a (@a) {
			my $value = $arg->{$a};
			unless (defined $value) {
				die "$a not supplied\n";
			}
			$content =~ s/<%\s*$a\s*%>/$value/g
		}
	}
	if ($content =~ /<%\s*(\w+)\s*%>/m) {
		die "$1 not defined\n";
	}
	my $buf = "";
	my $stage = "";
	my $hash = {};
	while ($content =~ s/(.*)\n//) {
		my $line = $1;
		if($line =~ /^\s*(\w+)((\(\w+\))?\s*:\s*.+)$/) {
			$stage = $1;
			$hash->{$stage} = $2."\n";
		} else {
			$hash->{$stage} .= $line."\n";
		}
	}
	my $stages = {};
	$hash->{'std_save'} = ': {std_save($pre_ret, $pre_url);}';
	while (my ($key, $value) = each %{$hash}) {
		next if ($key eq "");
		$stages->{$key} = {};
		if ($value =~ s/^\((\w+)\)\s*:\s*/:/) {
			$stages->{$key}->{'eq'} = $1;
		}
		if ($value =~ s/\s*:\s*(\w+(,\w+)*)?{(.+)}\s*$//sm) {
			$stages->{$key}->{'prefix'} = $1;
			$stages->{$key}->{'cmd'} = $3;
		} else {
			die "Syntax error: $value \n";
		}
		my $rules = [];
		my $reglist = [];
		my $rule = {};
		while ($value =~ s/(.*)\n//) {
			my $line = $1;
			if ($line =~ /^\s*-\s*(\w+)\s*$/) {
				$rule->{'reglist'} = $reglist;
				$rule->{'next'} = $1;
				$reglist = [];
				push @{$rules}, $rule;
				$rule = {};
			} else {
				chomp $line;
				$line =~ s/^\s+//;
				$line =~ s/\s+$//;
				if (length $line) {
					push @{$reglist}, $line; 
				}
			}
		}
		$stages->{$key}->{'rules'} = $rules;
	}
	return $stages;
}
1;
