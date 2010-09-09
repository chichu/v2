#! /usr/bin/perl -w
#
# parser.pl
# 说明
# 类似状态机的抓站模板解析工具, 使用配置文件parser.cfg作为模板.
# 模板使用正则表达式和perl语句描述了如何生成要抓取的url,以及抓取后的处理方式
# 待抓取的url通过socket连接送入server.pl
# 抓取结果由recieve.pl以文件方式送回并进行后续处理.
# 命令行参数 
# cfgsection 配置文件中的配置项的名称
# --test	可以单独运行,用于测试一个配置项
# --dep		总是保持节点间的依赖关系,当自动的分析不正确时,可以加上这个选项,它会增加内存消耗
#
#
# 已知bug：
# 1. 在中断后1分钟内重新运行，如果这时候有保存，则saveid可能重复
#
#
use strict; 
use Fcntl;
use POSIX;
use IO::Socket;
use Data::Dumper;
use Encode;
use Encode::CN;
use IO::Handle;
use File::Path;
use URI;
use HTML::Entities;
use INI;
use YPL;
use USER;
use USER qw(setbaseinfo setinfo setconfname);
autoflush STDOUT 1;
binmode STDOUT, ":raw";
binmode STDERR, ":raw";

sub usage {
	return 
	"usage: ./parser.pl [cfgsections] [options]\n".
	"options:\n".
	"\t--test\ttest your config\n".
	"\t--sd\tstand-alone\n".
	"\t-f name\t config file, default is parser.cfg\n".
	"\t-d result data path, default is ../data\n".
	"\t--list\tlist all section in config file\n".
	"\t--dep\tdo not parse dependency\n".
	"\t--nodup\tavoid unnecessary page crawl, but may be miss some pages\n".
	"\t-i second\tinterval between two crawl(max idle time)\n".
	"\t--help\tshow this message\n".
	"\t-v\tshow more messages\n"
	;
}

my $remote_host = "127.0.0.1";
my $remote_port = "8082";
my $datadir = "../data";
my $workingdir = ".";
my $readydir = "ready"; # 下载回来的内容在这里面
my $MAXIDLE = 3600 * 1; # 允许的空闲的秒数,超过这个数就结束
my $encoding = "gbk"; # 默认的网页编码

# when set to 1, we are test our cfg file with synchronize network call.
my $test = 0;
my $stand_alone = 0;
# when set to 1, only show a list of section names.
my $show_list = 0;
# when set to 1, we always save context when get url
my $dep = 0;
# 如果设置成1，那么会假设：如果一个列表页面的所有链接都是重复的，那么下一页也是重复的，就不再抓取
# 列表页的判定是基于下一节点指向本节点，那么就认为是列表页
my $nodup = 0;
# verbose
my $v = 0;
# eq to current cfg section name
my $conf_name;
# the selected cfg
my $cur_conf = {};
# the cfg list
my %conflist = ();
# store urls that are ready to send
#my @sendlist = ();
# map url to context 
#my %urlmap = ();
#用于运行期间记录获取错误的url
my $err_map = {};
# buffer of recieve data
my $inbuffer = "";
# 结束及重新开始url0的生成
#my $endexec = 0;
#my $restartflag = 0;
# url0的调用次数，在主循环中传入execconf.
#my $calltimes = 0;
# 空闲的秒数,空闲是指既没有待发送的url,也没有产生新的url及执行任何动作
#my $sleeped = 0;
# 当前时间的秒数，用于度量空闲
my $now = time();
# 当前的24小时制的小时
my $g_hour = 0;
# 测试时存储测试结果
my $testresult = {};

# for profile
my $count_match = 0;
my $count_action = 0;
my $count_geturl = 0;
my $count_evalonly = 0;
my $count_execconf = 0;
my $count_execnext = 0;

