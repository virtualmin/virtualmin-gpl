#!/usr/local/bin/perl
# Update the oauth code for either Google Cloud Storage or DNS

$trust_unknown_referers = 1;
require './virtual-server-lib.pl';
&ReadParse();
&can_cloud_providers() || &error($text{'clouds_ecannot'});

# Get the mode for use one time
$mode = $config{'cloud_oauth_mode'};
delete($config{'cloud_oauth_mode'});

if ($mode eq 'google') {
	# Update GCS token
	$config{'google_oauth'} = $in{'code'};
	my $gce = { 'oauth' => $config{'google_oauth'},
	            'clientid' => $config{'google_clientid'},
		    'secret' => $config{'google_secret'},
		  };
	my ($ok, $token, $rtoken, $ttime) = &get_oauth_access_token($gce);
	$ok || &error(&text('cloud_egoogletoken', $token));
	$config{'google_token'} = $token;
	$config{'google_rtoken'} = $rtoken;
	$config{'google_ttime'} = $ttime;
	$config{'google_tstart'} = time();

	# Validate that it actually works
	my $buckets = &list_gcs_buckets();
	ref($buckets) || &error(&text('cloud_egoogletoken2_gcs', $buckets));
	}
elsif ($mode eq 'googledns') {
	# Update Google DNS token
	$config{'googledns_oauth'} = $in{'code'};
	my $gce = { 'oauth' => $config{'googledns_oauth'},
	            'clientid' => $config{'googledns_clientid'},
		    'secret' => $config{'googledns_secret'},
		  };
	my ($ok, $token, $rtoken, $ttime) = &get_oauth_access_token($gce);
	$ok || &error(&text('cloud_egoogletoken', $token));
	$config{'googledns_token'} = $token;
	$config{'googledns_rtoken'} = $rtoken;
	$config{'googledns_ttime'} = $ttime;
	$config{'googledns_tstart'} = time();

	# Validate that it actually works
	$rv = &call_googledns_api("/managedZones", [], "GET");
	ref($rv) || &error(&text('cloud_egoogletoken2_gdns', $rv));
	}
elsif ($mode eq 'drive') {
	# Update Drive token
	$config{'drive_oauth'} = $in{'code'};
	my $gce = { 'oauth' => $config{'drive_oauth'},
	            'clientid' => $config{'drive_clientid'},
		    'secret' => $config{'drive_secret'},
		  };
	my ($ok, $token, $rtoken, $ttime) = &get_oauth_access_token($gce);
	$ok || &error(&text('cloud_egoogletoken', $token));
	$config{'drive_token'} = $token;
	$config{'drive_rtoken'} = $rtoken;
	$config{'drive_ttime'} = $ttime;
	$config{'drive_tstart'} = time();

	# Validate that it actually works
	my $buckets = &list_drive_folders();
	ref($buckets) || &error(&text('cloud_egoogletoken2_gdrv', $buckets));
	}
else {
	&error($text{'cloud_eoauth_mode'});
	}

&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);

&webmin_log("oauth", $mode);

# This window is no longer needed
&ui_print_header(undef, $text{'clouds_oauth_done'}, "");

print "<script>window.close();</script>\n";

&ui_print_footer();
