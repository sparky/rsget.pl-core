package RSGet::FileList;

use strict;
use warnings;
use URI::Escape;
use RSGet::Tools;
set_rev qq$Id$;

my $file;
my $file_swp;

my $update = 1;
# $uri => { cmd => "CMD", globals => {...}, options => {...} }

# commands:
# GET - download
# DONE - stop, fully downloaded
# STOP - stop, partially downloaded
# ADD - add as clone if possible, new link otherwise

our @actual;
our @added;

sub set_file
{
	$file = shift;
	unless ( defined $file ) {
		$file = 'get.list';
		unless ( -r $file ) {
			p "Creating empty file list '$file'";
			open F_OUT, '>', $file;
			print F_OUT "# empty list\n";
			close F_OUT;
		}
	} else {
		p "Using '$file' file list\n";
	}
	die "Can't read '$file'\n" unless -r $file;
	my $make_swp = $settings{list_lock};
	$file_swp = eval "\"$make_swp\"";
	p "Using '$file_swp' as file lock\n";
}

sub update
{
	$update = 1;
}

our %save; # options to be saved
sub save
{
	my $uri = shift;
	my %data = @_;
	my $save_uri = $save{ $uri } ||= {};
	foreach my $key ( keys %data ) {
		my $val = $data{ $key };
		if ( $key =~ /^(options|globals|clones)/ ) {
			my $hash = $save_uri->{ $key } ||= {};
			hadd $hash, %{ $val };
		} else {
			$save_uri->{ $key } = $val;
		}
	}
}



sub h2a($)
{
	my $h = shift;
	return map { defined $h->{$_} ? ($_ . "=" . uri_escape( $h->{$_} )) : () } sort keys %$h;
}

our $listmtime = 0;
sub readlist
{
	return unless -r $file;
	my $mtime = (stat _)[9];
	return unless $update or $mtime != $listmtime;
	#p "readlist()";

	open my $list, '<', $file;
	my @list = <$list>;
	close $list;

	push @list, @added;

	my @new;

	my @used_save;
	my %all_uri;
	@actual = ();
	while ( my $line = shift @list ) {
		chomp $line;
		if ( $line =~ /^__END__\s*$/ ) { # end of the list
			push @new, $line . "\n";
			push @actual, $line;
			push @new, @list;
			push @actual, @list;
			last;
		}
		if ( $line =~ /^\s*(#.*)?$/ ) { # comments and empty lines
			push @new, $line . "\n";
			push @actual, $line;
			next;
		}
		my $mline = $line;
		while ( $mline =~ s/\s*\\$/ / or (@list and $list[0] =~ s/^\s*\+\s*/ /) ) { # stitch broken lines together
			$line = shift @list;
			chomp $line;
			$mline .= $line;
		}

		$mline =~ s/^\s+//s;
		$mline =~ s/\s+$//s;
		my @words = split /\s+/s, $mline;


		my $cmd;
		if ( $words[0] =~ /^(GET|DONE|STOP|ADD):$/ ) {
			$cmd = $1;
			shift @words;
		}
		my $globals = {};
		my $options = $globals;

		my %decoded;
		my @invalid;
		foreach ( @words ) {
			if ( /^([a-z0-9_]+)=(.*)$/ ) {
				$options->{$1} = uri_unescape( $2 );
				next;
			} elsif ( m{^(http://)?(.*?)$} ) {
				my $proto = $1 || "http://";
				my $uri = $proto . $2;
				if ( my $getter = RSGet::Dispatch::getter($uri) ) {
					$options = {};
					$decoded{ $uri } = [ $getter, $options ];
					next;
				}
			}

			push @invalid, $_;
		}

		unless ( keys %decoded ) {
			my $line = '# invalid line: ' . (join " ", ($cmd ? "$cmd:" : ()), @words);
			push @new, $line . "\n";
			push @actual, $line;
			next;
		}
		if ( @invalid ) {
			my $line = '# invalid: ' . (join " ", @invalid);
			push @new, $line . "\n";
			push @actual, $line;
		}

		$cmd ||= "GET";

		foreach my $uri ( keys %decoded ) {
			next unless exists $save{ $uri };
			push @used_save, $uri;
			my $save = $save{ $uri };
			if ( not ref $save or ref $save ne "HASH" ) {
				warn "Invalid \$save{ $uri } => $save\n";
				next;
			}
			
			my $options = $decoded{ $uri }->[1];

			$cmd = $save->{cmd} if $save->{cmd};
			hadd $globals, %{$save->{globals}} if $save->{globals};
			hadd $options, %{$save->{options}} if $save->{options};

			if ( my $links = $save->{links} ) {
				push @new, map { "ADD: $_\n" } @$links;
				# don't bother with @actual, list will be reread shortly
				$update = 2;
			}

			if ( my $clones = $save->{clones} ) {
				hadd \%decoded, %{ $clones };
				$update = 2;
			}
			delete $decoded{ $uri } if $save->{delete};
		}

		foreach my $uri ( keys %decoded ) {
			if ( $all_uri{ $uri } ) {
				warn "URI: $uri repeated, removing second one\n";
				#hadd $options, %{ $all_uri{ $uri }->[1] };
				#$all_uri{ $uri }->[1] = $options;
				delete $decoded{ $uri };
			} else {
				$all_uri{ $uri } = $decoded{ $uri };
			}
		}

		next unless keys %decoded;

		my $all_error = 1;
		foreach my $uri ( keys %decoded ) {
			my $options = $decoded{ $uri }->[1];
			unless ( $options->{error} ) {
				$all_error = 0;
				last;
			}
		}
		$cmd = "STOP" if $all_error and $cmd ne "DONE";

		push @actual, {
			cmd => $cmd,
			globals => $globals,
			uris => \%decoded
		};

		{
			my @out = ( "$cmd:", h2a( $globals ) );
			push @new, (join " ", @out) . "\n";
		}
		foreach my $uri ( sort keys %decoded ) {
			my @out = ( $uri, h2a( $decoded{ $uri }->[1] ) );
			push @new, (join " ", '+', @out) . "\n";
		}
	}
	
	# we are forced to regenerate the list if there was something added
	unlink $file_swp if @added or $update == 2;

	unless ( -e $file_swp ) {
		open my $newlist, '>', $file . ".tmp";
		print $newlist @new;
		close $newlist || die "\nCannot update $file file: $!\n";
		unlink $file;
		rename $file . ".tmp", $file;
		@added = ();
		foreach my $uri ( @used_save ) {
			delete $save{ $uri };
		}
	}

	$update = $update == 2 ? 1 : 0;
	$listmtime = (stat $file)[9];

	return \@actual;
}

1;

# vim:ts=4:sw=4
