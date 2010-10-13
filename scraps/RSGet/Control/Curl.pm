package RSGet::Control::Curl;
# This file is an integral part of rsget.pl downloader.
#
# 2009-2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Curl;
use URI::Escape;
use MIME::Base64;


sub content_filename
{
	# TODO: actually read rfc2183 and rfc2184
	local $_ = shift;

	s/\s*;?\s+$//; # remove at least last \r
	my $src = $_;
	unless ( s/^\s*attachment\s*//i ) {
		warn "Not an attachment in C-D: '$src'\n" if verbose( 1 );
		return;
	}
	unless ( s/^;(.*?\s+)?filename//i ) {
		warn "No filename in C-D: '$src'\n" if verbose( 1 );
		return;
	}
	if ( s/^\*=(.+?)('.*?')// ) {
		warn "C-D: Unknown filename encoding: $1 $2, at $src\n"
			if uc $1 ne "UTF-8" and verbose( 1 );
		s/\s+.*//;
		return $_;
	}
	return unless s/^\s*=\s*//;
	if ( s/^"// ) {
		unless ( s/".*// ) {
			warn "C-D: Broken filename: $src\n"
				if verbose( 1 );
			return;
		}
	} elsif ( m/=\?(.*?)\?B\?(.*?)\?=/ ) {
		# described in rfc2047
		warn "C-D: Unsupported filename encoding: $1, at $src\n"
			if uc $1 ne "UTF-8" and verbose( 1 );
		$_ = decode_base64( $2 );
	} else {
		s/[;\s].*//;
	}
	p "C-D filename is: $_\n" if verbose( 2 );
	return $_;
}

sub file_init
{
	my $supercurl = shift;
	my $curl = $supercurl->{curl};
	my $get_obj = $supercurl->{get_obj};
	my $time = time;

	hadd $supercurl,
		time_start => $time,
		time_stamp => [ $time, 0, $time, 0, $time, 0 ],
		size_start => 0,
		size_got => 0;

	{
		my $mime = $curl->getinfo( CURLINFO_CONTENT_TYPE );
		if ( $mime =~ m#^text/html# ) {
			$get_obj->{is_html} = 1;
			$supercurl->{size_total} = 0;
			return;
		}
	}

	if ( my $f_len = $curl->getinfo( CURLINFO_CONTENT_LENGTH_DOWNLOAD ) ) {
		$supercurl->{size_total} = $f_len;
	}
	if ( $supercurl->{size_total} <= 0 and $supercurl->{force_size} ) {
		$supercurl->{size_total} = $supercurl->{force_size};
	}

	$get_obj->dump( $supercurl->{head}, "head" ) if verbose( 5 );
	my $fname;
	if ( $supercurl->{force_name} ) {
		$fname = $supercurl->{force_name};
	} elsif ( $supercurl->{head} =~ /^Content-Disposition:(.+?)$/mi ) {
		my $cf = content_filename( $1 );
		$fname = de_ml( uri_unescape( $cf ) ) if defined $cf and length $cf;
	}
	unless ( $fname ) {
		my $eurl = $curl->getinfo( CURLINFO_EFFECTIVE_URL );
		$eurl =~ s#^.*/##;
		$eurl =~ s/\?.*$//;
		$fname = de_ml( uri_unescape( $eurl ) );
	}

	if ( my $fn = $supercurl->{fname} ) {
		if ( $fname ne $fn ) {
			$get_obj->log( "WARNING: Name mismatch, shoud be '$fname'" );
		}
		$fname = $supercurl->{fname};
		if ( $supercurl->{head} =~ m{^Content-Range:\s*bytes\s*(\d+)-(\d+)(/(\d+))?\s*$}im ) {
			my ( $start, $stop ) = ( +$1, +$2 );
			$supercurl->{size_total} = +$4 if $3;

			$get_obj->log( "ERROR: Size mismatch: $supercurl->{fsize} != $supercurl->{size_total}" )
				if $supercurl->{fsize} != $supercurl->{size_total};

			my $fp = $supercurl->{filepath};
			my $old = file_backup( $fp, "continue" );
			my $old_msg = "";
			if ( $old ) {
				rename $fp, $old;
				copy( $old, $fp ) || die "Cannot create backup file: $!";
				$old =~ s#.*/##;
				$old_msg = ", backup saved as '$old'";
			}

			open my $f_out, '+<', $fp;
			seek $f_out, $start, SEEK_SET;
			$get_obj->log( "Continuing at " . bignum( $start ) . $old_msg );

			hadd $supercurl,
				file => $f_out,
				size_start => $start,
				size_got => $start,
				time_stamp => [ $time, $start, $time, $start, $time, $start ];

			RSGet::FileList::update(); # to update statistics
			return;
		}
	} else {
		$supercurl->{fname} = $fname;
	}

	$get_obj->started_download( fname => $supercurl->{fname}, fsize => $supercurl->{size_total} );

	{
		my $fn = $supercurl->{filepath} =
			filepath( setting("workdir"), $get_obj->{_opts}->{dir}, $supercurl->{fname} );
		my $old = file_backup( $fn, "scratch" );
		if ( $old ) {
			rename $fn, $old;
			$old =~ s#.*/##;
			$get_obj->log( "Old renamed to '$old'" );
		}
		open my $f_out, '>', $fn;
		$supercurl->{file} = $f_out;
	}
}

