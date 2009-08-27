package RSGet::FileList;

use strict;
use warnings;
use URI::Escape;
use RSGet::Tools;
our $file = 'get.list';
my $file_swp = '.get.list.swp';
our $reread = 1;
our %uri_options; # options to be saved

sub set_file
{
	my $file = shift;
	die "Can't read '$file'\n" unless -r $file;
	p "Using '$file' file list\n";
	my $make_swp = $settings{make_swp} || '.${file}.swp';
	$file_swp = eval "\"$make_swp\"";
	p "Using '$file_swp' as file lock\n";
}
sub need_update
{
	$reread = 1;
}

sub words
{
	my $pre = shift;
	my $before = shift;
	return () unless @_;
	my $line = "";
	my $lline = $pre . $before . shift;
	foreach ( @_ ) {
		if ( length $lline . $_ > 76 ) {
			$line .= "$lline \\\n";
			$lline = $pre;
		}
		$lline .= " " . $_;
	}

	$lline = $line.$lline if $line;
	return $lline."\n";
}


sub h2a($)
{
	my $h = shift;
	return map { $_ . "=" . uri_escape( $h->{$_} ) } sort keys %$h;
}

sub getter
{
	my $uri = shift;
	my @g = grep { $uri =~ m/^http:\/\/(:?www\.)?$_->{uri}/ } values %getters;
	return undef unless @g;
	return $g[0];
}

my @added_text;
sub add_text
{
	my $type = shift;
	my $text = shift;

	return unless $text;
	if ( $type eq "links" ) {
		my @words = split /\s/s, $text;

		foreach ( @words ) {
			next unless m{^(http://)?(.*?)$};
			my $proto = $1 || "http://";
			my $uri = $proto . $2;
			push @added_text, $uri . "\n" if getter($uri);
		}

		$reread = 2;
	} elsif ( $type eq "text" ) {
		foreach ( split /\n/, $text ) {
			s/\s+$//;
			push @added_text, $_."\n";
		}
	} elsif ( $type eq "comment" ) {
		foreach ( split /\n/, $text ) {
			s/\s+$//;
			push @added_text, "# $_\n";
		}
	}
	return \@added_text;
}

my $listmtime = 0;
sub readlist
{
	return unless -r $file;
	my $mtime = (stat _)[9];
	return unless $reread or $mtime != $listmtime;
	#p "readlist()";

	my @getlist;
	my @newlist;
	open my $list, '<', $file;
	while ( my $line = <$list> ) {
		chomp $line;
		if ( $line =~ /^\s*(#.*)?$/ ) { # comments and empty lines
			push @newlist, $line . "\n";
			next;
		} elsif ( $line =~ /^__END__\s*$/ ) { # end of list
			push @newlist, $line . "\n";
			push @newlist, <$list>;
			last;
		}
		while ( $line =~ s/\\$/ / ) { # stitch broken lines together
			$line .= <$list>;
			chomp $line;
		}

		$line =~ s/^\s+//;
		$line =~ s/\s+$//;


		my %uris;
		my %options;
		my @invalid;
		my @invalid_uri;

		# split line into words
		foreach ( split /\s+/, $line ) {
			if ( /^([a-z_]+)=(.*)$/ ) {
				$options{$1} = uri_unescape( $2 );
			} elsif ( m{^(http://)?(.*?)$} ) {
				my $proto = $1 || "http://";
				my $uri = $proto . $2;
				if ( my $getter = getter($uri) ) {
					$uris{ $uri } = $getter;
				} elsif ( $uri =~ m{.+\.[a-z]{2,4}/.+} ) {
					push @invalid_uri, $uri;
				} else {
					push @invalid, $_;
				}
			} else {
				push @invalid, $_;
			}
		}

		if ( not scalar keys %uris ) {
			push @newlist, words(
				"# ", "invalid line: ",
				@invalid, @invalid_uri, h2a( \%options ),
			);
			next;
		} elsif ( @invalid ) {
			push @newlist, words(
				"# ", "invalid words: ",
				@invalid, @invalid_uri
			);
		} elsif ( @invalid_uri ) {
			push @newlist, words(
				"# ", "invalid uri: ",
				@invalid_uri,
			);
		}

		foreach my $uri ( sort keys %uris ) {
			my $error = RSGet::Dispatch::is_error( $uri );
			next unless $error;
			delete $uris{ $uri };
			push @newlist, "# $error:\n# $uri\n";
		}

		unless ( keys %uris ) {
			push @newlist, words(
				"#", "", h2a( \%options )
			) if keys %options;
			next;
		}

		foreach my $uri ( sort keys %uris ) {
			hadd \%options, %{$uri_options{ $uri }} if $uri_options{ $uri };
		}

		my $status;
		foreach my $uri ( sort keys %uris ) {
			next unless $status = RSGet::Dispatch::done( $uri, $uris{ $uri } );
			$uri = "*" . $uri;
			if ( ref $status and ref $status eq "ARRAY" ) {
				push @newlist, words(
					"#", " Link: ",
					(sort keys %uris), h2a( \%options )
				);
				push @newlist, words( '', '', @$status );
			} else {
				push @newlist, words(
					"# ", "$status:\n# ",
					(sort keys %uris), h2a( \%options )
				);
			}
			$reread = 2;
			last;
		}
		next if $status;

		push @newlist, words( '', '', (sort keys %uris), h2a( \%options ) );

		push @getlist, [ \%uris, \%options ];
	}
	close $list;

	unless ( -e $file_swp ) {
		open my $newlist, '>', $file . ".tmp";
		print $newlist @newlist;
		print $newlist @added_text;
		@added_text = ();
		close $newlist || die "\nCannot update $file file: $!\n";
		unlink $file;
		rename $file . ".tmp", $file;
	}

	$reread = $reread == 2 ? 1 : 0;
	$listmtime = (stat $file)[9];

	return \@getlist;
}

1;

# vim:ts=4:sw=4
