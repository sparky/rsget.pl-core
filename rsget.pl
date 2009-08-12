#!/usr/bin/perl
#
# 2008 (c) Przemysław Iskra <sparky@pld-linux.org>
# Use/modify/distribute under GPL v2 or newer.
#
=item TODO:

- removing URI from list should stop download
- new URI higher in the list should replace any connection
  to the same network if still in the wait stage
- check all the URIs just after finding them in the list
  (catch non-existing files quickly)
- OdSiebie: there is a captcha now

=item Status:
- RS: 2009-08-12 OK
- NL: 2009-08-12 OK, captcha works
- OS: not working, captcha not supported
- MU: 2009-08-12 OK, captcha works, requires mu_font_db.png
- UT: 2009-06-07 OK
- HF: captcha not supported
- FF: 2009-08-12 OK
- DF: 2009-08-12 OK
- TU: 2009-08-12 OK
- ST: 2009-08-12 OK

=item Wishlist:
- handle multiple alternatives for same file
- add more servers

=cut
use strict;
use warnings;
use Time::HiRes;

our $data_path = $ENV{PWD};

my $checklist = 1;
my %gotlist;
$SIG{CHLD} = "IGNORE";

my %getters;

package Line; # {{{
use Term::Size;

$| = 1;
my $actual_line = 0;
my $max_line = 0;

my $columns = Term::Size::chars;

sub new
{
	my $proto = shift;
    my $class = ref( $proto ) || $proto;

	my $steps = $max_line - $actual_line;
	$actual_line = $max_line;
	my $move = "";

	if ( $steps < 0 ) {
		return undef;
	} elsif ( $steps > 0 ) {
		$move = "\033[" . $steps . "B";
	}

	print $move . "\n\r\033[K";

	my $line = $max_line++;
	my $self = \$line;
	return bless $self, $class;
}

sub print
{
	my $self = shift;
	my $text = shift;
	my $line = $$self;

	return undef if $line >= $max_line;
	my $steps = $line - $actual_line;
	$actual_line = $line;
	my $move = "";

	if ( $steps < 0 ) {
		$move = "\033[" . (-$steps) . "A";
	} elsif ( $steps > 0 ) {
		$move = "\033[" . $steps . "B";
	}
	my $tl = length $text;
	substr $text, 22, $tl - $columns + 3, '...'
		if $tl > $columns;
	
	print $move . "\r\033[K" . $text;
}

# }}}
package Curl; # {{{
use WWW::Curl::Easy;
use WWW::Curl::Multi;
use URI::Escape;

my $curl_headers = [
	'User-Agent: Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.9.0.10) Gecko/2009042316 Firefox/3.0.10',
	'Accept: text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5',
	'Accept-Charset: ISO-8859-1,utf-8;q=0.7,*;q=0.7',
	'Accept-Language: en-us,en;q=0.5',
	];

sub file_init
{
	my $self = shift;
	my $curl = $self->{curl};

	$self->{time_start} = time;

	{
		my $mime = $curl->getinfo( 	CURLINFO_CONTENT_TYPE );
		if ( $mime =~ m#^text/html# ) {
			$self->{is_html} = 1;
			$self->{size_total} = 0;
			$self->{size_got} = 0;
			return;
		}
	}

	{
		my $f_len = $curl->getinfo( CURLINFO_CONTENT_LENGTH_DOWNLOAD );
		$self->{size_total} = $f_len || 0;
		$self->{size_got} = 0;
	}

	if ( $self->{head} =~ /^Content-Disposition:\s*attachment;\s*filename\s*=\s*"?(.*?)"?\s*$/im ) {
		$self->{file_name} = $1;
	} else {
		my $eurl = $curl->getinfo( CURLINFO_EFFECTIVE_URL );
		$eurl =~ s#^.*/##;
		$self->{file_name} = uri_unescape( $eurl );
	}

	{
		my $fn = $self->{file_name};
		if ( -r $fn ) {
			my $fn_old = $fn;
			my $ext = "";
			$ext = $1 if $fn_old =~ s/(\..{3,5})$//;
			my $i = 1;
			while ( -r "$fn_old-$i$ext" ) {
				$i++;
			}
			$fn_old .= "-$i$ext";
			rename $fn, $fn_old;
		}
		my $net = $self->{obj}->{net};
		$self->{obj}->{netname} =~ s/] .*/] $fn: /;
	}

	{
		open my $f_out, '>', $self->{file_name};
		$self->{file} = $f_out;
	}
}

sub body_file
{
	my ($chunk, $self) = @_;

	file_init( $self ) unless exists $self->{size_total};

	my $len = length $chunk;
	$self->{size_got} += $len;

	if ( $self->{file} ) {
		my $file = $self->{file};
		my $p = print $file $chunk;
		die "\nCannot write data: $!\n" unless $p;
	} else {
		$self->{body} .= $chunk;
	}

	return $len;
}

sub body_scalar
{
	my ($chunk, $scalar) = @_;
	$$scalar .= $chunk;
	return length $chunk;
}


my $mcurl = new WWW::Curl::Multi;
my %curling;

sub start
{
	my $url = shift;
	my $obj = shift;
	my %opts = @_;

	my $curl = new WWW::Curl::Easy;

	my $id = 1;
	++$id while exists $curling{ $id };

	my $ecurl = {
		curl => $curl,
		id => $id,
		got => 0,
		head => "",
		body => "",
		obj => $obj,
	};

    $curl->setopt( CURLOPT_PRIVATE, $id );
	if ( $obj->{outaddr} ) {
		$curl->setopt( CURLOPT_INTERFACE, $obj->{outaddr} );
	}
	
	if ( defined $opts{cookies} ) {
		$curl->setopt( CURLOPT_COOKIEJAR, $opts{cookies} );
		$curl->setopt( CURLOPT_COOKIEFILE, $opts{cookies} );
	}
	$curl->setopt( CURLOPT_HEADERFUNCTION, \&body_scalar );
	$curl->setopt( CURLOPT_WRITEHEADER, \$ecurl->{head} );
	$curl->setopt( CURLOPT_MAXREDIRS, 10 );
	$curl->setopt( CURLOPT_FOLLOWLOCATION, 1 );
	$curl->setopt( CURLOPT_HTTPHEADER, $curl_headers );
	$curl->setopt( CURLOPT_URL, $url );
	$curl->setopt( CURLOPT_REFERER, $opts{referer} )
		if defined $opts{referer};
	$curl->setopt( CURLOPT_ENCODING, 'gzip,deflate' );
	$curl->setopt( CURLOPT_CONNECTTIMEOUT, 20 );

	if ( $opts{post} ) {
		my $post = $opts{post};
		$curl->setopt( CURLOPT_POST, 1 );
		$curl->setopt( CURLOPT_POSTFIELDS, $post );
	}

	if ( $opts{save} ) {
		$curl->setopt( CURLOPT_WRITEFUNCTION, \&body_file );
		$curl->setopt( CURLOPT_WRITEDATA, $ecurl );
	} else {
		$ecurl->{is_html} = 1;
		$curl->setopt( CURLOPT_WRITEFUNCTION, \&body_scalar );
		$curl->setopt( CURLOPT_WRITEDATA, \$ecurl->{body} );
	}

	$curling{ $id } = $ecurl;
    $mcurl->add_handle( $curl );
}