sub body_file
{
	my ($chunk, $supercurl) = @_;

	file_init( $supercurl ) unless exists $supercurl->{size_total};

	my $len = length $chunk;
	$supercurl->{size_got} += $len;

	if ( my $file = $supercurl->{file} ) {
		my $p = print $file $chunk;
		die "\nCannot write data: $!\n" unless $p;
	} else {
		$supercurl->{body} .= $chunk;
	}

	return $len;
}

sub body_scalar
{
	my ($chunk, $scalar) = @_;
	$$scalar .= $chunk;
	return length $chunk;
}

sub filepath
{
	my $outdir = shift || '.';
	my $subdir = shift;
	my $fname = shift;

	$outdir .= '/' . $subdir if $subdir;
	unless ( -d $outdir ) {
		unless ( mkpath( $outdir ) ) {
			$outdir = '.';
		}
	}
	return $outdir . '/' . $fname;
}

sub finish
{
	my $id = shift;
	my $err = shift;

	my $supercurl = $active_curl{ $id };
	delete $active_curl{ $id };

	my $curl = $supercurl->{curl};
	delete $supercurl->{curl}; # remove circular dep

	my $get_obj = $supercurl->{get_obj};
	delete $supercurl->{get_obj};

	if ( $supercurl->{file} ) {
		close $supercurl->{file};
		$get_obj->print( "DONE " . donemsg( $supercurl ) );
	}

	$get_obj->linedata();

	my $eurl = $curl->getinfo( CURLINFO_EFFECTIVE_URL );
	$get_obj->{content_type} = $curl->getinfo( CURLINFO_CONTENT_TYPE );
	my $error = $curl->errbuf;
	$curl = undef; # destroy curl before destroying getter

	if ( $err ) {
		#warn "error($err): $error\n";
		$get_obj->print( "ERROR($err): $error" ) if $err ne "aborted";
		if ( $error =~ /Couldn't bind to '(.*)'/ or $error =~ /bind failed/ ) {
			my $if = $get_obj->{_outif};
			RSGet::Dispatch::remove_interface( $if, "Interface $if is dead" );
			$get_obj->{_abort} = "Interface $if is dead";
		} elsif ( $error =~ /transfer closed with (\d+) bytes remaining to read/ ) {
			RSGet::Dispatch::mark_used( $get_obj );
			$get_obj->{_abort} = "PARTIAL " . donemsg( $supercurl );
		} elsif ( $err eq "aborted" ) {

		} else {
			$get_obj->log( "ERROR($err): $error" );
		}
		$get_obj->problem();
		return undef;
	}

	if ( $supercurl->{file} ) {
		rename_done: {
			my $infile = $supercurl->{filepath};
			my $outfile = filepath( setting("outdir"), $get_obj->{_opts}->{dir}, $supercurl->{fname} );
			if ( -e $outfile ) {
				my @si = stat $infile;
				my @so = stat $outfile;
				if ( $si[0] == $so[0] and $si[1] == $so[1] ) {
					p "$infile and $outfile are the same file, not renaming"
						if verbose( 2 );
					last rename_done;
				}

				my $out_rename = file_backup( $outfile, "done" );
				rename $outfile, $out_rename if $out_rename;
				p "backing up $outfile as $out_rename" if verbose( 1 );
			}
			p "renaming $infile to $outfile" if verbose( 2 );
			$! = undef;
			rename $infile, $outfile;
			if ( $! ) {
				warn "Cannot rename $infile to $outfile ($!), copying instead\n"
					if verbose( 1 );
				copy( $infile, $outfile ) || die "Cannot copy $infile to $outfile: $!";
				unlink $infile;
			}
		}

		$get_obj->{dlinfo} = sprintf 'DONE %s %s / %s',
			$supercurl->{fname},
			bignum( $supercurl->{size_got} ),
			bignum( $supercurl->{size_total} );
	} else {
		$get_obj->{body} = $supercurl->{body};
	}

	$get_obj->get_finish( $eurl, $supercurl->{keep_referer} || 0 );
}



