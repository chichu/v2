package USER;
require      Exporter;
our @ISA        =qw(Exporter);
our @EXPORT     =qw(
today
now
save
append
append_data
goodrss_save
std_save
filterRssPubDate
nextline
nextnum
formdata
urlencode
urlencode2
trim
confname
);
our @EXPORT_OK =qw(setbaseinfo setinfo setconfname);
our $VERSION    =1.00;

use strict;
use HTML::Entities;
use IO::Handle;
use File::Path;
use HTML::Form;
use Date::Manip;

#autoflush STDOUT 1;
*circle = \&main::circle;
*end = \&main::end;

my $conf_name = "";
my $saveid = 0;
my $g_day = "";
my $g_time = "";
my $datadir = "";
my $workingdir = "";
my $confnames = {};
# get date as '20070120'
sub today {
	return $g_day;
}
# get time as '1459' (14:59)
sub now {
	return $g_time;
}
sub basedir {
	return $datadir;
}
sub confname {
	return $conf_name;
}
# write str to file
sub save {
	my $name = $_[0];
	$name = $datadir."/".$conf_name."/".$name;
	print "Save... $name\n";
	my $file = $name; 
	open(F, ">", "$file");
	binmode F, ":raw";
	print F $_[1];
	close(F);
}
# append str to file
sub append {
	my $name = $_[0];
	$name = $datadir."/".$conf_name."/".$name;
	print "Append... $name\n";
	my $file = $name; 
	open(F, ">>", "$file");
	binmode F, ":raw";
	print F $_[1];
	close(F);
}
# append str to file
sub append_data {
	my $name = $_[0];
	$name = $datadir."/".$name;
	print "Append... $name\n";
	my $file = $name; 
	open(F, ">>", "$file");
	binmode F, ":raw";
	print F $_[1];
	close(F);
}
# save goodrsslist index and file
sub goodrss_save {
        my $content = $_[0];
        my $url = $_[1];
        my $path = $datadir."/".$conf_name;
        print "path:$path\n";
        if ($content =~/<rss version=/i && $content =~/<item>/i){
                open(F, ">>$path/goodrsslist") or (die "can't open $path/goodrsslist:$!\n");
                binmode F, ":raw";
                print F "$url\n";
                close(F);
        }
}
# save index and file
sub std_save {
	my $content = $_[0];
	my $url = $_[1];
	if (defined($_[2])) {
		my $f = $_[2];
		$content = &$f($_[0], $_[1]);
		return if (length($content) == 0);
	}
	my $day = today();
	my $time = now();
	print "save...$time"."_"."$saveid\tbytes:".length($content)."\n";
	my $path = $datadir."/".$conf_name;
	system("mkdir -p $path") unless -e $path;
	my $file = $path."/index";
	open(F, ">>$file") or (die "can't open $file:$!\n");
	binmode F, ":raw";
	print F "$path/$day/$time"."_"."$saveid\t$url\n";
	close(F);
	system("mkdir -p $path/$day") unless -e "$path/$day";
	open(F, ">$path/$day/$time"."_"."$saveid") or (die "can't open $time"."_"."$saveid:$!\n");
	binmode F, ":raw";
	print F $content;
	close(F);
	$saveid++;
}
sub filterRssPubDate
{
	my $rssContent = $_[0];
	my $url = $_[1];

	if ( my @pubDateArray = $rssContent =~ m|<pubDate>(.*?)</pubDate>|smg )
	{
		my $newContent = "$url\n";
		foreach my $pdate (@pubDateArray)
		{
			$newContent .= $pdate;
			$newContent .= "\n";
		}

		return $newContent;
	}
	else
	{
		return "";
	}
}
my $g_status = {};
sub setbaseinfo {
	$conf_name = $_[0];
	$confnames->{$conf_name} = 1;
	$datadir = $_[1];
	$workingdir = $_[2];
}
sub setconfname {
	$conf_name = $_[0];
}
sub setinfo {
	$g_day = shift @_ if defined $_[0];
	$g_time = shift @_ if defined $_[0];
	if (defined $_[0]) {
		$saveid = shift @_;
#                for my $name (keys %{$confnames}) {
#                        mkpath($datadir."/".$name);
#                }
	}
}
# get a file's next line, line NO. save in $g_status{$file}
sub nextline {
	my $file = $_[0];
	my $status = "$conf_name"."_$file";
	my $circle = defined($_[1]) ? $_[1] : 1;
	my $statusfile = "$workingdir/status/status_$conf_name"."_$file";
	unless (defined $g_status->{$status}) {
		print "open $file\n";
		open (my $fh, "<", "$file") or die "Can't open $file\n";
		my $count = 0;
		if ( open FH2, "<$statusfile") {
			#binmode FH2, ":encoding(utf8)";
			while(<FH2>) {
				if (/^(\d+)/) {
					$count = $1;
				}
			}
			close FH2;
		}
		my $orgcount = $count;
		while ($count) {
			unless (<$fh>) {
				seek ($fh, 0, 0);
			}
			$count--;
		}
		$g_status->{$status} = {
			'handle' => $fh,
			'count' => $orgcount
		};
	}
	my $fh = $g_status->{$status}->{'handle'};
	my $c = $g_status->{$status}->{'count'};
	my $line;
	if($line = <$fh>) {
		chomp $line;
		$c++;
		#binmode STDOUT, ":encoding()";
		#print $line,"\n";
		circle();
		$g_status->{$status}->{'count'} = $c;
	} elsif ($circle) {
		sleep 2;
		seek ($fh, 0, 0);
		$c = 0;
		die "Can't read $file \n" unless (defined($line = <$fh>));
		chomp $line;
		$c++;
		circle();
		$g_status->{$status}->{'count'} = $c;
	} else {
		end();
		$c = 0;
		$line = "";
		close($g_status->{$status}->{'handle'});
		delete $g_status->{$status};
	}
	system("echo $c >$statusfile");
	return $line;
}
# get a file's next line, line NO. save in $g_status{$file}
sub nextnum {
	my $file = $_[0];
	my $start = $_[1];
	my $end = $_[2];
	my $statusfile = "$workingdir/status/status_$conf_name"."_$file";
	unless (defined $g_status->{$file}) {
		my $count = $start;
		if ( open FH2, "<$statusfile") {
			while(<FH2>) {
				if (/^(\d+)/) {
					$count = $1;
				}
			}
			close FH2;
		}
		my $orgcount = $count;
		$g_status->{$file} = {
			'count' => $orgcount
		};
	}
	my $c = $g_status->{$file}->{'count'};
	if ($c < $start || $c > $end) {
		$c = $start;
	}
	my $line = $c++;
	$g_status->{$file}->{'count'} = $c;
	system("echo $c >$statusfile");
	return $line;
}
sub formdata {
	my $text = shift @_;
	my $base_uri = shift @_;
	my $formname = shift @_;
	my @forms = HTML::Form->parse($text, $base_uri);
	@forms = grep $_->attr("name") eq $formname, @forms;
	(print "No form named $formname found" && return "") unless @forms;
	my $form = shift @forms;
	my ($k, $b);
	while (defined ($k = shift @_) && defined ($b = shift @_)) {
		my $i = $form->find_input($k);
		(print "No param $k in $formname from $base_uri\n" && return "") unless $i;
		$i->readonly(0); 
		$form->param($k, $b);
	}
	my @kw = $form->form;
	my @a;
	while (defined ($k = shift @kw) && defined ($b = shift @kw)) {
		if ($b) {
			push @a, $k."=".urlencode($b);
		}
	}
	return join('&', @a);
}
# do normal urlencode
sub urlencode {
	my ($word) = @_;
	#return uri_escape($word);
	$word =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	#$word =~ s/%u([0-9A-Fa-f]{4})/utf8_2_gb(toUtf8($1))/eg;
	#$word =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
	#print $word,"\n";
	return $word;
}
# only encode gb
sub urlencode2 {
	my ($word) = @_;
	#return uri_escape($word);
	$word =~ s/([\x80-\xff])/sprintf("%%%02X", ord($1))/seg;
	$word =~ s/^\s+//;
	$word =~ s/\s+$//;
	#$word =~ s/%u([0-9A-Fa-f]{4})/utf8_2_gb(toUtf8($1))/eg;
	#$word =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
	return $word;
}

# remove html tags and &nbsp; and \t
sub trim {
        for my $text (@_) {
                #my ($text) = @_;
                #$text =~ s/<script[^>]*?>.*?<\/script>//smg;
                $text =~ s/<[\/\!]*?[^<>]*?>//smg;
                $text =~ s/(\s|\&nbsp;)+/ /smg;
		decode_entities($text);
                $text =~ s/^\s*(.*?)\s*$/$1/;
        }
        return @_;
}

# only decode utf-8
sub decode_utf8 {
                my($str) = @_;
                $str = decode('utf-8',$str);
                return $str;
}

# only encode utf-8
sub encode_utf8 {
                my($str) = @_;
                $str = encode('utf8',$str);
                return $str;
}

# only decode gbk
sub decode_gbk {
                my($str) = @_;
                $str = decode('gbk',$str);
                return $str;
}

# only encode gbk
sub encode_gbk {
                my($str) = @_;
                $str = encode('gbk',$str);
                return $str;
}

1;