# 解释命令行参数
sub parsecmd {
	my $conffile = "parser.cfg";
	my @names;
	while (my $arg = shift @ARGV) {
		if( $arg eq "--test") {
			$test = 1;
			$stand_alone = 1;
		} elsif ($arg eq "--dep") {
			$dep = 1;
		} elsif ($arg eq "--nodup") {
			$nodup = 1;
		} elsif ($arg eq "--help") {
			return 0;
		} elsif ($arg eq "-v") {
			$v = 1;
		} elsif ($arg eq "-f") {
			$arg = shift @ARGV or return 0;
			$conffile = $arg;
		} elsif ($arg eq "-d") {
			$arg = shift @ARGV or return 0;
			$datadir = $arg;
		} elsif ($arg eq "-i") {
			$arg = shift @ARGV or return 0;
			$arg =~ /^\d+$/ or return 0;
			$MAXIDLE = $arg;
		} elsif ($arg eq "--list") {
			$show_list = 1;
		} elsif ($arg eq "--sd") {
			$stand_alone = 1;
		} elsif ($arg =~ /^-.*/) {
			return 0;
		} else {
			push(@names, $arg);
		}
	}
	readconf2($conffile, @names);
	return 1;
}
# 读取和解析配置文件
# 分析依赖关系，以确定是否需要保存context
sub parsedep {
	#my ($conf) = @_;
	my ($stages) = @_; #$conf->{'stage'};
	my $lists = [ ];
	my $nodelist = "";
	tracechild(0, 'start', $stages, $nodelist, $lists);
	print "parse dep...\n" if $v;
	foreach my $list (@$lists) {
		#print $list."\n";
		my @a = split(/,/, $list);
		shift @a;
		print join(",",@a)."\n" if $v;
		for (my $i = 0; $i < @a; $i++) {
			#if ($a[$i] =~ /cnt\d+/) {
			for (my $j = $i+1; $j < @a; $j++) {
				#if ($a[$j] =~ /url\d+/) {
				for (my $k = $j + 1; $k < @a; $k++) {
					if ($a[$k] eq $a[$i]) {
						last;
					}
					#unless ($a[$k] =~ /cnt\d+/) {
					my $sk = $a[$k];
					$sk =~ s/(\w+)\(\w+\)/$1/;
					my $cmd = $stages->{$sk}->{'cmd'};
					my $mod = $a[$i];
					if ($cmd =~ /\b$mod\b/) {
						my $sj = $a[$j];
						$sj =~ s/(\w+)\(\w+\)/$1/;
						$stages->{$sj}->{needcontext} = 1;
						print $a[$j].":\t$mod used by ".$a[$k]."\n" if $v;
					}
					#}
				}
				#}
			}
			#}
		}
	}

}
# 递归的,在$lists中置入所有可能的执行路径,顺便将每一个stage的needcontext置为0
sub tracechild {
	my ($n, $stage, $stages, $nodelist, $lists) = @_;
	$stages->{$stage}->{'needcontext'} = 0;
	my $next = $stages->{$stage}->{'rules'};
	unless (defined $next) {
		die "$stage not defined\n";
	}

	my $qreg = qr/\b$stage\b/;
	my $eqstage = $stages->{$stage}->{'eq'};
	if (defined $eqstage) {
		$nodelist .= ",$stage";
		$nodelist .= "($eqstage)";
		$stage = "$eqstage";
		#$qreg = qr/,$stage\($eqstage\)/;
		$qreg = qr(/\b$stage\b/);
		$next = $stages->{$eqstage}->{'rules'};
	}
	#print $qreg."\n";
	unless (scalar @{$next} &&
		(! ($nodelist =~ /\b$stage\b/))) {
		$nodelist .= ",$stage";
		push @$lists, $nodelist;
		#print $nodelist."\n";
		return;
	};
	#print "stage:$stage\n";
	unless (defined $eqstage) {
		$nodelist .= ",$stage";
	}
	#print "$nodelist\n";
	for (my $i = 0; $i < scalar @{$next}; $i++) {
		my $this = $next->[$i]->{'next'};
		#print "next:","--"x$n, "$this\n";
		tracechild($n + 1, $this, $stages, $nodelist, $lists);
	}
}
# 预编译配置文件中提供的命令

# each time gen a new id
my $curid = 0;
my $wgetoption = " --user-agent='Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 5.1; .NET CLR 1.1.4322)' --header='Accept-Language: zh-cn' --tries=3 2>/dev/null";
# -S -s : silent but show error -g: close URL globbing parser
my $curloption = " -A 'Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 5.1; .NET CLR 1.1.4322)' -H 'Accept-Language: zh-cn' -m 120 -L --connect-timeout 30 -S -s -g";
sub localgeturl {
	my ($url) = @_;
	if ($url =~ /^\S+:\/\/.+/) {
		$url = urlstr($url);
		#$url = "wget "."$url"." -O -".$wgetoption;
		$url = "curl "."$url".$curloption;
	} elsif ($url =~ /^wget.+/) {
		$url .= " -O -".$wgetoption;
	} elsif ($url =~ /^curl.+/) {
		$url .= " ".$curloption;
	} else {
		return "";
	}
	my $ret = "";
	open(my $fh, "$url |");
	binmode $fh, ":raw";
	while (<$fh>) {
		$ret .= $_;
	}
	return $ret;
}

