package RSGet::ListAdder;
# This file is an integral part of rsget.pl downloader.
#
# 2009 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Tools;
use RSGet::ListManager;
use RSGet::Dispatch;
set_rev qq$Id$;

sub new
{
	my $class = shift;
	my $self = {};
	$self->{comment} = [];
	$self->{lines} = [];
	$self->{ids} = {};

	bless $self, $class;
	return $self;
}

sub add_links
{
	my $self = shift;
	my $text = shift;

	my $lines = $self->{lines};

	my %list_uris;
	foreach my $mcd ( @$RSGet::ListManager::act_clist ) {
		foreach my $ucd ( @$mcd ) {
			my $uri = $ucd->[0];
			$list_uris{ $uri } = 1;
		}
	}

	my %all_uris;
	foreach my $line ( @$lines ) {
		next unless ref $line;
		my $uris = $line->{uris};
		foreach my $uri ( keys %$uris ) {
			if ( $all_uris{ $uri } ) {
				warn "$uri repeated!";
				delete $uris->{ $uri };
			} else {
				$all_uris{ $uri } = 1;
			}
		}
	}

	my $u = qr/[a-z0-9_-]+/;
	my $tld = qr/[a-z]{2,8}/;
	foreach ( split /\s+/s, $text ) {
		next unless m{^(.*?)(https?://)?((?:$u\.)*$u\.$tld/.+)$};
		my $pre = $1;
		my $proto = $2 || "http://";
		my $uri = $proto . $3;
		if ( $pre ) {
			if ( $pre =~ /%([0-9A-F]{2})$/ ) {
				my $l = chr hex $1;
				$l =~ tr/[](){}<>/][)(}{></;
				$l = sprintf "%.2X", ord $l;
				$uri =~ s/%$l.*//i;
			} elsif ( $pre =~ m{.*([^a-zA-Z0-9_/])$} ) {
				my $l = $1;
				$l =~ tr/[](){}<>/][)(}{></;
				$uri =~ s/\Q$l\E.*//;
			}
		}

		(my $getter, $uri) = RSGet::Dispatch::unigetter( $uri );
		next unless $getter;
		next if exists $all_uris{ $uri };
		$all_uris{ $uri } = 1;
		my $options = {};
		$options->{error} = "Already on the list" if $list_uris{ $uri };
		my $line = { cmd => "ADD", globals => {}, uris => { $uri => [ $getter, $options ] } };
		push @$lines, $line;
	}

	return $self;
}

sub add_comment
{
	my $self = shift;
	my $text = shift;

	my $c = $self->{comment};

	foreach ( split /[\r\n]+/s, $text ) {
		s/^\s*#\s*//;
		push @$c, "# " . $_;
	}

	return $self;
}

sub list_update
{
	my $self = shift;

	my $lines = $self->{lines};
	$self->{select_clone} = 1;
	my @used_save;
	for ( my $i = 0; $i < scalar @$lines; $i++ ) {
		my $line = $lines->[$i];
		next unless ref $line;
		my $globals = $line->{globals};
		my $uris = $line->{uris};
		unless ( keys %$uris ) {
			my $l = splice @$lines, $i, 1;
			redo;
		}

		foreach my $uri ( keys %$uris ) {
			my ( $getter, $options ) = @{ $uris->{ $uri } };
			
			if ( my $save = $RSGet::FileList::save{ $uri } ) {
				push @used_save, $uri;
				$self->{select_clone} = 0;
			
				$line->{cmd} = $save->{cmd} if $save->{cmd};
				hadd $globals, %{$save->{globals}} if $save->{globals};
				hadd $options, %{$save->{options}} if $save->{options};

				if ( my $links = $save->{links} ) {
					my @new;
					foreach my $luri ( @$links ) {
						my ($getter, $uri) = RSGet::Dispatch::unigetter( $luri );
						if ( $getter ) {
							push @new, { cmd => "ADD", globals => {}, uris => { $uri => [ $getter, {} ] } };
						} else {
							push @new, "# unsupported uri: $uri";
						}
					}
					splice @$lines, $i+1, 0, @new;
				}
				if ( my $clones = $save->{clones} ) {
					hadd $uris, %$clones;
					# will check new ones next time
				}
				if ( $save->{delete} ) {
					delete $uris->{ $uri };
					next;
				}
			}

			my $chk = RSGet::Dispatch::check( $uri, $getter, $options );
			$self->{select_clone} = 0 unless $chk;
		}
	}

	foreach my $uri ( @used_save ) {
		delete $RSGet::FileList::save{ $uri };
	}

	return $self;
}

sub find_clones
{
	my $self = shift;

	$self->{select_clone} = 1;
	my $lines = $self->{lines};
	my $own_clist = [ @$RSGet::ListManager::act_clist ];
	my $active = 0;

	my $clone_select;

	foreach my $line ( @$lines ) {
		next unless ref $line;
		my ( $cmd, $globals, $uris ) = @$line{ qw(cmd globals uris) };

		foreach my $uri ( keys %$uris ) {
			my ( $getter, $options ) = @{ $uris->{ $uri } };

			my @cd = RSGet::ListManager::clone_data( { %$options, %$globals } );
			unless ( @cd ) {
				$line->{cmd} = "STOP" if $options->{error};
				next;
			}

			if ( $line->{cmd} ne "ADD" ) {
				$active++;
				push @$own_clist, [ [ $uri, @cd ] ];
				next;
			}

			my @clones = RSGet::ListManager::find_clones( $own_clist, \@cd );
			if ( @clones ) {
				$clone_select = [ $uri, $options, \@clones ];
			} else {
				$line->{cmd} = "GET";
				push @$own_clist, [ [ $uri, @cd ] ];
			}
		}
		last if $clone_select;
	}
	$self->{active} = $active;

	return $clone_select;
}

sub find_uri
{
	my $self = shift;
	my $furi = shift;

	my $lines = $self->{lines};
	foreach my $line ( @$lines ) {
		next unless ref $line;
		my ( $cmd, $globals, $uris ) = @$line{ qw(cmd globals uris) };

		foreach my $uri ( keys %$uris ) {
			if ( $uri eq $furi ) {
				return $line;
			}
		}
	}
	return;
}

sub finish
{
	my $self = shift;

	my @new;
	my $comment = $self->{comment};
	foreach my $line ( @$comment ) {
		push @new, $line . "\n";
	}

	my $added = 0;
	my $lines = $self->{lines};
	foreach my $line ( @$lines ) {
		next unless ref $line;
		my ( $cmd, $globals, $uris ) = @$line{ qw(cmd globals uris) };

		foreach my $uri ( sort keys %$uris ) {
			my $o = $uris->{ $uri }->[1];
			delete $uris->{ $uri } unless $o->{size} or $o->{asize} or $o->{quality};
		}

		next unless keys %$uris;

		$added++;
		{
			my @out = ( "$cmd:", RSGet::FileList::h2a( $globals ) );
			push @new, (join " ", @out) . "\n";
		}
		foreach my $uri ( sort keys %$uris ) {
			my @out = ( $uri, RSGet::FileList::h2a( $uris->{ $uri }->[1] ) );
			push @new, (join " ", '+', @out) . "\n";
		}
	}
	push @RSGet::FileList::added, @new;
	RSGet::FileList::update();

	$self->{msg} = $added == 1 ? "One link added" : "$added links added";
}

sub command
{
	my $self = shift;
	my $exec = shift;

	unless ( $exec =~ s/^(.*?):(.*?)_// ) {
		warn "Invalid command: $exec\n";
		return;
	}
	my $cmd = $1;
	my $grp = $2;

	my $list_ids = $self->{ids};
	my $idgrp = $list_ids->{$grp};
	my $data = $idgrp->{ $exec };
	unless ( $data ) {
		warn "Invalid ID: $cmd, $grp, $exec\n";
		return undef;
	}

	if ( $grp eq "addclone" ) {
		my @save;
		if ( $cmd ne "SELECT" ) {
			warn "Invalid command: $cmd, $grp, $exec\n";
			return;
		}
		my $newuri = $idgrp->{uri};
		my $newline = $self->find_uri( $newuri );
		if ( $data eq "NEW SOURCE" ) {
			my $line = $self->find_uri( $newuri );
			$line->{cmd} = "GET";
		} elsif ( my $line = $self->find_uri( $data ) ) {
			$line->{uris}->{ $newuri } = $newline->{uris}->{ $newuri };
			delete $newline->{uris}->{ $newuri };
		} else {
			RSGet::FileList::save( $data, clones =>
				{ $newuri => $newline->{uris}->{ $newuri } } );
			delete $newline->{uris}->{ $newuri };
			RSGet::FileList::update();
		}
	} elsif ( $grp eq "adduri" ) {
		my $target = $self->find_uri( $data );
		if ( $cmd eq "CLEAR ERROR" ) {
			delete $target->{uris}->{ $data }->[1]->{error};
		} elsif ( $cmd eq "DISABLE" ) {
			$target->{uris}->{ $data }->[1]->{error} = "disabled";
		} elsif ( $cmd eq "REMOVE" ) {
			delete $target->{uris}->{ $data };
		} else {
			warn "Invalid command: $cmd, $grp, $exec\n";
			return;
		}
	} elsif ( $grp eq "addlist" ) {
		if ( $cmd eq "CONFIRM" ) {
			$self->finish();
		}
	} else {
		warn "Invalid command group: $cmd, $grp, $exec\n";
		return;
	}
}

1;

# vim: ts=4:sw=4:fdm=marker
