package RSGet::MicroHTTP;

use strict;
use warnings;
use IO::Socket;
use RSGet::Tools;

my @template = <DATA>;
our %data = (
	last_lines => '',
	status => '',
	dl_list => '',
);

sub new
{
	my $class = shift;
	my $port = shift;
	my $socket = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalPort => $port,
		Listen => SOMAXCONN,
		Reuse => 1,
		Blocking => 0,
	) || return undef;

	my $self = \$socket;
	return bless $self, $class;
}

sub perform
{
	my $self = shift;
	my $socket = $$self;

	my @ret;

	my $client = $socket->accept();
	return () unless $client;

	u_last_lines();
	u_status();
	u_dl_list();

	push @ret, request( $client );

	for ( my $i = 0; $i < 5; $i++ ) {
		my $client = $socket->accept() or last;
		push @ret, request( $client );
	}

	return @ret;
}

sub request
{
	my $client = shift;
	local $SIG{ALRM} = sub {
		die "HTTP Frozen !\n";
	};
	alarm 5; # XXX: this must be fixed
	my $request = <$client>;
	unless ( $request ) {
		close $client;
		alarm 0;
		return;
	}
	chomp $request;

	my( $method, $file, $ignore ) = split /\s+/, $request;
	p "HTTP request: $method: $file";

	my $len = 0;
	while ( $_ = <$client> ) {
		$len = $1 if /^Content-Length:\s*(\d+)/i;
		last if /^\s*$/;
	}
	if ( $len and $method =~ /^POST$/i ) {
		my $r;
		$client->read( $r, $len );
		foreach ( split /&/, $r ) {
			s/^(.*?)=//;
			my $key = $1;
			tr/+/ /;
			s/%(..)/chr hex $1/eg;
			RSGet::FileList::add_text( $key, $_ );
		}
	}

	print $client "HTTP/1.1 200 OK\r\n";
	print $client "Content-Type: text/html; charset=utf-8\r\n";
	print $client "\r\n";
	foreach my $line ( @template ) {
		local $_ = $line;
		s/\${([a-z_]+)}/$data{$1}/g;
		print $client $_;
	}
	close $client;
	alarm 0;

	return 1;
}

sub u_last_lines
{
	my $out = "";
	foreach my $line ( @RSGet::Line::dead ) {
		local $_ = $line;
		s/&/&amp;/g;
		s/</&lt;/g;
		s/>/&gt;/g;
		s#(^|\s)(http://\S*)#$1<a href="$2">$2</a>#g;
		$out .= "<li>$_</li>\n";
	}
	$data{last_lines} = $out;
	return;
}

sub u_status
{
	my $out = "";
	foreach my $line ( @RSGet::Line::active ) {
		local $_ = $line;
		s/&/&amp;/g;
		s/</&lt;/g;
		s/>/&gt;/g;
		s#(^|\s)(http://\S*)#$1<a href="$2">$2</a>#g;
		$out .= "<li>$_</li>\n";
	}
	$data{status} = $out;
	return;
}

sub u_dl_list
{
	unless ( -r $RSGet::FileList::file ) {
		$data{dl_list} = '<li></li>';
	}

	my $out = "";
	open my $list, '<', $RSGet::FileList::file;
	while ( $_ = <$list> ) {
		chomp;
		my $class = "";
		$class = ' class="comment"' if /^\s*#/;
		s/&/&amp;/g;
		s/</&lt;/g;
		s/>/&gt;/g;
		s{(^|\s|#)(http://\S*)}{$1<a href="$2">$2</a>}g;
		$out .= "<li$class>$_</li>\n";
	}
	close $list;

	$data{dl_list} = $out;
	return;
}
1;

__DATA__
<html>
<head>
	<title>rsget.pl</title>
<style>
html {
	background: #333;
}
body {
	width: 900px;
	margin: 10px;
	margin-left: auto;
	margin-right: auto;
	border: 10px solid #555;
	padding: 5px;
	background: #777;
	font-family: monospace;
}
fieldset {
	border: 10px solid #999;
	padding: 5px;
	margin: 5px;
	background: #bbb;
}
input, textarea {
	border: 10px solid #ddd;
	padding: 5px;
	margin: 5px;
	background: #fff;
}
input {
	width: 150px;
	margin-left: 700px;
}
legend {
	border: 10px solid #999;
	border-top: 0;
	border-bottom: 0;
	background: #bbb;
}
ul {
	border: 10px solid #ddd;
	padding: 5px;
	margin: 5px;
	background: #fff;
	list-style: none;
}
li:first-child {
	border-top: 0;
}
li {
	border-top: 2px solid #ddd;
	white-space: pre;
}
li.comment {
	color: #00F;
}
a, a:visited {
	color: inherit;
}
</style>
</head>
<body>
	<fieldset>
		<legend>Last lines</legend>
		<ul>${last_lines}</ul>
	</fieldset>

	<fieldset>
		<legend>Status</legend>
		<ul>${status}</ul>
	</fieldset>

	<fieldset>
		<legend>Download list</legend>
		<ul>${dl_list}</ul>
	</fieldset>

	<form action="" method="post">
		<fieldset>
			<legend>Extract links from text</legend>
			<textarea cols="100" rows="16" name="links"></textarea>
			<input type="submit" value="OK" />
		</fieldset>
		<fieldset>
			<legend>Append whole text to download list</legend>
			<textarea cols="100" rows="16" name="text"></textarea>
			<input type="submit" value="OK" />
		</fieldset>
	</form>
</body>
</html>