# unpack the context to a evalable form
sub depack {
	my ($context) = @_;
	my $ret = "";
	foreach my $key ( keys %{$context} ) {
		my $name;
		eval('$name=qw('.$key.')');
		$ret .= "my ".Data::Dumper->Dump([$context->{$key}], [$name]);
	}
	return $ret;
}
# return a copy of context
sub copy {
	my ($context) = @_;
	my $ret = {};
	while (my ($key,$value) = each(%{$context})) {
		$ret->{$key} = $value;
	}
	return $ret;
}
# send each line stored in @sendlist
# each time send a conf's all data
sub sendbuf {
	my $count = 0;
	my $ret = 0;
	while (my ($name, $conf) = each(%conflist)) {
		my $list = $conf->{'sendlist'};
		$count = @{$list};
		next unless $count;
		my $socket = IO::Socket::INET->new(PeerAddr => $remote_host,
			PeerPort => $remote_port,
			Proto    => "tcp",
			Type     => SOCK_STREAM);
		unless ($socket) {
			print "Couldn't connect to $remote_host:$remote_port : $@\n";
			next;
			# TODO: last will cause some problem
			# last;
		}
		print $socket "put $count $name\n";
		my $answer = <$socket>;
		chomp $answer;
		if ($answer == 200) {
			$ret = 1;
			$conflist{$name}->{'doing'} = 1;
			my $i = 0;
			for ($i = 0; $i < $count; $i++) {
				my $ret = shift(@{$list});
				print $socket "$name\t$ret\n";
			}
		} else {
			print "$answer\n";
			$count = 0;
		}
		close($socket);
	}
	return $ret;
}
# recieve result from a directory, which increase speed greatly 
sub getresult2 {
	my ($name) = @_;
	my $a = time;
	#my $a = `date "+%s%N"`;
	my $ret = 0;
	my $dir = "$workingdir/$readydir/$name";
	opendir(DIR, $dir) or die "Can't open $dir: $!";
	#print $dir."\n";
	while ( defined (my $file = readdir DIR) ) {
		next if $file =~ /^\.\.?$/;     # skip . and ..
		next if (-d "$dir/$file");
		next unless ($file =~ /.*\.html$/);
		if (open (my $fh, "<", "$dir/$file")) {
			$ret = 1;
			binmode($fh, ":raw");
			$cur_conf->{'doing'} = 1;
			checkfile($fh);
			close $fh;
			unlink("$dir/$file");
		}

	}
	closedir(DIR);
	my $b = time;
	#my $b = `date "+%s%N"`;
	my $c = $b - $a;
	if ($ret) {
		print "getresult2 cost:".$c."\n";
		#outputprofile();
	}
	return $ret;
}
sub outputprofile {
	print STDERR $count_match."\n";          
	print STDERR $count_geturl."\n";         
	print STDERR $count_evalonly."\n";       
	print STDERR $count_execconf."\n";       
	print STDERR $count_execnext."\n"; 
	#my $aa = %urlmap;
	#my $cc = scalar(keys(%urlmap));
	#print STDERR "$aa $cc\n";
}
# when recieved result, exectute it
my $qregline;
sub checkfile {
	my ($fh) = @_;
	my $mod = 0; # flag when match <name	0	url>
	my $modline = ""; # match </name	0	url>
	my $info = "";
	my $html = "";

	print "+\n";
	my $ret = 0;
	#$qregline = qr/^<($conf_name\t(\d+\t.+)>)$/ unless defined $qregline;
	$qregline = qr/^<(\w+\t(\d+\t.+)>)$/ unless defined $qregline;

	my $count = 0;

	while (my $line = <$fh>) {
		#chomp ($line);
		if (!$mod) {
			if ($line =~ /$qregline/) {
				$mod = 1;
				$modline = "</$1\n";
				$info = $2;
			}
		} else {
			if ($line eq $modline) {
				$mod = 0;
				execrecieved($info, \$html);
				$count++;
				$html = "";
			} else {
				$html .= $line;
			}
		}
	}
	print "process $count files\n";
	return $ret;
}
# 根据接收到的信息继续执行
sub execrecieved {
	my ($header, $content) = @_;
	my $ctx;
	my $context;

	my ($sendid, $stage, $needcontext, $realurl) = split(/\t/, $header);

	return unless defined $stage;
	return unless defined $realurl;

	# 出错重试
	if (length $$content == 1) {
		my $e = $err_map->{$sendid};
		$err_map->{$sendid} = ++$e;
		print "Error-$e----$header\n";
		if ($e < 3) {
			push @{$cur_conf->{'sendlist'}}, $header;
		} else {
			if ($needcontext) {
				delete $cur_conf->{'urlmap'}->{$realurl};
			}
		}
		return;
	} else {
		delete $err_map->{$sendid};
	}

	my $s = $cur_conf->{'stage'}->{$stage};
	if ($needcontext) {
		$ctx = $cur_conf->{'urlmap'}->{$realurl};
		#$context = copy($ctx) if defined $ctx;
		$context = $ctx;
		delete $cur_conf->{'urlmap'}->{$realurl} if defined $ctx;
	}
	# 如果需要context但是却不存在context, 放弃
	if ((defined $s && defined $realurl) &&
		!($needcontext && ! defined $context)) {
		#print "execnext\n";
		my $next = $s->{'next'};
		unless (defined $context) {
			$context = {};
		}
		$context->{'pre_url'} = trimurl($realurl);
		$context->{'id'} = $sendid;
		#execnext($next, $context, $ret);
		#execypl($cur_conf, $next, $context, $$content);
		continueexec($cur_conf, $stage, $context, $$content);
	} else {
		print "Error-----------$header\n";
	}

}
sub updateinfo {
	$now = time();
	my ($MIN, $HOUR, $DAY, $MONTH, $YEAR) = (localtime)[1,2,3,4,5];
	$g_hour = $HOUR;
	my $day = sprintf("%04d%02d%02d", $YEAR + 1900, $MONTH + 1, $DAY);
	my $time = sprintf("%02d%02d", $HOUR, $MIN);
	my $lastday = today();
	my $lasttime = now();
	if ($day eq $lastday && $time eq $lasttime) {
		setinfo($day, $time, undef);
	} else {
		setinfo($day, $time, 0);
	}
}
sub uniq {
	if (defined $cur_conf->{'uniq_map'}->{$_[0]}) {
		#print "defined\n";
		return 0;
	}
	$cur_conf->{'uniq_map'}->{$_[0]} = 1;
	return 1;
}
# 用于在一定时间后清除URL的排重(对付网站更新)
sub refresh_uniq_map {
	if ($cur_conf->{'keepdays'} <= 0) {
		return;
	}
	for my $k (keys %{$cur_conf->{'uniq_map'}}) {
		if ($cur_conf->{'uniq_map'}->{$k} > $cur_conf->{'keepdays'}) { # 超过指定天数，删除
			delete $cur_conf->{'uniq_map'}->{$k};
		} else {
			$cur_conf->{'uniq_map'}->{$k}++;
		}
	}
}
sub loadandsave {
	return if ($test);
	my $uniq_map_file = "$workingdir/status/$conf_name/uniqurl";
	my $urlmap_file = "$workingdir/status/$conf_name/urlmap";
	my $sendlist_file = "$workingdir/status/$conf_name/sendlist";
	if ($_[0]) { # save
		# 排重
		open my $fh, ">$uniq_map_file";
		binmode $fh, ":raw";
		for my $k (keys %{$cur_conf->{'uniq_map'}}) {
			print $fh $k."\n";
		}
		close $fh;
		# sendlist
		open $fh, ">$sendlist_file";
		binmode $fh, ":raw";
		while (my $line = shift @{$cur_conf->{'sendlist'}}) {
			print $fh $line."\n";
		}
		close $fh;
		# urlmap
		open $fh, ">$urlmap_file";
		binmode $fh, ":raw";
		while (my ($key,$value) = each(%{$cur_conf->{'urlmap'}})) {
			my $str =  "my ".Data::Dumper->Dump([$value], [qw(context)]);
			$str =~ s/\n/ /g;
			$str =~ s/\s+/ /g;
			print $fh $key."\t".$str."\n";
		}
		close $fh;

	} else { # load
		if (open my $fh, "<$uniq_map_file") {
			binmode $fh, ":raw";
			while(<$fh>) {
				chomp;
				$cur_conf->{'uniq_map'}->{$_} = 1;
			}
			close $fh;
		}
		if (open my $fh, "<$sendlist_file") {
			binmode $fh, ":raw";
			while(<$fh>) {
				chomp;
				push @{$cur_conf->{'sendlist'}}, $_;
			}
			close $fh;
		}
		if (open my $fh, "<$urlmap_file") {
			binmode $fh, ":raw";
			while(<$fh>) {
				chomp;
				if (/^(.*?)\t(.*)$/){
					eval($2.'$cur_conf->{\'urlmap\'}->{$1}=$context;');
				}
			}
		}
	}
}
# 表示在$MAXIDLE秒空闲后重新开始start节点的调用，这是默认行为
sub restart {
	$MAXIDLE = $_[0] if defined $_[0];
	$cur_conf->{'endexec'} = 1;
	$cur_conf->{'restartflag'} = 1;
}
# 表示在$MAXIDLE秒空闲后结束start节点的调用
sub end {
	$MAXIDLE = $_[0] if defined $_[0];
	$cur_conf->{'endexec'} = 1;
	$cur_conf->{'restartflag'} = 0;
}
# 表示持续的进行start节点的调用
sub circle {
	return if ($test);
	print "circle\n";
	$cur_conf->{'endexec'} = 0;
	$cur_conf->{'restartflag'} = 0;
}
# 读取参数传入的配置文件名，后续参数是配置项的名称，如果为空，则表示全部配置项
sub readconf2() {
	my $conffile = shift @_;
	my %hash = iniToHash($conffile);
	my @names;
	if (scalar @_) {
		@names = @_;
	} else {
		@names = keys %hash;
	}
	initypl(".");
	# 选择参数指定的配置
	for my $name (@names) {
		my $cur = $hash{$name};
		die "Can't find section $name\n" unless (defined $cur);
		# TODO:检查是否相同的配置已经在运行
		setbaseinfo($name, $datadir, $workingdir);
		print "-----------------------------------reading $name...\n" if $v;

		my $template = "";
		# 模板参数
		my $args = {};
		my $enc = $encoding;
		my $keepdays = 0;
		# 构造$conf
		foreach my $key (keys %{$cur}) {
			#print $key."\n";
			if ($key eq "encoding") {
				$enc = $cur->{$key};
				next;
			}
			if ($key eq "template") {
				$template = $cur->{$key};
				next;
			}
			if ($key eq "keepdays") {
				$keepdays = $cur->{$key};
				next;
			}
			$args->{$key} = $cur->{$key};
		}
		my $yplcontent = findypl($template);
		unless (defined $yplcontent) {
			die "Can't find template $template\n";
		}
		my $stages = parseypl($yplcontent, $args);

		my $conf = {};
		$conf->{'name'} = $name;
		$conf->{'stage'} = $stages;
		$conf->{'sendlist'} = [];
		$conf->{'uniq_map'} = {};
		$conf->{'keepdays'} = $keepdays;
		$conf->{'urlmap'} = {};
		$conf->{'endexec'} = 0;
		$conf->{'idleat'} = 0;
		$conf->{'doing'} = 0;
		$conf->{'restartflag'} = 0;
		if ($test) {
			$testresult->{$name} = { 'exec' => 0,
				'getu' => 0,
				'match' => 0,
				'matchf' => 0, 
				'matchs' => {},
				'matchfs' => {},
			};
		}


		# 解析依赖性关系
		unless ($dep) {
			parsedep($stages);
		}
		if ($nodup) {
			parsedup($stages);
		}
		# 编译
		complie($stages, $enc);
		$conflist{$name} = $conf;
		#print @{$conf->{'sendlist'}};
	}
	uninitypl();
	if ($show_list) {
		print join(' ', keys %{conflist})."\n";
		exit;
	}
	$nodup = 0;
	#my $dump = Dumper($conf);
	#print $dump;
}
# 返回一个相对url的绝对url
sub absurl {
	unless (defined $_[1]) {
		return $_[0];
	}
	my $base;
	my $url = $_[0];
	$base = $_[1];

	$url = URI->new_abs($url, $base);
	return $url;
}
# 试图从curl或者wget命令行中抽取出url
sub trimurl {
	if ($_[0] =~ /^(curl|wget)\s+\'(.+?)\'/) {
		return $2;
	} else {
		return $_[0];
	}
}
# 将url中可能存在的'编码成%27
sub urlstr {
	my ($str) = @_;
	#$str =~ s/([\$`\\"])/\\$1/g;
	$str =~ s/'/%27/g;
	return "'$str'";
}
sub complie {
	my ($stages,$enc) = @_;
	my @skey = keys %{$stages};
	my $definestr = "my (\$context,\$pre_ret) = \@_;\n";
	$definestr .= "my \$pre_url = \$context->{'pre_url'};\n";
	$definestr .= "my \$pre_match = \$context->{'pre_match'};\n";
	my $subheader = "sub {\n";
	my $subfooter = "\n}\n";
	while (my ($key, $value) = each %{$stages}) {
		$value->{'needcontext'} = 1 unless defined $value->{'needcontext'};
		foreach my $rule (@{$value->{'rules'}}) {
			foreach my $reg (@{$rule->{'reglist'}}) {
				# 为了效率改进，不对网页进行转码，而对正则表达式进行
				my $ret = Encode::decode('utf-8', $reg);
				$reg = Encode::encode("$enc", $ret);                       
				# 分析正则表达式中的g标识,因为含有g的无法被预编译
				my $g;
				if ($reg =~ s/(.*\/[ismxe]*)g([ismxe]*)$/$1$2/) {
					$g = 1;       
				} else {                               
					$g = 0;       
				}     
				my $qreg;
				eval('$qreg=qr'.$reg.'');      
				if ($@) {                              
					die "complie err:$@\n$reg\n";  
				}     
				$reg = {'q' => $qreg, 'g' => $g};
			}
		}
		my $f_c;
		# 构造一个函数
		my $def = $definestr;
		my $ret = Encode::decode('utf-8',$value->{'cmd'});
		$value->{'cmd'} = Encode::encode("$enc", $ret);                       
		my $mod = $value->{'cmd'};
		foreach my $s (@skey) {
			if ($mod =~ /\b$s\b/) {
				$def .= "my \$$s = \$context->{'$s'};\n";
			}
		}
		eval("package aaabbc;use strict;use USER;\$f_c = ".$subheader.$def.$value->{'cmd'}.$subfooter);
		if ($@) {
			die "complie err:$@";
		}
		$value->{'cmd'} = $f_c;
		$value->{'isurl'} = 0;
		$value->{'isuniq'} = 0;
		if (defined $value->{'prefix'}) {
			my @prefix = split(/,/, $value->{'prefix'});
			for my $pre (@prefix) {
				if ($pre eq "url") {
					$value->{'isurl'} = 1;
				} elsif ($pre eq "uniq") {
					$value->{'isuniq'} = 1;
				}
			}
			delete $value->{'prefix'};
		}
	}
}
sub parsedup {
	my ($stages) = @_;
	while (my ($k, $v) = each %{$stages}) {
		my $eq = $v->{'eq'}; # 找出循环节点
		next unless defined $eq;
		my $stage = $stages->{$eq};
		next unless defined $stage;
		my @a = ();
		my @b = ();
		my @c = ();
		for my $r (@{$stage->{'rules'}}) {
			my $n = $r->{'next'};
			next unless defined $n;
			my $s = $stages->{$n};
			next unless defined $s;
			if ($n eq $k) { # 循环节点
				push @a, $r;
			} elsif (defined $s->{'isurl'} and defined $s->{'isurl'}) { 
				# 需要排重的节点
				push @b, $r;
			} else { # 其他无关的节点
				push @c, $r;
			}
		}
		next if scalar @a != 1; # 不存在或者多于一个循环节点,不做处理
		next if scalar @a < 1; # 不存在可以排重的节点，也不处理
		my @aa = (@b, @c, @a);
		$stage->{'rules'} = \@aa; # 使循环节点最后处理
		print "$k ->isdup\n";
		$stage->{'isdup'} = 0; # 增加一个标志
	}

}
sub continueexec {
	my ($conf, $stage, $context) = @_;
	my $s = $conf->{'stage'}->{$stage};
	if (defined $s->{'isdup'}) {
		$nodup = 1;
	}
	#my $eqstage = $s->{'eq'};
	#if (defined $eqstage) {print "$stage:$eqstage\n";}
	for my $rule (@{$s->{'rules'}}) {
		matchrule($conf, $stage, $rule->{'reglist'}, 0, $rule->{'next'}, copy($context), $_[3]);
	}
	$nodup = 0;
}
sub execypl {
	$count_execconf++;
	my ($conf, $stage, $context) = @_;
	my $s = $conf->{'stage'}->{$stage};
	unless (defined $s) {
		die "runtime error: $stage not defined\n";
	}
	if ($test) {
		$context->{'parentlist'} .= "$stage,";
		if (my @a = $context->{'parentlist'} =~ /\b$stage\b/g) {
			if (scalar @a >= 4) {
				print "When test, recursion up to 3 times\n";
				return 1;
			}
		}
		$testresult->{$conf->{'name'}}->{'exec'}++;
	}

	print "stage:$stage\n";
	my @ret = &{$s->{'cmd'}}($context, $_[3]);
	my $isurl = $s->{'isurl'};
	my $isuniq = $s->{'isuniq'};

	my $eqstage = $s->{'eq'};
	if (defined $eqstage) {
		$s = $conf->{'stage'}->{$eqstage};
		return 0 unless defined $s;
		my $dup = $s->{'isdup'};
		# 节点全都重复，所以不再继续
		if (defined $dup && $nodup == 1) {
			# 但是为了防止漏掉，几个特定的时间依然抓全
			unless ($g_hour == 12 || $g_hour == 3 || $g_hour == 19) {
				print "all url in this page are duplicate\n";
				return 0;
			}
		}
		$stage = $eqstage;
	}

	$context->{$stage} = [];
	$context->{'pre_match'} = [];

	
	foreach my $r (@ret) {
		die "Use of undefined value in $stage\n" unless defined $r;
		if ($isurl) {
			if ($r =~ /^(wget|curl)/) {
			} else {
				decode_entities($r);
				$r = absurl($r, $context->{'pre_url'});
				$r = urlencode2($r);
			}
			if ($isuniq) {
				next unless uniq($r);
				if ($nodup) {
					# 一旦有一个不重复的, 那么清除重复标志
					$nodup++;
				}
			}

			my $need = $s->{'needcontext'};
			if ($need && exists $cur_conf->{'urlmap'}->{$r}) {
				print "url already in map\n";
				next;
			}
			if ($curid > 90000000) {$curid = 0;}

			# when test, use wget
			if ($stand_alone) {
				print "url:$r\n";
				my $html = localgeturl($r);
				$testresult->{$conf->{'name'}}->{'getu'}++ if $test;
				$context->{'pre_url'} = trimurl($r);
				$curid++;
				$r = $html;
			} else {
				# add context to a list
				print "url($conf->{'name'} $curid):$r\n";
				push (@{$cur_conf->{'sendlist'}}, "$curid\t$stage\t$need\t$r");
				$curid++;
				if ($need) {
					my $context_copy = copy($context);
					$cur_conf->{'urlmap'}->{$r} = $context_copy;
				}
				$r = "";
			}
			next if ($r eq "");
		}

		for my $rule (@{$s->{'rules'}}) {
			matchrule($conf, $stage, $rule->{'reglist'}, 0, $rule->{'next'}, copy($context), $r);
		}
	}
}
sub matchrule {
	$count_match++;
	my ($conf, $stage, $reglist, $num, $next, $context, $content) = @_;

	if (defined $reglist && defined (my $reg = $reglist->[$num])) {
		my $qreg = $reg->{'q'};
		my $g = $reg->{'g'};
		my @b = ();
		my @p = ();
		if (defined $context->{$stage}) {
			@b = (@{$context->{$stage}});
		}
		if (defined $context->{'pre_match'}) {
			@p = (@{$context->{'pre_match'}});
		}
		my $matched = 0;
		while ($content =~ /$qreg/g) {
			$matched++;
			my @a = ();
			for (my $i = 1; $i <= $#-; $i++) {
				no strict 'refs';
				my $k = $i;
				#if (defined $$k) {
				push @a, $$i;
					#} else {
					#last;
					#}
				use strict 'refs';
			}
			my @c = (@b, @a);
			my @d = (@p, @a);
			$context->{$stage} = \@c;
			$context->{'pre_match'} = \@d;
			if ($test) {
				$testresult->{$conf->{'name'}}->{'match'}++;
				$testresult->{$conf->{'name'}}->{'matchs'}->{$qreg}++;
			}
			if ($stand_alone) {
				matchrule($conf, $stage, $reglist, $num + 1, $next, copy($context), $content);
			} else {
				matchrule($conf, $stage, $reglist, $num + 1, $next, $context, $content);
			}
			last unless $g;
			if ($test && $matched >= 2) {
				print "When test, match up to 2 times at most\n";
				last;
			}
		}
		unless ($matched) {
			print STDERR "$qreg----------------------no match:\n";
			print STDERR $context->{'pre_url'}."\n" if (defined $context->{'pre_url'});
			if ($test) {
				$testresult->{$conf->{'name'}}->{'matchf'}++;
				$testresult->{$conf->{'name'}}->{'matchfs'}->{$qreg}++;
			}
		}
	}
	else {
		execypl($conf, $next, $context, $content);
	}
}
################  start ############################
die usage() unless parsecmd();
for my $name (keys %conflist) {
	mkpath("$workingdir/$readydir/$name");
	mkpath("$workingdir/status/$name");
}

