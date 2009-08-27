#!/usr/bin/perl
#
# 2009 (c) Przemysław Iskra <sparky@pld-linux.org>
# Use/modify/distribute under GPL v2 or newer.
#
use strict;
use warnings;

our $data_path = $ENV{PWD};

use Time::HiRes;

unshift @INC, $data_path;
use RSGet::Tools;
use RSGet::Processor;
use RSGet::Curl;
use RSGet::Line;
use RSGet::FileList;
use RSGet::Get;
use RSGet::Dispatch;
$SIG{CHLD} = "IGNORE";

# read options
my $http = undef;
while ( my $arg = shift @ARGV ) {
	if ( $arg eq '-i' ) {
		RSGet::Dispatch::add_interface( shift @ARGV || die "argument missing" );
	} elsif ( $arg eq '-s' ) {
		require RSGet::MicroHTTP;
		$http = new RSGet::MicroHTTP( shift @ARGV || die "port missing" );
		p "HTTP server " . ( $http ? "started" : "failed" ) ;
	} elsif ( $arg eq '-o' ) {
		my $data = shift @ARGV;
		my $o = eval "{ $data }";
		if ( $o and ref $o ) {
			hadd \%settings, %$o;
		}
	} else {
		$RSGet::FileList::file = $arg;
	}
}
p "Using '$RSGet::FileList::file' file list\n";
die "Can't read the list\n" unless -r $RSGet::FileList::file;

if ( keys %settings ) {
	p "Settings:";
	hprint \%settings;
}
new RSGet::Line();

# add getters
foreach my $type ( qw(Get Link) ) {
	foreach ( sort glob "$data_path/$type/*" ) {
		next if /~$/;
		next if m{/\.[^/]*$};
		( my $file = $_ ) =~ s#.*/##;
		my ( $pkg, $getter ) = RSGet::Processor::read_file( $type, $_ );
		my $msg = "${type}/$file: failed";
		if ( $pkg and $getter ) {
			$getters{ $pkg } = $getter;
			$msg = "$pkg: added\n";
		}
		new RSGet::Line( "INIT: ", $msg );
	}
}
new RSGet::Line();
new RSGet::Line( "rsget.pl started successfully" );
new RSGet::Line();
RSGet::Line::update();

# main loop
my $lasttime = 0;
for (;;) {
	if ( RSGet::Curl::need_run() ) {
		RSGet::Curl::maybe_abort();
		foreach ( 0..4 ) {
			RSGet::Curl::perform();
			Time::HiRes::sleep(0.050);
		}
	} else {
			Time::HiRes::sleep(0.250);
	}
	RSGet::Curl::update_status();
	RSGet::Line::update();
	$http->perform() if $http;

	my $time = time;
	next if $time == $lasttime;
	$lasttime = $time;

	RSGet::Get::wait_update();

	my $getlist = RSGet::FileList::readlist();
	RSGet::Dispatch::process( $getlist ) if $getlist;
}


# vim:ts=4:sw=4
