#!/usr/bin/perl
#
# 2009 (c) Przemysław Iskra <sparky@pld-linux.org>
# Use/modify/distribute under GPL v2 or newer.
#
use strict;
use warnings;

our $data_path;
BEGIN {
	$data_path = $ENV{PWD};
	unshift @INC, $data_path;
}

use Time::HiRes;
use RSGet::Line;
use RSGet::Tools;
use RSGet::Processor;
use RSGet::Curl;
use RSGet::FileList;
use RSGet::Get;
use RSGet::Dispatch;
use RSGet::ListManager;
$SIG{CHLD} = "IGNORE";

%settings = (
	backup => "copy,move",
	# backup_suf => "~",
	logging => 0,
	list_lock => '.${file}.swp', # vim-like swap file
	errorlog => 0,
);

# read options
my $http = undef;
my $flist = 'get.list';
while ( my $arg = shift @ARGV ) {
	if ( $arg eq '-i' ) {
		my $ifs = shift @ARGV || die "argument missing";
		RSGet::Dispatch::add_interface( $ifs );
	} elsif ( $arg eq '-p' ) {
		require RSGet::HTTPServer;
		my $port = shift @ARGV || die "port missing";
		$http = new RSGet::HTTPServer( $port );
		p "HTTP server " . ( $http ? "started on port $port" : "failed" ) ;
	} elsif ( $arg eq '-s' ) {
		my $data = shift @ARGV;
		my $o = eval "{ $data }";
		die "Can't process settings: $@\n" if $@;
		if ( $o and ref $o ) {
			hadd \%settings, %$o;
		}
	} elsif ( $arg =~ s/^--(.*?)=// ) {
		$settings{ $1 } = $arg;
	} elsif ( $arg =~ s/^--(.*)// ) {
		my $key = $1;
		my $var = shift @ARGV;
		die "argument missing" unless defined $var;
		$settings{ $key } = $var;
	} else {
		$flist = $arg;
	}
}
if ( keys %settings ) {
	p "Settings:";
	hprint \%settings;
}

RSGet::FileList::set_file( $flist );

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
	if ( $getlist ) {
		my $allchk = RSGet::Dispatch::process( $getlist );
		RSGet::ListManager::autoadd( $getlist );
	}
}


# vim:ts=4:sw=4