sub finish
{
	my $id = shift;
	my $err = shift;

	my $ecurl = $curling{ $id };
	delete $curling{ $id };

	my $curl = $ecurl->{curl};
	delete $ecurl->{curl}; # remove circular dep

	my $obj = $ecurl->{obj};
	delete $ecurl->{obj};

	if ( $ecurl->{file} ) {
		close $ecurl->{file};
		$obj->print( donemsg( $ecurl ) );
	}

	if ( $err ) {
		my $error = $curl->errbuf;
		$obj->print( "error($err): $error" );
		$obj->problem();
		return undef;
	}

	if ( $obj->{curl_next} ) {
		my $func = $obj->{curl_next};
		my $body = $ecurl->{file}
			? "DONE $ecurl->{file_name} " . main::bignum( $ecurl->{size_got} )
				. " / " . main::bignum( $ecurl->{size_total} )
			: $ecurl->{body};
		my $eurl = $curl->getinfo( CURLINFO_EFFECTIVE_URL );
		
		&$func( $obj, $body, $eurl, $ecurl->{is_html} );
	}
}

sub perform
{
	my $running = scalar keys %curling;
	return unless $running;
	my $act = $mcurl->perform();
	return if $act == $running;

	while ( my ($id, $rv) = $mcurl->info_read() ) {
		next unless $id;

		finish( $id, $rv );
	}
}

sub print_status
{
	my $time = time;

	foreach my $ecurl ( values %curling ) {
		next unless exists $ecurl->{size_total};
		my $size_got = $ecurl->{size_got};
		my $size_total = $ecurl->{size_total};

		my $size = main::bignum( $size_got ) . " / " . main::bignum( $size_total );
		my $eta = "";
		my $time_diff = $time - $ecurl->{time_start};
		if ( $size_total > 0 ) {
			$size .= sprintf " [%.2f%%]", $size_got * 100 / $size_total;
			if ( $time_diff > 0 ) {
				my $tleft = ($size_total - $size_got) * $time_diff / $size_got;
				$eta = main::s2string( $tleft );
			}
		}
		my $speed = "???";
		$speed = sprintf "%.2f", $size_got / ( $time_diff * 1024 )
			if $time_diff > 0;

		$ecurl->{obj}->print( "$size; ${speed}KB/s $eta" );
	}
}

sub donemsg
{
	my $ecurl = shift;

	my $size_total = $ecurl->{size_got};

	my $time_diff = time() - $ecurl->{time_start};
	$time_diff = 1 unless $time_diff;
	my $eta = main::s2string( $time_diff );
	my $speed = sprintf "%.2f", $size_total / ( $time_diff * 1024 );

	my @l = localtime;
	my $date = sprintf "%d-%.2d-%.2d %2d:%.2d:%.2d", $l[5] + 1900, $l[4] + 1, @l[(3,2,1,0)];
	return "DONE " . main::bignum( $size_total ) . "; ${speed}KB/s $eta @ $date";
}


# }}}
package Wait; # {{{

my %waiting;

sub start
{
	my $obj = shift;
	my $time = shift;
	$obj->{wait_until} = time + $time;

	my $id = 0;
	++$id while exists $waiting{ $id };
	$waiting{ $id } = $obj;
}

sub finish
{
	my $id = shift;

	my $obj = $waiting{ $id };
	delete $waiting{ $id };

	my $func = $obj->{wait_next};
		
	&$func( $obj );
}

sub perform
{
	my $time = time;

	foreach my $id ( keys %waiting ) {
		my $obj = $waiting{ $id };
		my $left = $obj->{wait_until} - $time;
		if ( $left <= 0 ) {
			finish( $id );
		} else {
			$obj->print( $obj->{wait_msg} . main::s2string( $left ) );
		}
	}
}

# }}}
package Get; # {{{

use URI;
my @outaddr;

sub add_outaddr
{
	my $newaddr = shift;
	NEW_IP: foreach my $ip ( split /[ ,]+/, $newaddr ) {
		foreach my $outaddr ( @outaddr ) {
			if ( $ip eq $outaddr ) {
				print "Address $ip already on the list\n";
				next NEW_IP;
			}
		}
		print "Adding $ip address\n";
		push @outaddr, $ip;
	}
}

my %running;
sub makenew
{
	my $net = shift;
	my $class = shift;
	my $url = shift;
	my $slots = 1;
	if ( scalar @_ and $_[0] eq "slots" ) {
		shift;
		$slots = shift;
	}
	if ( scalar @outaddr > $slots ) {
		$slots = scalar @outaddr;
	}

	my @opts = split /\s+/, $url;
	$url = shift @opts;
	my %opts = map { /(.*?)=(.*)/ ? ( $1, $2 ) : ( $_, 1 ) } @opts;

	return {} if $gotlist{ $url };
	$running{ $net } = {} unless exists $running{ $net };
	my $rn = $running{ $net };
	return {} if $slots <= scalar keys %$rn;
	foreach my $id ( keys %$rn ) {
		if ( $rn->{ $id }->{url} eq $url ) {
			return {};
		}
	}

	my $outaddr = undef;
	if ( scalar @outaddr ) {
		FIND_IP: foreach my $maybe_outaddr ( @outaddr ) {
			foreach my $id ( keys %$rn ) {
				if ( $rn->{ $id }->{outaddr} eq $maybe_outaddr ) {
					next FIND_IP;
				}
			}
			$outaddr = $maybe_outaddr;
			last;
		}
		# no IP found ?
		return {}
			unless defined $outaddr;
	}
	my $outaddrstr = $outaddr ? "[$outaddr]" :  "";

	my $id = 1;
	++$id while exists $rn->{ $id };

	my $line = new Line;

	( my $fn = $url ) =~ s{/+$}{};
	$fn =~ s#^.*/##;

	my $self = {
		@_,
		url => $url,
		opts => \%opts,
		id => $id,
		try => 0,
		line => $line,
		net => $net,
		netname => "[$net]$outaddrstr $fn: ",
		outaddr => $outaddr,
	};

	$rn->{ $id } = bless $self, $class;

	$self->stage1();
	return $self;
}

