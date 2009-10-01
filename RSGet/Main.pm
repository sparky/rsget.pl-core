package RSGet::Main;
#
# 2009 (c) Przemysław Iskra <sparky@pld-linux.org>
# Use/modify/distribute under GPL v2 or newer.
#
use strict;
use warnings;
use RSGet::AutoUpdate;
use RSGet::Captcha;
use RSGet::Curl;
use RSGet::Dispatch;
use RSGet::FileList;
use RSGet::Get;
use RSGet::Line;
use RSGet::ListManager;
use RSGet::Processor;
use RSGet::Tools;
use RSGet::Wait;
use Time::HiRes;
set_rev qq$Id$;

def_settings(
	interfaces => [ "Specify output interfaces or IP addresses", undef, qr/\d+/ ],
	http_port => [ "Start HTTP server on specified port.", 0, qr/\d+/ ],
	verbose => [ "Verbosity level", 0, qr/\d+/ ],
);

my $http = undef;
sub init
{
	my $help = shift;
	my $main_rev = shift;
	my $argv = shift;
	my $ifs = shift;
	set_rev $main_rev;

	print_help() if $help;
	check_settings();

	$SIG{CHLD} = "IGNORE";
	maybe_update( $argv );
	RSGet::Line::init();
	print_settings() if setting( "verbose" ) >= 1;
	RSGet::FileList::set_file();
	maybe_start_http();
	set_interfaces( $ifs );

	new RSGet::Line();

	find_getters();

	new RSGet::Line();
	new RSGet::Line( "rsget.pl started successfully" );
	new RSGet::Line();
	RSGet::Line::update();

	loop();
}

sub print_help
{
	require Term::Size;
	my ( $columns, $rows ) = Term::Size::chars;
	warn "No help yet\n";

	exit 0;
}

sub maybe_update
{
	my $argv = shift;
	if ( setting( "use_svn" ) eq "update" ) {
		if ( RSGet::AutoUpdate::update() ) {
			warn "Update successful, restarting\n";
			exec $0, @$argv, "--use_svn", "yes";
		}
	}
}

sub check_settings
{
	warn "Unable to check settings\n";
}

sub print_settings
{
	p "Settings:";
	foreach my $s ( sort keys %main::settings ) {
		p "  $s => " . setting( $s );
	}
}

sub maybe_start_http
{
	my $port = setting( "http_port" );
	return unless $port;

	require RSGet::HTTPServer;
	$http = new RSGet::HTTPServer( setting("http_port") );
	if ( $http ) {
		p "HTTP server started on port $port";
	} else {
		warn "HTTP server failed (port $port)\n";
	}
}

sub set_interfaces
{
	my $ifs = shift;
	my $if = setting( "interfaces" );
	RSGet::Dispatch::add_interface( $if ) if $if;
	foreach my $if ( @$ifs ) {
		RSGet::Dispatch::add_interface( $if );
	}
}

sub find_getters
{
	my @paths = ( $main::install_path );
	if ( setting( "use_svn" ) eq "yes" ) {
		unshift @paths, $main::local_path;
	}
	foreach my $path ( @paths ) {
		foreach my $type ( qw(Get Link) ) {
			my $dir = "$path/$type";
			next unless -d $dir;
			foreach ( sort glob "$path/$type/*" ) {
				add_getter( $type, $_ );
			}
		}
	}
}

sub add_getter
{
	my $type = shift;
	local $_ = shift;
	return if /~$/;
	return if m{/\.[^/]*$};
	( my $file = $_ ) =~ s#.*/##;
	return if exists $getters{ $type . "::" . $file };
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

sub loop
{
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
}

1;
# vim:ts=4:sw=4
