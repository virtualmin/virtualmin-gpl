#!/usr/local/bin/perl
# Send ratings for scripts to Virtualmin Inc

package virtual_server;
$main::no_acl_check++;
require './virtual-server-lib.pl';

# Get all ratings, and work out an average for each script
$ratings = &list_all_script_ratings();
foreach $user (keys %$ratings) {
	foreach $type (keys %{$ratings->{$user}}) {
		$count{$type}++;
		$score{$type} += $ratings->{$user}->{$type};
		}
	}

if (%count) {
	# We have some scores .. send them in
	&read_env_file("/etc/virtualmin-license", \%serial);
	@params = ( "serial=".
		    ($serial{'SerialNumber'} || &get_system_hostname()) );
	foreach $type (keys %count) {
		push(@params, $type."=".$score{$type});
		push(@params, $type."_count"."=".$count{$type});
		}
	$page = $script_ratings_page."?".join("&", @params);
	&http_download($script_ratings_host, $script_ratings_port, $page,
		       \$out, \$error, undef, 0, undef, undef, 60, 0, 1);
	if ($error) {
		print STDERR "Failed to send ratings : $error\n";
		}
	}

# Fetch the latest average scores
&http_download($script_ratings_host, $script_ratings_port,
	       $script_fetch_ratings_page, \$fout, \$ferror,
	       undef, 0, undef, undef, 60, 0, 1);
if ($ferror) {
	print STDERR "Failed to get ratings : $ferror\n";
	}
else {
	%fetched = ( );
	foreach $line (split(/\r?\n/, $fout)) {
		($type, $rating, $count) = split(/\s+/, $line);
		$fetched{$type} = $rating;
		$fetched{$type." count"} = $count;
		}
	&save_overall_script_ratings(\%fetched);
	}