sub print
{
	my $self = shift;
	my $text = shift;
	my $line = $self->{line};
	$line->print( $self->{netname} . $text );
}

sub curl
{
	my $self = shift;
	my $url = shift;
	my $next_stage = shift;

	$url = URI->new( $url )->abs( $self->{referer} )->as_string
		if $self->{referer};

	$self->{curl_next} = $next_stage;
	Curl::start( $url, $self,
		(referer => $self->{referer}),
		(cookies => $self->{cookies}),
		(outaddr => $self->{outaddr}),
		@_ );
}

sub download
{
	my $self = shift;
	$self->print("starting download");
	$self->{file_html} = \&start unless defined $self->{file_html};
	$self->curl( $self->{file_url}, \&finish, save => 1, @_ );
}

sub wait
{
	my $self = shift;
	my $time = shift;
	my $next_stage = shift;
	my $msg = shift || "waiting";

	$time = 30 * 60 if $time > 30 * 60;

	$self->{wait_next} = $next_stage;
	$self->{wait_msg} = $msg . " ";
	Wait::start( $self, $time );
}

sub multi
{
	my $self = shift;
	return $self->wait( 5 * 60 * rand, \&start, "multi-download not allowed, waiting" );
}

sub finish
{
	my $self = shift;
	my $body = shift;
	my $url = shift;
	my $is_html = shift;

	if ( $is_html ) {
		if ( my $func = $self->{file_html} ) {
			delete $self->{file_url};
			delete $self->{file_html};
			return &$func( $self, $body, $url );
		}
	}

	$gotlist{ $self->{url} } = $body;

	my $net = $self->{net};
	my $id = $self->{id};
	delete $running{ $net }->{ $id };

	$checklist = 1;
}

sub finish_links
{
	my $self = shift;

	$gotlist{ $self->{url} } = [@_];

	my $net = $self->{net};
	my $id = $self->{id};
	delete $running{ $net }->{ $id };

	$checklist = 1;
}

sub error
{
	my $self = shift;
	my $msg = shift;
	my $data = shift;
	if ( $data ) {
		my $n = 0;
		my $name;
		do {
			$name = "errorlog." . (++$n) . ".html";
		} while ( -r $name );
		open ERR_OUT, '>', $name;
		print ERR_OUT $data;
		close ERR_OUT;

		$msg .= "; saved $name";
	}

	$self->print( $msg );
	$self->finish( $msg );
}

sub start
{
	my $self = shift;
	return $self->stage1();
}

sub problem
{
	my $self = shift;
	my $var = shift;
	my $data = shift;
	my $msg = "";
	$msg = " (undefined var: $var)" if $var;
	if ( ++$self->{try} < 8 ) {
		return $self->wait( 2 ** $self->{try}, \&start, "unknown problem$msg, waiting" );
	} else {
		return $self->error( "unknown problem$msg, aborting", $data );
	}
}

# }}}
package Get::RapidShare; # {{{

BEGIN {
	our @ISA;
	@ISA = qw(Get);
}

sub new
{
	my $proto = shift;
	my $class = ref $proto || $proto;
	my $url = shift;
	Get::makenew( "RS", $class, $url );
}

sub stage1
{
	my $self = shift;
	delete $self->{referer};

	$self->print("starting...");
	$self->curl( $self->{url}, \&stage2 );
}

sub stage2
{
	my ($self, $body, $url) = @_;
	$self->print("starting......");
	$self->{referer} = $url;

	my $link;
	if ( $body =~ /The file could not be found\.  Please check the download link\./m ) {
		return $self->error( "file not found" );
	} elsif ( $body =~ /file has been removed from the server\./m ) {
		return $self->error( "file removed" );
	} elsif ( $body =~ /Unfortunately you will have to wait ([0-9]+) minutes,/m ) {
		return $self->wait( $1 * 60, \&stage1, "servers overloaded, waiting" );
	} elsif ( $body =~ /form id="ff" action="(.*?)"/m ) {
		$link = $1;
	} else {
		return $self->problem( "link", $body );
	}

	$self->curl( $link, \&stage3, post => 'dl.start=Free' );
}

sub stage3
{
	my ($self, $body, $url) = @_;
	$self->print("starting.........");
	$self->{referer} = $url;

	if ( $body =~ /Please wait until the download is completed/m ) {
		return $self->multi();
	}
	if ( $body =~ /You have reached the download limit for free-users\./m ) {
		$body =~ /Instant download access! Or try again in about ([0-9]+) minutes\./m;
		my $m = $1;
		return $self->wait( $m * 60 + 10, \&stage1, "free limit reached, waiting" );
	} elsif ( $body =~ /Unfortunately you will have to wait ([0-9]+) minutes,/m ) {
		return $self->wait( $1 * 60, \&stage1, "servers overloaded, waiting" );
	}
	unless ( $body =~ /var c=([0-9]+);/m ) {
		return $self->problem( "var c=", $body );
	}
	my $wait = $1;

	$body =~ /form name="dlf" action="(.*?)"/m;
	$self->{file_url} = $1;

	$self->wait( $wait, \&stage4, "starting download in" );
}

sub stage4
{
	my $self = shift;
	$self->print("downloading");

	$self->download( post => 'mirror=on' );
}

$getters{RS} = {
	uri => qr{rapidshare\.com/.*?},
	add => sub { Get::RapidShare->new( @_ ) },
};

# }}}
package Get::NetLoad; # {{{

BEGIN {
	our @ISA;
	@ISA = qw(Get);
}

my $nlcookie = 0;
sub new
{
	my $proto = shift;
	my $class = ref $proto || $proto;
	my $url = shift;

	++$nlcookie;
	my $cookie = ".cookie.nl.$nlcookie.txt";
	unlink $cookie if -e $cookie;

	Get::makenew( "NL", $class, $url, cookies => $cookie );
}

sub stage1
{
	my $self = shift;

	$self->print("starting...");
	delete $self->{referer};
	$self->curl( $self->{url}, \&stage2 );
}

