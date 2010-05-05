package RSGet::Forks;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Mux;
use Fcntl;
use POSIX ":sys_wait_h";

=head1 RSGet::Forks

This code takes care of our forks.

=cut

my %forks;
my @dead;

# we process all kids
$SIG{CHLD} = \&_sig_chld;

=head2 RSGet::Forks::add( PID, %OPTIONS )

PID is the pid number of that child.

OPTIONS:
 - at_exit - function to execute when fork ends its live
 - from_child - filehandle to read from
 - readline - function to call when one line of text is read
 - read - function to call when something is read
 - check - function to call each ~200ms while the fork is still alive
 - to_child - filehandle to write to (data returned from readline and check
              functions is written there

=cut
sub add
{
	my $pid = shift;
	my %opts = @_;

	return unless $pid;
	die "Pid not numeric." unless $pid =~ /^\d+$/;

	# we want non-blocking read
	if ( my $fh = $opts{from_child} ) {
		my $flags = 0;
		fcntl $fh, F_GETFL, $flags
			or die "Couldn't get flags for fh: $!";
		$flags |= O_NONBLOCK;
		fcntl $fh, F_SETFL, $flags
			or die "Couldn't set flags for fh: $!";

		$opts{_} = "";
	} else {
		delete $opts{_};
	}

	# force int, so it will make a good hash key
	$pid |= 0;

	$forks{ $pid } = \%opts;

	_update_mux();

	return;
}


=head2 _sig_chld

Wait for pid, but don't execute anything just yet.

=cut
sub _sig_chld
{
	# get pids and $? from the dead kids, but don't do finish kids just yet,
	# because we don't want to call at_exit code while doing something else
	while ( 1 ) {
		my $pid = waitpid -1, WNOHANG;
		if ( $pid > 0 ) {
			push @dead, [ $pid, $? ];
		} else {
			last;
		}
	}

	# make sure we'll get called as soon as possible
	RSGet::Mux::add_short( forks => \&_perform );
	RSGet::Mux::remove_long( "forks" );
}

# adjust calls from mux for best performance
sub _update_mux
{
	my $need_long = 0;
	my $need_short = 0;

	foreach my $fork ( values %forks ) {
		$need_long = 1;
		if ( $fork->{check} or $fork->{from_child} ) {
			$need_short = 1;
			last;
		}
	}

	$need_long = 0 if $need_short;

	if ( $need_short ) {
		RSGet::Mux::add_short( forks => \&_perform );
	} else {
		RSGet::Mux::remove_short( "forks" );
	}
	if ( $need_long ) {
		RSGet::Mux::add_long( forks => \&_perform );
	} else {
		RSGet::Mux::remove_long( "forks" );
	}
}

# safely call some function
sub _call
{
	my $fname = shift;
	my $func = shift;
	eval {
		return &$func( @_ );
	};
	if ( $@ ) {
		warn "RSGet::Forks::_call: Function $fname died: $@\n";
	}
	return;
}

# finish kid
sub _dead_kid
{
	my ( $pid, $code ) = @_;
		
	my $fork = $forks{ $pid };
	delete $forks{ $pid };

	unless ( $fork ) {
		warn "RSGet::Forks::_dead_kid pid $pid is not registered\n";
	}

	my $func;
	if ( exists $fork->{_} ) {
		_read( $fork );

		if ( $func = $fork->{readline} ) {
			if ( length $fork->{_} ) {
				while ( $fork->{_} =~ s/^(.*?)\n//s ) {
					_call( readline => $func, $pid, $1 );
				}
				_call( readline => $func, $pid, $fork->{_} )
					if length $fork->{_};
			}
			undef $fork->{_};
		} elsif ( $func = $fork->{read} ) {
			_call( read => $func, $pid, $fork->{_} )
				if length $fork->{_};
			undef $fork->{_};
		}
	}
	if ( $func = $fork->{at_exit} ) {
		_call( at_exit => $func, $pid, $code, $fork->{_} );
	}
}

# read data from kid
sub _read
{
	my $fork = shift;
	my $fh = $fork->{from_child};
	return unless $fh;

	local $_;
	$_ = "";
	while ( read $fh, $_, 1024 ) {
		$fork->{_} .= $_;
	}
	return;
}

# process one kid
sub _process_kid
{
	my $pid = shift;
	my $fork = shift;

	my $func;
	my $fho = $fork->{to_child};
	if ( exists $fork->{_} ) {
		_read( $fork );
		if ( length $fork->{_} ) {
			if ( $func = $fork->{readline} ) {
				while ( $fork->{_} =~ s/^(.*?)\n//s ) {
					my $ret = _call( readline => $func, $pid, $1 );
					print $fho $ret if $fho and defined $ret;
				}
			} elsif ( $func = $fork->{read} ) {
				my $ret = _call( read => $func, $pid, $fork->{_} );
				$fork->{_} = "";
				print $fho $ret if $fho and defined $ret;
			}
		}
	}

	if ( $func = $fork->{check} ) {
		my $ret = _call( check => $func, $pid );
		print $fho $ret if $fho and defined $ret;
	}
	if ( $fho ) {
		$fho->flush();
	}
}

=head2 _perform

Process all children. Called from Mux.

=cut
sub _perform
{
	my $dead = scalar @dead;
	while ( my $kid = shift @dead ) {
		_dead_kid( @$kid );
	}
	_update_mux() if $dead or not %forks;

	foreach my $pid ( keys %forks ) {
		_process_kid( $pid, $forks{ $pid } );
	}
}

1;

# vim: ts=4:sw=4:fdm=marker
