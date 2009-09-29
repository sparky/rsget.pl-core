#!/usr/bin/perl
#
# 2009 (c) Przemysław Iskra <sparky@pld-linux.org>
# Use/modify/distribute under GPL v2 or newer.
#
use strict;
use warnings;

our $data_path;
our $configdir;
BEGIN {
	$data_path = $ENV{PWD};
	unshift @INC, $data_path;

	my $cd = "$ENV{HOME}/.rsget.pl";
	if ( -r $cd and -d $cd ) {
		$configdir = $cd;
		unshift @INC, $configdir;
	} else {
		$configdir = $data_path;
	}
}

use Time::HiRes;
use RSGet::Line;
use RSGet::Tools;
use RSGet::AutoUpdate;
use RSGet::Processor;
use RSGet::Curl;
use RSGet::FileList;
use RSGet::Get;
use RSGet::Wait;
use RSGet::Captcha;
use RSGet::Dispatch;
use RSGet::ListManager;
$SIG{CHLD} = "IGNORE";

set_rev qq$Id$;

%settings = (
	auto_update => undef,
	svn_uri => 'http://svn.pld-linux.org/svn/toys/rsget.pl',
	backup => "copy,move",
	backup_suf => undef,
	logging => 0,
	list_lock => '.${file}.swp', # vim-like swap file
	http_port => undef,
	list_file => undef,
	errorlog => 0,
	outdir => '.',
	workdir => '.',
);

my @save_ARGV = @ARGV;

sub set
{
	my ( $key, $val ) = @_;
	if ( exists $settings{ $key } ) {
		$settings{ $key } = $val;
	} else {
		warn "Option '$key' does not exist\n";
	}
}

if ( -r "$configdir/config" ) {
	open F_IN, "<", "$configdir/config";
	while ( <F_IN> ) {
		next if /^\s*(?:#.*)?$/;
		chomp;
		if ( s/^\s*([a-z_]+)\s*=\s*// ) {
			set( $1, $_ );
			next;
		}
		warn "Incorrect config line: $_\n";
	}
	close F_IN;
}

# read options
while ( my $arg = shift @ARGV ) {
	if ( $arg eq '-h' ) {
		die "No help here, sorrt. For real help read documentation.\n";
	} elsif ( $arg eq '-i' ) {
		my $ifs = shift @ARGV || die "argument missing";
		RSGet::Dispatch::add_interface( $ifs );
	} elsif ( $arg eq '-p' ) {
		set( "http_port", shift @ARGV || die "port missing" );
	} elsif ( $arg =~ s/^--(.*?)=// ) {
		set( $1, $arg );
	} elsif ( $arg =~ s/^--(.*)// ) {
		my $key = $1;
		my $var = shift @ARGV;
		die "argument missing" unless defined $var;
		set( $key, $var );
	} else {
		set( "list_file", $arg );
	}
}

if ( $settings{auto_update} ) {
	if ( RSGet::AutoUpdate::update() ) {
		warn "Update successfull, restarting\n";
		exec $0, @save_ARGV, "--auto_update", 0;
	}
}
if ( keys %settings ) {
	p "Settings:";
	hprint \%settings;
}

RSGet::FileList::set_file( $settings{list_file} );

my $http = undef;
if ( $settings{http_port} ) {
	require RSGet::HTTPServer;
	$http = new RSGet::HTTPServer( $settings{http_port} );
	p "HTTP server " . ( $http ? "started on port $settings{http_port}" : "failed" ) ;
}

if ( $settings{interfaces} ) {
	RSGet::Dispatch::add_interface( $settings{interfaces} );
}

new RSGet::Line();

# add getters
foreach my $path ( ( $configdir, $data_path ) ) {
  foreach my $type ( qw(Get Link) ) {
	foreach ( sort glob "$path/$type/*" ) {
		next if /~$/;
		next if m{/\.[^/]*$};
		( my $file = $_ ) =~ s#.*/##;
		next if exists $getters{ $type . "::" . $file };
		my ( $pkg, $getter ) = RSGet::Processor::read_file( $type, $_ );
		my $msg = "${type}/$file: failed";
		if ( $pkg and $getter ) {
			$getters{ $pkg } = $getter;
			$msg = "$pkg: added\n";
			new RSGet::Line( "INIT: ", $msg );
		} else {
			warn "$msg\n";
		}
	}
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

	RSGet::Wait::wait_update();
	RSGet::Captcha::captcha_update();

	my $getlist = RSGet::FileList::readlist();
	if ( $getlist ) {
		my $allchk = RSGet::Dispatch::process( $getlist );
		RSGet::ListManager::autoadd( $getlist );
	}
}


# vim:ts=4:sw=4