sub stage2
{
	my ($self, $body, $url) = @_;
	$self->print("starting......");
	$self->{referer} = $url;

	if ( $body =~ /(Sorry, we don't host the requested file|unknown_file_data)/ ) {
		return $self->error( "file not found" );
	}
	if ( $body =~ /We will prepare your download/ ) {
		return $self->wait( 60, \&stage1 );
	}
	my ($link) = ($body =~ /href="(.*?captcha=1)"/);
	unless ( defined $link ) {
		if ($body =~ /MAINTENANCE/ ) {
			return $self->wait( 10 * 60, \&stage1, "server maintenence, will try in" );
		}
		return $self->problem( "link", $body );
	}
	$link =~ s/&amp;/&/g;

	$self->curl( $link, \&stage3 );
}

sub stage3
{
	my ($self, $body, $url) = @_;
	$self->print("starting.........");
	$self->{referer} = $url;

	if ( $body =~ /"(.*?captcha=1)"/) {
		return $self->stage2( $body, $url );
	}

	my %search = (
		action => qr#<form method="post" action="(.*?)">#,
		captcha_img => qr#"(share/includes/captcha\.php\?t=[0-9]+)"#,
		file_id => qr#input name="file_id" .*value="(.*?)"#,
		s3wait => qr#please wait .*countdown\(([0-9]+),#,
	);

	foreach my $name ( keys %search ) {
		my $search = $search{$name};
		if ( $body =~ m/$search/ ) {
			$self->{$name} = $1;
		} else {
			return $self->problem( $name, $body )
		}
	}

	$self->curl( $self->{captcha_img}, \&stage4 );
}

sub stage4
{
	my ($self, $body, $url) = @_;
	$self->print("reading captcha");

	my $captcha = Get::NetLoad::Captcha::resolve( $body );

	unless ( defined $captcha ) {
		return $self->curl( $self->{captcha_img}, \&stage4 );
	}
	$self->{captcha} = $captcha;

	$self->wait( $self->{s3wait} / 100 + 1, \&stage5, "checking in" );
}

sub stage5
{
	my $self = shift;
	$self->print("starting............");

	my $post = "file_id=$self->{file_id}&captcha_check=$self->{captcha}&start=";
	$self->curl( $self->{action}, \&stage6, post => $post );
}

sub stage6
{
	my ($self, $body, $url) = @_;
	$self->print("starting...............");
	$self->{referer} = $url;

	if ( $body =~ /You may forgot the security code or it might be wrong/ ) {
		return $self->stage1();
	}
	if ( $body =~ /This file is currently unavailable/ ) {
		return $self->error( "file currently unavailable" );
	}
	if ( $body =~ /You could download your next file in.*countdown\(([0-9]+)/ ) {
		my $s = $1 / 100;
		$s = 10 * 60 if $s > 10 * 60;
		return $self->wait( $s, \&stage1, "free limit reached, waiting" );
	}
	unless ( $body =~ /please wait .*countdown\(([0-9]+),/ ) {
		return $self->problem( "countdown", $body );
	}
	my $wait = $1 / 100 + 1;
	unless ( $body =~ m#<a class="Orange_Link" href="(.*?)"#) {
		return $self->problem( "Orange_Link", $body );
	}
	$self->{file_url} = $1;

	$self->wait( $wait, \&stage7, "starting in" );
}

sub stage7
{
	my $self = shift;
	$self->print("downloading");

	$self->download();
}

sub DESTROY
{
	my $self = shift;
	unlink $self->{cookies};
}

$getters{NL} = {
	uri => qr{netload\.in/datei.*?},
	add => sub { Get::NetLoad->new( @_ ) },
};

# }}}
package Get::NetLoad::Captcha; # {{{

sub blankline
{
	my $img = shift;
	my $x = shift;
	my $n = 0;
	my $white = $img->colorClosest( 255, 255, 255 );
	foreach my $y ( 0..28 ) {
		my $ci = $img->getPixel( $x, $y );
		next if $ci == $white;
		$n++;
		return 0 if $n > 1;
	}
	return 1;
}

sub blanklinev
{
	my $img = shift;
	my $y = shift;
	my $y2 = $y + shift;
	my $xmin = shift;
	my $xmax = shift;
	my $n = 0;
	my $white = $img->colorClosest( 255, 255, 255 );
	foreach my $x ( $xmin..$xmax ) {
		my $ci = $img->getPixel( $x, $y );
		$n++ if $ci != $white;
		$ci = $img->getPixel( $x, $y2 );
		$n++ if $ci != $white;
		return 0 if $n > 2;
	}
	return 1;
}

sub charat
{
	require GD;
	my $img = shift;
	my $trimg = shift;
	my $sx = shift;

	my $xmin = $sx;
	until( blankline( $img, $xmin ) ) {
		$xmin--;
	}
	my $xmax = $sx+1;
	until( blankline( $img, $xmax ) ) {
		$xmax++;
	}
	my $ymin = 14;
	until( blanklinev( $img, $ymin, -1, $xmin, $xmax ) ) {
		$ymin--;
	}
	my $ymax = 15;
	until( blanklinev( $img, $ymax, +1, $xmin, $xmax ) ) {
		$ymax++;
	}

	my $w = $xmax - $xmin;
	my $h = $ymax - $ymin;
	my $nimg = new GD::Image( $w * 4 + 16, ($h > 12 ? $h : 12 ) + 4 );
	my $nw = $nimg->colorAllocate( 255, 255, 255);
	$nimg->copy( $trimg, 1, 1, $xmin, $ymin, $w, $h );
	$nimg->copy( $trimg, 3 + 1*$w, 1, $xmin, $ymin, $w, $h );
	$nimg->copy( $trimg, 13 + 2*$w, 1, $xmin, $ymin, $w, $h );
	$nimg->copy( $trimg, 15 + 3*$w, 1, $xmin, $ymin, $w, $h );

	require IPC::Open2;
	IPC::Open2::open2( *READ, *WRITE, "pngtopnm | gocr -f ASCII -a 5 -m 56 -C 0123456789 - 2>/dev/null" );
	print WRITE $nimg->png;
	close WRITE;
	my $num = <READ> || "";
	close READ;

	my ($gocr) = ($num =~ /^([0-9])/);

	IPC::Open2::open2( *READ, *WRITE, "pngtopnm | ocrad --filter=numbers_only - 2>/dev/null" );
	print WRITE $nimg->png;
	close WRITE;
	$num = <READ> || "";
	close READ;

	my ($ocrad) = ($num =~ /^([0-9])/);

	#print "G: $gocr, O: $ocrad\n";
	if ( defined $gocr ) {
		return 7 if ( defined $ocrad and $ocrad == 7 and $gocr == 1 );
		return $gocr;
	} elsif ( defined $ocrad ) {
		return $ocrad;
	}
	return undef;
}

sub resolve
{
	my $capdata = shift;
	require GD;

	my $img = GD::Image->new( $capdata );
	my $white = $img->colorClosest( 255, 255, 255 );

	foreach my $y ( 0..28 ) {
		$img->setPixel( 0, $y, $white );
		$img->setPixel( 73, $y, $white );
	}
	foreach my $x ( 0..73 ) {
		$img->setPixel( $x, 0, $white );
		$img->setPixel( $x, 28, $white );
	}

	foreach my $y ( 1..27 ) {
		FORX: foreach my $x ( 1..72 ) {
			my $ci = $img->getPixel( $x, $y );
			next if $ci == $white;
			my @xy = ( [0, 1], [0, -1], [1, 0], [-1, 0] );
	
			my $wrong = 0;
			foreach my $xy ( @xy ) {
				my $c = $img->getPixel( $x + $xy->[0], $y + $xy->[1] );
				if ( $c != $white ) {
					$wrong++;
					next FORX if $wrong > 1;
				}
			}
	
			$img->setPixel( $x, $y, $white );
		}
	}


	my $trimg = GD::Image->newTrueColor( 74, 29 );
	my $trwhite = $trimg->colorAllocate( 255, 255, 255 );
	$trimg->fill( 0, 0, $trwhite );
	foreach my $y ( 0..28 ) {
		foreach my $x ( 0..73 ) {
			my $ci = $img->getPixel( $x, $y );
			my ($r, $g, $b ) = $img->rgb( $ci );
			$r = (256 - $r) / 256;
			$g = (256 - $g) / 256;
			$b = (256 - $b) / 256;
			my $c = 256 - 256 * (($r * $g * $b) ** (1/3));

			my $gray = $trimg->colorResolve( $c, $c, $c );
	
			$trimg->setPixel( $x, $y, $gray );
		}
	}
	
	my @n;
	push @n, charat( $img, $trimg, 9 );
	push @n, charat( $img, $trimg, 28 );
	push @n, charat( $img, $trimg, 42 );
	push @n, charat( $img, $trimg, 58 );
	foreach (@n) {
		return undef unless defined $_;
	}

	return join "", @n;
}

# }}}
package Get::OdSiebie; # {{{

BEGIN {
	our @ISA;
	@ISA = qw(Get);
}

my $oscookie = 0;
sub new
{
	my $proto = shift;
	my $class = ref $proto || $proto;
	my $url = shift;

	++$oscookie;
	my $cookie = ".cookie.os.$oscookie.txt";
	unlink $cookie if -e $cookie;

	Get::makenew( "OS", $class, $url, slots => 16, cookies => $cookie );
}

sub stage1
{
	my $self = shift;

	$self->print("starting...");
	delete $self->{referer};

	( my $url = $self->{url} ) =~ s#/pokaz/#/pobierz/#;

	$self->curl( $url, \&stage2 );
}

sub stage2
{
	my ($self, $body, $url) = @_;

	if ( $url =~ m{/(upload|error)\.html} ) {
		return $self->error( "some problem", $body );
	}
	$self->print("downloading");
	$self->{referer} = $url;

	( my $furl = $url ) =~ s#/pobierz/#/download/#;
	$self->{file_url} = $furl;

	$self->download();
}

sub DESTROY
{
	my $self = shift;
	unlink $self->{cookies};
}

$getters{OS} = {
	uri => qr{odsiebie\.com/(?:pokaz|pobierz)/.*?},
	add => sub { Get::OdSiebie->new( @_ ) },
};

# }}}
package Get::MegaUpload; # {{{

BEGIN {
	our @ISA;
	@ISA = qw(Get);
}

use URI::Escape;

sub new
{
	my $proto = shift;
	my $class = ref $proto || $proto;
	my $url = shift;

	Get::makenew( "MU", $class, $url );
}

sub stage1
{
	my $self = shift;

	$self->print("starting...");
	delete $self->{referer};
	$self->curl( $self->{url}, \&stage2 );
}

sub stage2
{
	my ($self, $body, $url) = @_;
	$self->print("starting......");
	$self->{referer} = $url;

	if ( $body =~ /The file you are trying to access is temporarily unavailable/
			or $body =~ /Unfortunately, the link you have clicked is not available/
			or $body =~ /This file has expired due to inactivity/ ) {
		return $self->error( "file not found" );
	}
	if ( $body =~ /The file you're trying to download is password protected/ ) {
		return $self->error( "password required" )
			unless exists $self->{opts}->{pass};

		my $pass = uri_escape( $self->{opts}->{pass} );
		my $post = "filepassword=$pass";
		return $self->curl( "", \&stage4, post => $post );
	}
	my %search = (
		captcha_img => qr#<img src="(http://.*/gencap\.php\?[0-9a-f]+\.gif)"#,
		s2icode => qr#<INPUT type="hidden" name="captchacode" value="(.*?)"#,
		s2mevagar => qr#<INPUT type="hidden" name="megavar" value="(.*?)"#,
	);

	foreach my $name ( keys %search ) {
		my $search = $search{$name};
		if ( $body =~ m/$search/ ) {
			$self->{$name} = $1;
		} else {
			return $self->problem( $name, $body )
		}
	}

	$self->curl( $self->{captcha_img}, \&stage3 );
}

sub stage3
{
	my ($self, $body, $url) = @_;
	$self->print("reading captcha");

	my $captcha = Get::MegaUpload::Captcha::resolve( \$body );

	unless ( defined $captcha ) {
		return $self->stage1();
	}

	my $post = "captchacode=$self->{s2icode}&megavar=$self->{s2mevagar}&captcha=$captcha";

	$self->curl( "", \&stage4, post => $post );
}

sub stage4
{
	my ($self, $body, $url) = @_;
	$self->print("starting.........");
	$self->{referer} = $url;

	if ( $body =~ /id="captchaform"/ ) {
		return $self->stage1( @_ );
	}
	if ( $body =~ /The file you're trying to download is password protected/ ) {
		return $self->error( "invalid password" );
	}

	my $wait;
	if ( $body =~ /count=([0-9]+);/ ) {
		$wait = $1;
	}
	if ( $body =~ /<a href="(.*?)".*IMG SRC=".*?but_dnld_regular.gif/ ) {
		$self->{file_url} = $1;
	} else {
		return $self->problem( "link", $body )
	}

	$self->wait( $wait, \&stage5, "starting in" );
}

sub stage5
{
	my $self = shift;
	$self->print("downloading");

	$self->download();
}

$getters{MU} = {
	uri => qr{(?:www\.)?mega(upload|porn)\.com/\?d=.*?},
	add => sub { Get::MegaUpload->new( @_ ) },
};

# }}}
package Get::MegaUpload::Captcha; # {{{

my %size = (
	A => 28, B => 22, C => 21, D => 27, E => 16,
	F => 16, G => 26, H => 26, K => 20, M => 38,
	N => 28, P => 21, Q => 30, R => 22, S => 18,
	T => 19, U => 26, V => 22, W => 40, X => 23,
	Y => 18, Z => 18
);

my @db;

sub read_db()
{
	my $dbf = new Image::Magick;
	$dbf->Read( $main::data_path . "/mu_font_db.png" );
	foreach my $pos ( 0..3 ) {
		my @list = sort keys %size;
		@list = (1..9) if $pos == 3;

		my $height = 32;
		my $width = 40;
		my $left = $width * $pos;
		$width = 22 if $pos == 3;
		my $top = 0;
	
		my %db;
		foreach my $char ( @list ) {
			my $db = $dbf->Clone();
			$db->Crop( width => $width, height => $height, x => $left, y => $top );
			$db{$char} = $db;
			$top += 32;
		}
		push @db, \%db;
	}
}

sub get_char
{
	my ($src, $db, $width, $x) = @_;

	my $img = $src->Clone();
	$img->Crop( width => $width, height => 32, x => $x, y => 0 );
	$img->Extent( width => $width, height => 32, x => 0, y => 0 );

	my $min = 1;
	my $min_char = undef;
	foreach my $n ( keys %$db ) {
		my $x = $img->Compare( image => $db->{$n} );
		my ($e, $em) = $img->Get( 'error', 'mean-error' );
		if ( $em < $min ) {
			$min = $em;
			$min_char = $n;
		}
	}
	return $min_char;
}

sub resolve
{
	my $data_ref = shift;

	require Image::Magick;

	read_db() unless @db;

	open IMAGE, '>', '.captcha.gif';
	print IMAGE $$data_ref;
	close IMAGE;

	my $img = new Image::Magick;
	my $x = $img->Read( '.captcha.gif' );
	unlink '.captcha.gif';
	return if length $x;

	my ($width, $height) = $img->Get( 'columns', 'rows' );

	my $bg = new Image::Magick;
	$bg->Set( size => $width."x32" );
	$bg->Read( "xc:white" );
	$bg->Composite( image => $img );

	my @cap;
	push @cap, get_char( $bg, $db[0], 40, 0 );
	push @cap, get_char( $bg, $db[1], 40, $size{$cap[0]} - 6 );
	push @cap, get_char( $bg, $db[2], 40, $width - 56 );
	push @cap, get_char( $bg, $db[3], 22, $width - 22 );

	return join "", @cap;
}

# }}}
package Get::UploadedTo; # {{{

BEGIN {
	our @ISA;
	@ISA = qw(Get);
}

sub new
{
	my $proto = shift;
	my $class = ref $proto || $proto;
	my $url = shift;

	Get::makenew( "UT", $class, $url );
}

sub stage1
{
	my $self = shift;

	$self->print("starting...");
	delete $self->{referer};
	$self->curl( $self->{url}, \&stage2 );
}

sub stage2
{
	my ($self, $body, $url) = @_;
	$self->print("starting......");
	$self->{referer} = $url;

	if ( $body =~ /Or wait (\d+) minutes/ ) {
		return $self->wait( $1 * 60, \&stage1, "free limit reached, waiting" );
	}
	if ( $url =~ m#/\?view=# ) {
		if ( $url =~ /fileremoved/) {
			return $self->error( "file not found" );
		}
		return $self->error( "unknown error", $body );
	}
	($self->{file_url}) = ($body =~ m#<form name="download_form" method="post" action="(.*)">#);
	my ($wait) = ($body =~ m#var secs = (\d+); // Wartezeit#);

	$self->wait( $wait, \&stage3, "starting in" );
}

sub stage3
{
	my $self = shift;
	$self->print("downloading");

	$self->download( post => "download_submit=Download");
}

$getters{UT} = {
	uri => qr{(uploaded|ul)\.to/.*?},
	add => sub { Get::UploadedTo->new( @_ ) },
};

# }}}
package Get::HotFile; # {{{

BEGIN {
	our @ISA;
	@ISA = qw(Get);
}

sub new
{
	my $proto = shift;
	my $class = ref $proto || $proto;
	my $url = shift;
	Get::makenew( "HF", $class, $url );
}

sub stage1
{
	my $self = shift;
	delete $self->{referer};

	$self->print("starting...");
	$self->curl( $self->{url}, \&stage2 );
}

sub stage2
{
	my ($self, $body, $url) = @_;
	$self->print("starting......");
	$self->{referer} = $url;

	unless ( length $body ) {
		return $self->error( "file not found" );
	}
	if ( $body =~ /You are currently downloading/ ) {
		return $self->multi();
	} elsif ( $body =~ /This file is either removed/ ) {
		return $self->error( "file not found" );
	} elsif ( $body =~ /starthtimer[\s\S]*?timerend=d\.getTime\(\)\+(\d+);/m and $1 > 0 ) {
		return $self->wait( 1 + int ( $1 / 1000 ), \&stage1, "free limit reached, waiting" );
	}
	my $wait;
	if ( $body =~ /starttimer[\s\S]*?timerend=d\.getTime\(\)\+(\d+);/m ) {
		$wait = $1 / 1000;
	} else {
		return $self->problem( "starttimer", $body );
	}
	my @post;
	my $link;
	my @body = split /\n+/, $body;
	while ( $_ = shift @body ) {
		if ( not defined $link ) {
			$link = $1 if /<form style=".*?" action="(.*?)" method=post name=f>/m;
		} elsif ( /<input type=hidden name=(.*?) value=(.*?)>/ ) {
			push @post, "$1=$2";
		} elsif ( m#</form># ) {
			last;
		}
	}
	unless ( defined $link ) {
		return $self->problem( "link", $body );
	}
	$self->{action} = $link;
	$self->{post} = join "&", @post;

	$self->wait( $wait, \&stage3, "starting download in" );
}

sub stage3
{
	my $self = shift;
	$self->print("starting.........");

	$self->curl( $self->{action}, \&stage4, post => $self->{post} );
}

sub stage4
{
	my ($self, $body, $url) = @_;
	$self->print("downloading");
	if ( $body =~ m#<a href="(.*?)">Click here to download</a># ) {
		$self->{file_url} = $1;
	}

	$self->download();
}

$getters{HF} = {
	uri => qr{hotfile\.com/.*?},
	add => sub { Get::HotFile->new( @_ ) },
};

# }}}
package Get::FileFactory; # {{{

BEGIN {
	our @ISA;
	@ISA = qw(Get);
}

sub new
{
	my $proto = shift;
	my $class = ref $proto || $proto;
	my $url = shift;
	Get::makenew( "FF", $class, $url );
}

sub stage1
{
	my $self = shift;
	delete $self->{referer};

	$self->print("starting...");
	$self->curl( $self->{url}, \&stage2 );
}

sub stage2
{
	my ($self, $body, $url) = @_;
	$self->print("starting......");
	$self->{referer} = $url;

	my $link;
	if ( $body =~ /You are currently downloading/ ) {
		return $self->multi();
	} elsif ( $body =~ /starthtimer[\s\S]*timerend=d\.getTime\(\)\+(\d+);/m and $1 > 0 ) {
		return $self->wait( 1 + int ( $1 / 1000 ), \&stage1, "free limit reached, waiting" );
	} elsif ( $body =~ m#<form action="(.*)" method="post">\s*<input type="submit" value="Free#m ) {
		$link = $1;
	} elsif ( $body =~ /File Not Found/ ) {
		return $self->error( "file not found" );
	} else {
		return $self->problem( "link", $body );
	}

	$self->curl( $link, \&stage3, post => "freeBtn=Free%20Download" );
}

sub stage3
{
	my ($self, $body, $url) = @_;
	$self->{referer} = $url;
	$self->print("starting.........");
	if ( $body =~ m#<a href="(.*?)">Click here to begin your download</a># ) {
		$self->{file_url} = $1;
	} else {
		return $self->problem( "file url", $body );
	}
	my $wait;
	if ( $body =~ m#<p id="countdown">(\d+)</p># ) {
		$wait = 0+$1;
	} else {
		return $self->problem( "countdown", $body );
	}
	
	$self->wait( $wait, \&stage4, "starting in" );
}

sub stage4
{
	my $self = shift;
	$self->print("downloading");
	$self->{file_html} = \&stage5;

	$self->download();
}

sub stage5
{
	my ($self, $body, $url) = @_;
	# file turned out to be html, meens we need to wait
	if ( $body =~ /You are currently downloading too many files at once/ ) {
		return $self->multi();
	} elsif ( $body =~ /Please wait (\d+) minutes to download more files/ ) {
		return $self->wait( $1 * 60 - 30, \&stage1, "free limit reached, waiting" );
	} elsif ( $body =~ /Please wait (\d+) seconds to download more files/ ) {
		return $self->wait( $1, \&stage1, "free limit reached, waiting" );
	}
	return $self->problem( undef, $body );
}

$getters{FF} = {
	uri => qr{(www.)?filefactory\.com/.*?},
	add => sub { Get::FileFactory->new( @_ ) },
};

# }}}
package Get::DepositFiles; # {{{

BEGIN {
	our @ISA;
	@ISA = qw(Get);
}

sub new
{
	my $proto = shift;
	my $class = ref $proto || $proto;
	my $url = shift;
	Get::makenew( "DF", $class, $url );
}

sub stage1
{
	my $self = shift;
	delete $self->{referer};

	$self->print("starting...");
	$self->curl( $self->{url}, \&stage2 );
}

sub stage2
{
	my ($self, $body, $url) = @_;
	$self->print("starting......");
	$self->{referer} = $url;

	my $link;
	if ( $body =~ /Such file does not exist / ) {
		return $self->error( "file not found" );
	} elsif ( $body =~ m#<form action="(.*?)" method="post"># ) {
		$link = $1;
	} elsif ( $body =~ /We are sorry, but all downloading slots for your country are busy/ ) {
		return $self->wait( 5 * 60, \&stage1, "servers overloaded, waiting" );
	} else {
		return $self->problem( "link", $body );
	}

	$self->curl( $link, \&stage3, post => "gateway_result=1" );
}

sub stage3
{
	my ($self, $body, $url) = @_;
	$self->{referer} = $url;
	$self->print("starting.........");

	if ( $body =~ m#<form action="(.*?)" method="get" onSubmit="download_started# ) {
		$self->{file_url} = $1;
	} elsif ( $body =~ m#<span class="html_download_api-limit_interval">(\d+)</span># ) {
		return $self->wait( $1, \&stage1, "free limit reached, waiting" );
	} elsif ( $body =~ m#<span class="html_download_api-limit_parallel"># ) {
		return $self->multi();
	} else {
		return $self->problem( "file url", $body );
	}
	
	$self->wait( 60, \&stage4, "starting download in" );
}

sub stage4
{
	my $self = shift;
	$self->print("downloading");

	$self->download();
}

$getters{DF} = {
	uri => qr{(www\.)?depositfiles\.com/.*?},
	add => sub { Get::DepositFiles->new( @_ ) },
};

# }}}
package Get::TurboUpload; # {{{

BEGIN {
	our @ISA;
	@ISA = qw(Get);
}

sub new
{
	my $proto = shift;
	my $class = ref $proto || $proto;
	my $url = shift;
	Get::makenew( "TU", $class, $url );
}

sub stage1
{
	my $self = shift;
	delete $self->{referer};

	$self->print("starting...");
	$self->curl( $self->{url}, \&stage2 );
}

sub stage2
{
	my ($self, $body, $url) = @_;
	$self->print("starting......");
	$self->{referer} = $url;

	my @body = split /\n+/, $body;
	do {
		return $self->error( "no form" ) unless @body;
		$_ = shift @body;
	} until ( /<Form method="POST" action=''>/ );
	my %opts;
	for (;;) {
		return $self->error( "no form" ) unless @body;
		$_ = shift @body;
		/<input type="hidden" name="(.*?)" value="(.*?)">/ or last;
		$opts{$1} = $2;
	}

	$opts{method_free} = "Free%20Download";
	my $post = join "&", map { "$_=$opts{$_}" } keys %opts;

	$self->curl( $url, \&stage3, post => $post );
}

sub stage3
{
	my ($self, $body, $url) = @_;
	$self->{referer} = $url;
	$self->print("starting.........");

	$self->{file_url} = $url;

	my $wait;
	if ( $body =~ /You have to wait (\d+) hours?/ ) {
		$wait = 600;
	} elsif ( $body =~ /You have to wait (\d+) minutes?(, (\d+) second)?/ ) {
		$wait = 60 * $1 + ( defined $2 ? $3 : 0 );
		$wait = 600 if $wait > 600;
	} elsif ( $body =~ /You have to wait (\d+) seconds?/ ) {
		$wait = $1;
	}
	if ( defined $wait ) {
		return $self->wait( $wait, \&stage1, "free limit reached, waiting" );
	}

	$body =~ m#Enter code below:[\S\s]*?<div.*?>(.*?)</div>#o;

	my %c = map /<span.*?padding-left:\s*?(\d+)px;.*?>(\d)</g, $1;
	my @c = map { $c{$_} } sort { $a <=> $b } keys %c;
	my $captcha = join "", @c;

	my @body = split /\n+/, $body;
	do {
		$_ = shift @body;
	} until ( /<Form name="F1" method="POST" action=""/ );
	my %opts;
	for (;;) {
		$_ = shift @body;
		/<input type="hidden" name="(.*?)" value="(.*?)">/ or last;
		$opts{$1} = $2;
	}
	$opts{code} = $captcha;
	$opts{btn_download} = "Download%20File";

	$self->{dl_post} = join "&", map { "$_=$opts{$_}" } keys %opts;

	$self->wait( 60, \&stage4, "starting download in" );
}

sub stage4
{
	my $self = shift;
	$self->print("downloading");

	$self->download( post => $self->{dl_post} );
}

$getters{TU} = {
	uri => qr{(www\.)?turboupload\.com/.*?},
	add => sub { Get::TurboUpload->new( @_ ) },
};

# }}}
package Get::StorageTo; # {{{

BEGIN {
	our @ISA;
	@ISA = qw(Get);
}

sub new
{
	my $proto = shift;
	my $class = ref $proto || $proto;
	my $url = shift;
	Get::makenew( "ST", $class, $url );
}

sub stage1
{
	my $self = shift;
	delete $self->{referer};

	$self->print("starting...");
	$self->curl( $self->{url}, \&stage2 );
}

sub stage2
{
	my ($self, $body, $url) = @_;
	$self->print("starting......");
	$self->{referer} = $url;

	my $code;
	if ( $body =~ /onclick='javascript:startcountdown\("(.*?)", "(.*?)"\);'/ ) {
		$code = $2;
	}

	$self->curl( "/getlink/$code/", \&stage3 );
}

sub stage3
{
	my ($self, $body, $url) = @_;
	$self->print("starting.........");

	$_ = $body;
	s/^.*?{\s+//;
	s/\s+}.*?$//;

	if ( /'link'\s*:\s*'(.*?)'/ ) {
		$self->{file_url} = $1;
	} elsif ( /'countdown'\s*:\s*(\d+)/ ) {
		my $wait = $1;
		$wait = 600 if $wait > 600;
		return $self->wait( $1, \&stage1, "free limit reached, waiting" );
	}

	$self->wait( 60, \&stage4, "starting download in" );
}

sub stage4
{
	my $self = shift;
	$self->print("downloading");

	$self->download();
}

$getters{ST} = {
	uri => qr{(www\.)?storage\.to/.*?},
	add => sub { Get::StorageTo->new( @_ ) },
};

# }}}
package Link::RaidRush; # {{{

BEGIN {
	our @ISA;
	@ISA = qw(Get);
}

sub new
{
	my $proto = shift;
	my $class = ref $proto || $proto;
	my $url = shift;
	Get::makenew( "LINK: save.raidrush.ws", $class, $url, slots => 8 );
}

sub stage1
{
	my $self = shift;
	delete $self->{referer};

	$self->print("starting...");
	$self->curl( $self->{url}, \&stage2 );
}

sub stage2
{
	my ($self, $body, $url) = @_;
	$self->print("starting......");
	$self->{referer} = $url;

	my @list;
	foreach ( split /\n+/, $body ) {
		if ( /onclick="get\('(.*?)','FREE','(.*?)'\)/ ) {
			push @list, "/404.php.php?id=$1&key=$2";
		}
	}
	$self->{list} = [@list];
	$self->{list_done} = [];

	$self->curl( shift @{$self->{list}}, \&stage3 );
}

sub stage3
{
	my ($self, $body, $url) = @_;
	$self->{referer} = $url;

	push @{$self->{list_done}}, "http://" . $body;
	$self->print( scalar @{$self->{list_done}});

	if ( scalar @{$self->{list}} ) {
		return $self->curl( shift @{$self->{list}}, \&stage3 );
	}

	$self->print( "Links: " . scalar @{$self->{list_done}} );

	return $self->finish_links( @{$self->{list_done}} );
}

$getters{"save.raidrush.ws"} = {
	uri => qr{save\.raidrush\.ws/.*?},
	add => sub { Link::RaidRush->new( @_ ) },
};

# }}}
package main; # {{{

my $get_list = 'get.list';
while ( my $arg = shift @ARGV ) {
	if ( $arg eq '-i' ) {
		Get::add_outaddr( shift @ARGV || die "argument missing" );
	} else {
		$get_list = $arg;
	}
}
print "Using '$get_list' file list\n";
die "Can't read the list\n" unless -r $get_list;
print "\n";

my $listmtime = 0;
sub readlist
{
	return unless -r $get_list;
	my $mtime = (stat _)[9];
	return unless $checklist or $mtime != $listmtime;

	my @newlist;
	my @updated;
	open my $list, '<', $get_list;
	while ( my $line = <$list> ) {
		if ( $line =~ /^\s*(#.*)?$/ ) {
			push @newlist, $line;
			next;
		} elsif ( $line =~ /^__END__\s*$/ ) {
			push @newlist, $line;
			push @newlist, <$list>;
			last;
		}
		my $uri = undef;
		my $getter = undef;
		if ( $line =~ m{^\s*(http://)?(.*?)\s*$} ) {
			my $proto = $1 || "http://";
			$uri = $2;
			($getter) = grep { $uri =~ m/^$getters{$_}->{uri}$/ } keys %getters;
			$uri = $proto.$uri;
		}

		if ( $getter ) {
			( my $only_uri = $uri ) =~ s/\s+.*//;
			if ( exists $gotlist{$only_uri} ) {
				my $status = $gotlist{$only_uri};
				if ( ref $status and ref $status eq "ARRAY" ) {
					chomp $line;
					push @newlist, "# Link $line:\n"
						. (join "\n", @$status) . "\n";
					$checklist = 2;
				} else {
					push @newlist, "# $status:\n# " . $line;
				}
				push @updated, $only_uri;
			} else {
				push @newlist, $uri . "\n";
				&{$getters{ $getter }->{add}}( $uri );
			}
			next;
		}
		push @newlist, "# invalid url: $line";
	}
	close $list;
	unless ( -e ".${get_list}.swp" ) {
		open my $newlist, '>', $get_list . ".tmp";
		print $newlist @newlist;
		close $newlist || die "\nCannot update $get_list file: $!\n";
		unlink $get_list;
		rename $get_list . ".tmp", $get_list;
		delete $gotlist{ $_ } foreach @updated;
	}

	$checklist = $checklist == 2 ? 1 : 0;
	$listmtime = (stat $get_list)[9];
}

my $lasttime = 0;
for (;;) {
	if ( scalar keys %running ) {
		foreach ( 0..50 ) {
			Curl::perform();
			Time::HiRes::sleep(0.005);
		}
	} else {
			Time::HiRes::sleep(0.250);
	}
	Curl::print_status();

	my $time = time;
	next if $time == $lasttime;
	$lasttime = $time;

	Wait::perform();
	readlist();
}

sub s2string($)
{
	my $s = shift;
	my $hours = int( $s / 3600 );
	my $minutes = int( ( $s % 3600 ) / 60 );
	my $seconds = $s % 60;

	return sprintf '%d:%.2d:%.2d', $hours, $minutes, $seconds
		if $hours;
	return sprintf '%d:%.2d', $minutes, $seconds;
}

sub bignum($)
{
	local $_ = shift;
	s/(..?.?)(?=(...)+$)/$1_/g;
	return $_;
}

# }}}
# vim:ts=4:sw=4:fdm=marker
