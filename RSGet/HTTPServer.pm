package RSGet::HTTPServer;

use strict;
use warnings;
use IO::Socket;
use RSGet::Tools;
use RSGet::HTTPRequest;

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

	for ( my $i = 0; $i < 5; $i++ ) {
		my $client = $socket->accept() or last;
		last unless request( $client );
	}
}

sub request
{
	my $client = shift;
	my $request;
	my @headers;
	my $post = "";
	my $OK = 0;
	eval {
		local $SIG{ALRM} = sub { die "HTTP: Frozen !\n"; };
		alarm 2;
		$request = <$client>;

		my $len = 0;
		while ( $_ = <$client> ) {
			if ( /^\s*$/ ) {
				$OK = 1;
				last;
			}
			push @headers, $_;
			$len = $1 if /^Content-Length:\s*(\d+)/i;
		}

		$client->read( $post, $len ) if $len;
		$OK++;
	};
	alarm 0;
	if ( $@ ) {
		warn "HTTP error: $@\n" unless $@ eq "HTTP: Frozen !\n";
		close $client;
		return undef;
	}
	unless ( $OK == 2 ) {
		warn "Some HTTP problem\n";
		close $client;
		return undef;
	}
	
	my( $method, $file, $ignore ) = split /\s+/, $request;
	$file =~ s#^/+##;

	my %post;
	if ( uc $method eq "POST" and length $post ) {
		foreach ( split /&/, $post ) {
			s/^(.*?)=//;
			my $key = $1;
			tr/+/ /;
			s/%(..)/chr hex $1/eg;
			$post{ $key } = $_;
		}
	} elsif ( $file =~ s/\?(.*)// ) {
		my $get = $1;
		%post = map /^(.*?)=(.*)/, split /;+/, $get;
	}
	my $print;
	if ( my $func = $RSGet::HTTPRequest::handlers{$file} ) {
		$print = "HTTP/1.1 200 OK\r\n";
		my $headers = { Content_Type => "text/xml; charset=utf-8" };
		my $data = &$func( $file, \%post, $headers );

		$headers->{Content_Length} ||= length $data;
		while ( my ( $k, $v ) = each %$headers ) {
			( my $key = $k ) =~ s/_/-/g;
			$print .= "$key: $v\r\n";
		}
		$print .= "\r\n";

		$print .= $data;
	} else {
		$print = "HTTP/1.1 404 Not found\r\n";
		$print .= "\r\n";
	}

	my $kid = fork();
	unless ( $kid ) {
		# XXX: this is stupid, but I don't know what
		# else to do if $client is closed already
		print $client $print;
		close $client;

		# don't exit if we didn't actually fork
		exit 0 if defined $kid;
	};

	close $client;
	return 1;
}

1;

# vim: ts=4:sw=4