my $avg_speed = 0;
sub update_status
{
	my $time = time;
	my $total_speed = 0;

	foreach my $supercurl ( values %active_curl ) {
		next unless exists $supercurl->{size_total};
		my ($size_got, $size_total, $time_stamp ) =
			@$supercurl{ qw(size_got size_total time_stamp) };

		my $size = bignum( $size_got ) . " / " . bignum( $size_total );
		if ( $size_total > 0 ) {
			my $per = sprintf "%.2f%%", $size_got * 100 / $size_total;
			$size .= " [$per]";
			$supercurl->{get_obj}->linedata( prog => $per );
		}

		if ( $time_stamp->[4] + 30 <= $time ) {
			@$time_stamp[0..3] = @$time_stamp[2..5];
			$time_stamp->[4] = $time;
			$time_stamp->[5] = $size_got;
		}

		my $time_diff = $time - $time_stamp->[0];
		my $size_diff = $size_got - $time_stamp->[1];

		if ( $time_diff > 0 and $size_diff == 0 ) {
			$supercurl->{stalled_since} ||= $time;
			my $stime = s2string( $time - $supercurl->{stalled_since} );
			$supercurl->{get_obj}->print( "$size; STALLED $stime" );
			next;
		}

		my $speed = "???";
		if ( $time_diff > 0 ) {
			my $s = $size_diff / ( $time_diff * 1024 );
			$speed = sprintf "%.2f", $s;
			$total_speed += $s;
		}

		my $eta = "";
		if ( $size_total > 0 and $time_diff > 0 and $size_diff > 0 ) {
			my $tleft = ($size_total - $size_got) * $time_diff / $size_diff;
			$eta = " " . s2string( $tleft );
			delete $supercurl->{stalled_since}
		}

		$supercurl->{get_obj}->print( "$size; ${speed}KB/s$eta" );
	}
	$avg_speed = ($avg_speed * 9 + $total_speed) / 10;

	my $running = scalar keys %active_curl;
	RSGet::Line::status(
		'running cURL' => $running,
		'total speed' => ( sprintf '%.2fKB/s', $avg_speed )
	);
	return;
}

sub donemsg
{
	my $supercurl = shift;

	my $size_diff = $supercurl->{size_got} - $supercurl->{size_start};
	my $time_diff = time() - $supercurl->{time_start};
	$time_diff = 1 unless $time_diff;
	my $eta = s2string( $time_diff );
	my $speed = sprintf "%.2f", $size_diff / ( $time_diff * 1024 );

	return bignum( $supercurl->{size_got} ) . "; ${speed}KB/s $eta";
}


1;

# vim: ts=4:sw=4:fdm=marker
