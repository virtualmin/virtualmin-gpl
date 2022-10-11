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
	ref($buckets) || &error(&text('cloud_egoogletoken2', $buckets));
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