# 加载状态
for my $name (keys %conflist) {
	$conf_name = $name;
	$cur_conf = $conflist{$name};
	loadandsave(0);
}
# 信号处理
my $time_to_die = 0;
sub signal_handler {
	$time_to_die = 1;
}
$SIG{INT} = $SIG{TERM} = $SIG{HUP} = \&signal_handler unless ($test or $stand_alone);
# 控制刷新url排重表的变量，每天刷新一次
my $refreshed = 1;
# loop
MAIN: while(!$time_to_die)
{
	updateinfo();
	# refresh uniq map
	my $needrefresh = 0;
	if ($g_hour > 2 && $g_hour < 18 && !$refreshed) {
		$needrefresh = 1;
		$refreshed = 1;
	} elsif ($g_hour >= 18 && $refreshed) {
		$refreshed = 0;
	}
	my $ret = 0;
	# recieve and parse
	while( my ($name,$conf) = each (%conflist)) {
		$conf_name = $name;
		$cur_conf = $conf;
		setconfname($name);
		if ($needrefresh) {
			refresh_uniq_map();
		}
		$ret |= getresult2($name);
	}
	if ($ret) {
		next;
	}
	# send
	sendbuf();
	while( my ($name,$conf) = each (%conflist)) {
		#print $name."\n";
		my $count = @{$conf->{'sendlist'}};
		if ($count > 0) {
			print ">0\n";
			# 队列大于0个，则不产生新的url, 也不会结束
			next;
		}
		my $mapsize = scalar(keys(%{$conf->{'urlmap'}}));
		# 产生开始的url
		unless ($conf->{'endexec'} || $mapsize > 1000) { #如果有大于1000个url在外面,则不再产生新的url
			#sleep 1;
			$cur_conf = $conf;
			$conf_name = $name; 
			setconfname($name);
			for (my $i = 0; $i < 5 && !$conf->{'endexec'}; $i++) {
				$conf->{'endexec'} = 1;
				$conf->{'restartflag'} = 1;
				if ($test) {
					# 测试时，严重错误需要打印测试结果,所以这里用eval避免直接结束
					eval {
						execypl($conf, 'start', {});
					};
					if ($@) {
						print STDERR $@."\n";	
						last;
					}
				} else {
					execypl($conf, 'start', {});
				}
				#execypl($conf, 'start', {}, $calltimes);
				#$calltimes++;
			}
		}
		$count = @{$conf->{'sendlist'}};

		# 没有发送/接收过数据
		if ($conf->{'doing'} == 0) {
			#sleep 1;
			#if ($conf->{'endexec'} && !$count) { # 空闲
			if (!$count) { # 空闲
				if ($conf->{'idleat'} == 0) {
					$conf->{'idleat'} = $now;
				}
				if ($now - $conf->{'idleat'} > $MAXIDLE) {
					$conf->{'idleat'} = $now;
					# 重新开始或结束的时候忽略以前的信息
					$conf->{'urlmap'} = {};
					# last unless ($restartflag);
					if ($conf->{'endexec'}) {
						if ($conf->{'restartflag'}) {
							print "----------$name----------restarting----------$now-----\n";
							# 重新开始
							$conf->{'restartflag'} = 0;
							$conf->{'endexec'} = 0;
						} else {
							delete $conflist{$name};
						}
					}
					# $calltimes = 0;
				}
			}
		} else {
			$conf->{'idleat'} = 0;
			$conf->{'doing'} = 0;
			print "$name:urlmap size=".$mapsize."\n";
		}
	}
	# 测试时只走一轮
	last if $test;
	sleep 1;
}
# 保存状态
for my $name (keys %conflist) {
	$conf_name = $name;
	$cur_conf = $conflist{$name};
	loadandsave(1);
}
if ($test) {
	print STDERR "stage\tgeturl\tmatch\tfailed\tname\n";
	while (my ($name, $r) = each (%{$testresult})) {
		print STDERR "$r->{'exec'}\t$r->{'getu'}\t$r->{'match'}\t$r->{'matchf'}\t$name\n";
		while (my ($preg, $c) = each %{$r->{'matchfs'}}) {
			my $c2 = $r->{'matchs'}->{$preg};
			unless (defined $c2) {
				print STDERR "--$preg never matched\n";
				next;
			}
			if ($c2 < $c) {
				print STDERR "--$preg failed $c, matched $c2\n";
			}
		}
	}
}
