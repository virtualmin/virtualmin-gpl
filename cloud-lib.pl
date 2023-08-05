# Functions for generically handling cloud storage providers

# list_cloud_providers()
# Returns a list of hash refs with details of known providers
sub list_cloud_providers
{
my @rv = ( { 'name' => 's3',
	     'prefix' => [ 's3', 's3rrs' ],
	     'url' => 'https://aws.amazon.com/s3/',
	     'desc' => $text{'cloud_s3desc'},
	     'longdesc' => \&cloud_s3_longdesc },
	   { 'name' => 'rs',
	     'prefix' => [ 'rs' ],
	     'url' => 'https://www.rackspace.com/openstack/public/files',
	     'desc' => $text{'cloud_rsdesc'},
	     'longdesc' => $text{'cloud_rs_longdesc'} } );
if ($virtualmin_pro) {
	my $ourl = &get_miniserv_base_url()."/$module_name/oauth.cgi";
	push(@rv, { 'name' => 'google',
		    'prefix' => [ 'gcs' ],
		    'url' => 'https://cloud.google.com/storage',
		    'desc' => $text{'cloud_googledesc'},
		    'longdesc' => \&cloud_google_longdesc });
	push(@rv, { 'name' => 'dropbox',
		    'prefix' => [ 'dropbox' ],
		    'url' => 'https://www.dropbox.com/',
		    'desc' => $text{'cloud_dropboxdesc'},
		    'longdesc' => $text{'cloud_dropbox_longdesc'} });
	push(@rv, { 'name' => 'bb',
		    'prefix' => [ 'bb' ],
		    'url' => 'https://www.backblaze.com/',
		    'desc' => $text{'cloud_bbdesc'},
		    'longdesc' => $text{'cloud_bb_longdesc'} });
	push(@rv, { 'name' => 'azure',
		    'prefix' => [ 'azure' ],
		    'url' => 'https://azure.microsoft.com/',
		    'desc' => $text{'cloud_azdesc'},
		    'longdesc' => $text{'cloud_az_longdesc'} });
	}
return @rv;
}

# backup_uses_cloud(&backup, &provider)
# Checks if any dest of a backup uses this provider
sub backup_uses_cloud
{
my ($backup, $prov) = @_;
my @rv;
foreach my $d (&get_scheduled_backup_dests($backup)) {
	foreach my $p (@{$prov->{'prefix'}}) {
		if ($d =~ /^\Q$p\E:/) {
			push(@rv, $d);
			last;
			}
		}
	}
return wantarray ? @rv : $rv[0];
}

######## Functions for Amazon S3 ########

sub cloud_s3_get_state
{
if ($config{'s3_akey'}) {
	return { 'ok' => 1,
		 'desc' => &text('cloud_s3account',
				 "<tt>$config{'s3_akey'}</tt>"),
	       };
	}
elsif (&can_use_aws_s3_creds()) {
	return { 'ok' => 1,
		 'desc' => $text{'cloud_s3creds'},
	       };
	}
else {
	return { 'ok' => 0 };
	}
}

sub cloud_s3_longdesc
{
if (!$config{'s3_akey'} && &can_use_aws_s3_creds()) {
	return $text{'cloud_s3_creds'};
	}
else {
	return $text{'cloud_s3_longdesc'};
	}
}

sub cloud_s3_show_inputs
{
my $rv;

# Default login
if ($config{'s3_akey'} || !&can_use_aws_s3_creds()) {
	# Prompt for login
	$rv .= &ui_table_row($text{'cloud_s3_akey'},
		&ui_radio("s3_akey_def", $config{'s3_akey'} ? 0 : 1,
			  [ [ 1, $text{'cloud_noneset'} ],
			    [ 0, $text{'cloud_below'} ] ])."<br>\n".
		&ui_grid_table([ "<b>$text{'cloud_s3_access'}</b>",
			 &ui_textbox("s3_akey", $config{'s3_akey'}, 50),
			 "<b>$text{'cloud_s3_secret'}</b>",
			 &ui_textbox("s3_skey", $config{'s3_skey'}, 50) ], 2));
	}

# S3 endpoint hostname, for non-amazon implementations
$rv .= &ui_table_row($text{'cloud_s3_endpoint'},
	&ui_opt_textbox("s3_endpoint", $config{'s3_endpoint'}, 40,
			$text{'cloud_s3_amazon'}));

# Upload chunk size
$rv .= &ui_table_row($text{'cloud_s3_chunk'},
	&ui_opt_textbox("s3_chunk", $config{'s3_chunk'}, 6,
			$text{'default'}." (5 MB)"));

# Location for new buckets
my $l = $config{'s3_location'};
if ($config{'s3_endpoint'}) {
	$rv .= &ui_table_row($text{'cloud_s3_location'},
		&ui_opt_textbox("s3_location", $l, 30,
				$text{'default'}));
	}
else {
	my @locs = &s3_list_locations();
	my $found = !$l || &indexof($l, @locs) >= 0;
	$rv .= &ui_table_row($text{'cloud_s3_location'},
		&ui_select("s3_location", $found ? $l : "*",
			   [ [ "", $text{'default'} ],
			     @locs,
			     [ "*", $text{'cloud_s3_lother'} ] ],
			   1, 0, 1)." ".
		&ui_textbox("s3_location_other", $found ? "" : $l, 20));
	}

return $rv;
}

sub cloud_s3_parse_inputs
{
my ($in) = @_;

# Parse default login
if ($config{'s3_akey'} || !&can_use_aws_s3_creds()) {
	if ($in->{'s3_akey_def'}) {
		delete($config{'s3_akey'});
		delete($config{'s3_skey'});
		}
	else {
		$in->{'s3_akey'} =~ /^\S+$/ || &error($text{'backup_eakey'});
		$in->{'s3_skey'} =~ /^\S+$/ || &error($text{'backup_eskey'});
		$config{'s3_akey'} = $in->{'s3_akey'};
		$config{'s3_skey'} = $in->{'s3_skey'};
		}
	}

# Parse endpoint hostname
if ($in->{'s3_endpoint_def'}) {
	delete($config{'s3_endpoint'});
	}
else {
	my ($host, $port) = split(/:/, $in->{'s3_endpoint'});
	&to_ipaddress($host) ||
		&error($text{'cloud_es3_endpoint'});
	!$port || $port =~ /^\d+$/ ||
		&error($text{'cloud_es3_endport'});
	$config{'s3_endpoint'} = $in->{'s3_endpoint'};
	}

# Parse chunk size
if ($in->{'s3_chunk_def'}) {
	delete($config{'s3_chunk'});
	}
else {
	$in->{'s3_chunk'} =~ /^[1-9][0-9]*$/ ||
		&error($text{'cloud_es3_chunk'});
	$config{'s3_chunk'} = $in->{'s3_chunk'};
	}

# Parse new bucket location
if ($in->{'s3_location_def'}) {
	$config{'s3_location'} = '';
	}
else {
	my $l = $in->{'s3_location'};
	$l = $in->{'s3_location_other'} if ($l eq "*");
	$l =~ /^[a-z0-9\.\-]*/i || &error($text{'cloud_es3_location'});
	$config{'s3_location'} = $l;
	}

&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);

return undef;
}

# cloud_s3_clear()
# Reset the S3 account to the default
sub cloud_s3_clear
{
# Clear Virtualmin's credentials
my $akey = $config{'s3_akey'};
&lock_file($module_config_file);
delete($config{'s3_akey'});
delete($config{'s3_skey'});
delete($config{'s3_location'});
&save_module_config();
&unlock_file($module_config_file);

# Also clear the AWS creds
my @uinfo = getpwnam("root");
foreach my $f ("$uinfo[7]/.aws/config", "$uinfo[7]/.aws/credentials") {
	&lock_file($f);
	my $lref = &read_file_lines($f);
	my ($start, $end, $inside) = (-1, -1, 0);
	for(my $i=0; $i<@$lref; $i++) {
		if ($lref->[$i] =~ /^\[(profile\s+)?\Q$akey\E\]$/) {
			$start = $end = $i;
			$inside = 1;
			}
		elsif ($lref->[$i] =~ /^\S+\s*=\s*\S+/ && $inside) {
			$end = $i;
			}
		else {
			$inside = 0;
			}
		}
	if ($start >= 0) {
		splice(@$lref, $start, $end-$start+1);
		}
	&flush_file_lines($f);
	&unlock_file($f);
	}
}

######## Functions for Rackspace Cloud Files ########

sub cloud_rs_get_state
{
if ($config{'rs_user'}) {
	return { 'ok' => 1,
		 'desc' => &text('cloud_rsuser', "<tt>$config{'rs_user'}</tt>"),
	       };
	}
else {
	return { 'ok' => 0 };
	}
}

sub cloud_rs_show_inputs
{
my $rv;

# Default login
$rv .= &ui_table_row($text{'cloud_rs_user'},
	&ui_radio("rs_user_def", $config{'rs_user'} ? 0 : 1,
		  [ [ 1, $text{'cloud_noneset'} ],
		    [ 0, $text{'cloud_below'} ] ])."<br>\n".
	&ui_grid_table([ "<b>$text{'cloud_rs_user'}</b>",
		         &ui_textbox("rs_user", $config{'rs_user'}, 50),
		         "<b>$text{'cloud_rs_key'}</b>",
                         &ui_textbox("rs_key", $config{'rs_key'}, 50) ], 2));

# Rackspace endpoint
my @eps = &list_rackspace_endpoints();
$rv .= &ui_table_row($text{'cloud_rs_endpoint'},
	&ui_select("rs_endpoint", $config{'rs_endpoint'}, \@eps, 1, 0, 1));

# Use internal address?
$rv .= &ui_table_row($text{'cloud_rs_snet'},
	&ui_yesno_radio("rs_snet", $config{'rs_snet'}));

# Upload chunk size
$rv .= &ui_table_row($text{'cloud_rs_chunk'},
	&ui_opt_textbox("rs_chunk", $config{'rs_chunk'}, 6,
			$text{'default'}." (200 MB)"));

return $rv;
}

sub cloud_rs_parse_inputs
{
my ($in) = @_;

# Parse default login
if ($in->{'rs_user_def'}) {
	delete($config{'rs_user'});
	delete($config{'rs_key'});
	}
else {
	$in->{'rs_user'} =~ /^\S+$/ || &error($text{'backup_ersuser'});
	$in->{'rs_key'} =~ /^\S+$/ || &error($text{'backup_erskey'});
	$config{'rs_user'} = $in->{'rs_user'};
	$config{'rs_key'} = $in->{'rs_key'};
	}

# Parse endpoint
$config{'rs_endpoint'} = $in{'rs_endpoint'};

# Parse internal network flag
$config{'rs_snet'} = $in{'rs_snet'};

# Parse chunk size
if ($in->{'rs_chunk_def'}) {
	delete($config{'rs_chunk'});
	}
else {
	$in->{'rs_chunk'} =~ /^[1-9][0-9]*$/ ||
		&error($text{'cloud_es3_chunk'});
	$config{'rs_chunk'} = $in->{'rs_chunk'};
	}

&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);

return undef;
}

# cloud_rs_clear()
# Reset the Rackspace account to the default
sub cloud_rs_clear
{
delete($config{'rs_user'});
delete($config{'rs_key'});
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
}

sub list_rackspace_endpoints
{
return ( [ 'https://identity.api.rackspacecloud.com/v1.0', 'US default' ],
	 [ 'https://lon.auth.api.rackspacecloud.com/v1.0', 'UK default' ],
	 [ 'https://identity.api.rackspacecloud.com/v1.0;DFW', 'US - Dallas' ],
	 [ 'https://identity.api.rackspacecloud.com/v1.0;ORD', 'US - Chicago' ] );
}


######## Functions for Google Cloud Storage ########

sub cloud_google_get_state
{
if ($config{'google_account'} &&
    ($config{'google_oauth'} || $config{'google_rtoken'})) {
	return { 'ok' => 1,
		 'desc' => &text('cloud_gaccount',
				 "<tt>$config{'google_account'}</tt>",
				 "<tt>$config{'google_project'}</tt>"),
	       };
	}
elsif ($virtualmin_pro && &can_use_gcloud_storage_creds()) {
	return { 'ok' => 1,
		 'desc' => $text{'cloud_gcpcreds'},
	       };
	}
else {
	return { 'ok' => 0 };
	}
}

sub cloud_google_longdesc
{
if (!$config{'google_account'} && $virtualmin_pro &&
    &can_use_gcloud_storage_creds()) {
	return $text{'cloud_google_creds'};
	}
else {
	my $ourl = &get_miniserv_base_url()."/$module_name/oauth.cgi";
	return &text('cloud_google_longdesc', $ourl);
	}
}

sub cloud_google_show_inputs
{
my $rv;

if ($virtualmin_pro && &can_use_gcloud_storage_creds() &&
   !$config{'google_account'}) {
	$rv .= &ui_table_row($text{'cloud_google_account'},
		&get_gcloud_account());

	# Optional GCE project name
	$rv .= &ui_table_row($text{'cloud_google_project'},
		&ui_opt_textbox("google_project", $config{'google_project'}, 40,
			$text{'default'}." (".&get_gcloud_project().")"));
	}
else {
	# Google account
	$rv .= &ui_table_row($text{'cloud_google_account'},
		&ui_textbox("google_account", $config{'google_account'}, 40));

	# Google OAuth2 client ID
	$rv .= &ui_table_row($text{'cloud_google_clientid'},
		&ui_textbox("google_clientid", $config{'google_clientid'}, 80));

	# Google client secret
	$rv .= &ui_table_row($text{'cloud_google_secret'},
		&ui_textbox("google_secret", $config{'google_secret'}, 60));

	# GCE project name
	$rv .= &ui_table_row($text{'cloud_google_project'},
		&ui_textbox("google_project", $config{'google_project'}, 40));
	}

# Default location for new buckets
$rv .= &ui_table_row($text{'cloud_google_location'},
	&ui_select("google_location", $config{'google_location'},
		   [ [ "", $text{'default'} ],
		     &list_gcs_locations() ]));

# OAuth2 code
if ($config{'google_oauth'}) {
	$rv .= &ui_table_row($text{'cloud_google_oauth'},
		             "<tt>$config{'google_oauth'}</tt>");
	}

return $rv;
}

sub cloud_google_parse_inputs
{
my ($in) = @_;
my $reauth = 0;
my $authed = 0;

if ($virtualmin_pro && &can_use_gcloud_storage_creds() &&
   !$config{'google_account'}) {
	# Just parse project name
	$authed = 1;
	if ($in->{'google_project_def'}) {
		$config{'google_project'} = '';
		}
	else {
		$in->{'google_project'} =~ /^\S+$/ ||
			&error($text{'cloud_egoogle_project'});
		$config{'google_project'} = $in->{'google_project'};
		}
	}
else {
	# Parse google account
	$in->{'google_account'} =~ /^\S+\@\S+$/ ||
		&error($text{'cloud_egoogle_account'});
	$reauth++ if ($config{'google_account'} ne $in->{'google_account'});
	$config{'google_account'} = $in->{'google_account'};

	# Parse client ID
	$in->{'google_clientid'} =~ /^\S+$/ ||
		&error($text{'cloud_egoogle_clientid'});
	$reauth++ if ($config{'google_clientid'} ne $in->{'google_clientid'});
	$config{'google_clientid'} = $in->{'google_clientid'};

	# Parse client secret
	$in->{'google_secret'} =~ /^\S+$/ ||
		&error($text{'cloud_egoogle_secret'});
	$reauth++ if ($config{'google_secret'} ne $in->{'google_secret'});
	$config{'google_secret'} = $in->{'google_secret'};

	# Parse project name
	$in->{'google_project'} =~ /^\S+$/ ||
		&error($text{'cloud_egoogle_project'});
	$reauth++ if ($config{'google_project'} ne $in->{'google_project'});
	$config{'google_project'} = $in->{'google_project'};
	}

# Parse bucket location
$config{'google_location'} = $in->{'google_location'};

&lock_file($module_config_file);
if (!$authed) {
	$reauth++ if (!$config{'google_oauth'});
	$config{'cloud_oauth_mode'} = $reauth ? 'google' : undef;
	}
&save_module_config();
&unlock_file($module_config_file);

if (!$reauth) {
	# Nothing more to do - either the OAuth2 token was just set, or the
	# settings were saved with no change
	return undef;
	}
if ($authed) {
	# Nothing to do, because token comes from the gcloud command
	return undef;
	}

my $url = &get_miniserv_base_url()."/virtual-server/oauth.cgi";
return $text{'cloud_descoauth'}."<p>\n".
       &ui_link("https://accounts.google.com/o/oauth2/auth?".
                "scope=https://www.googleapis.com/auth/devstorage.read_write&".
                "redirect_uri=".&urlize($url)."&".
                "response_type=code&".
                "client_id=".&urlize($in->{'google_clientid'})."&".
                "login_hint=".&urlize($in->{'google_account'})."&".
                "access_type=offline&".
                "prompt=consent", $text{'cloud_openoauth'},
                undef, "target=_blank")."<p>\n".
       $text{'cloud_descoauth2'}."<p>\n";
}

# cloud_google_clear()
# Reset the GCS account to the default
sub cloud_google_clear
{
delete($config{'google_account'});
delete($config{'google_clientid'});
delete($config{'google_secret'});
delete($config{'google_oauth'});
delete($config{'google_token'});
delete($config{'google_rtoken'});
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
}

######## Functions for Dropbox ########

sub cloud_dropbox_get_state
{
if ($config{'dropbox_account'} && $config{'dropbox_oauth'}) {
	return { 'ok' => 1,
		 'desc' => &text('cloud_daccount',
				 "<tt>$config{'dropbox_account'}</tt>"),
	       };
	}
else {
	return { 'ok' => 0 };
	}
}

sub cloud_dropbox_show_inputs
{
my $rv;

# Dropbox account
$rv .= &ui_table_row($text{'cloud_dropbox_account'},
	&ui_textbox("dropbox_account", $config{'dropbox_account'}, 40));

# OAuth2 code
if ($config{'dropbox_oauth'}) {
	$rv .= &ui_table_row($text{'cloud_dropbox_oauth'},
		             "<tt>$config{'dropbox_oauth'}</tt>");
	}

# OAuth2 token
if ($config{'dropbox_token'}) {
	$rv .= &ui_table_row($text{'cloud_dropbox_token'},
		             "<tt>$config{'dropbox_token'}</tt>");
	}

return $rv;
}

sub cloud_dropbox_parse_inputs
{
my ($in) = @_;
my $reauth = 0;

if ($in{'dropbox_set_oauth'}) {
	# Special mode - saving the oauth token
	$in->{'dropbox_oauth'} =~ /^\S+$/ ||
		&error($text{'cloud_egoogle_oauth'});
	$config{'dropbox_oauth'} = $in->{'dropbox_oauth'};
	}
else {
	# Parse dropbox account
	$in->{'dropbox_account'} =~ /^\S+\@\S+$/ ||
		&error($text{'cloud_edropbox_account'});
	$reauth++ if ($config{'dropbox_account'} ne $in->{'dropbox_account'});
	$config{'dropbox_account'} = $in->{'dropbox_account'};

	$reauth++ if (!$config{'dropbox_oauth'});
	}

if ($config{'dropbox_oauth'} && !$config{'dropbox_token'}) {
	# Need to get access token for the first time
	my ($ok, $token, $uid, $rtoken, $expires) =
		&get_dropbox_oauth_access_token(0);
	$ok || &error(&text('cloud_egoogletoken', $token));
	$config{'dropbox_token'} = $token;
	$config{'dropbox_uid'} = $uid;
	$config{'dropbox_tstart'} = time();
	$config{'dropbox_rtoken'} = $rtoken;
	$config{'dropbox_expires'} = $expires;
	}

&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);

if ($in{'dropbox_set_oauth'} || !$reauth) {
	# Nothing more to do - either the OAuth2 token was just set, or the
	# settings were saved with no change
	return undef;
	}

return $text{'cloud_descoauth_dropbox'}."<p>\n".
       &ui_link("https://www.dropbox.com/oauth2/authorize?".
		"response_type=code&client_id=$dropbox_app_key&token_access_type=offline",
                $text{'cloud_openoauth'},
                undef,
                "target=_blank")."<p>\n".
       &ui_form_start("save_cloud.cgi", "post").
       &ui_hidden("name", "dropbox").
       &ui_hidden("dropbox_set_oauth", 1).
       "<b>$text{'cloud_newoauth_dropbox'}</b> ".
       &ui_textbox("dropbox_oauth", undef, 80)."<p>\n".
       &ui_form_end([ [ undef, $text{'save'} ] ]);
}

# cloud_dropbox_clear()
# Reset the GCS account to the default
sub cloud_dropbox_clear
{
delete($config{'dropbox_account'});
delete($config{'dropbox_oauth'});
delete($config{'dropbox_token'});
delete($config{'dropbox_rtoken'});
delete($config{'dropbox_expires'});
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
}

######## Functions for Backblaze ########

sub cloud_bb_get_state
{
if ($config{'bb_keyid'}) {
	return { 'ok' => 1,
		 'desc' => &text('cloud_baccount',
				 "<tt>$config{'bb_keyid'}</tt>"),
	       };
	}
else {
	return { 'ok' => 0 };
	}
}

sub cloud_bb_show_inputs
{
my $rv;

# Backblaze application key ID
$rv .= &ui_table_row($text{'cloud_bb_keyid'},
	&ui_textbox("bb_keyid", $config{'bb_keyid'}, 60));

# Backblaze application key
$rv .= &ui_table_row($text{'cloud_bb_key'},
	&ui_textbox("bb_key", $config{'bb_key'}, 60));

return $rv;
}

sub cloud_bb_parse_inputs
{
$in{'bb_keyid'} =~ /^[A-Za-z0-9\/]+$/ || &error($text{'cloud_bb_ekeyid'});
$in{'bb_key'} =~ /^[A-Za-z0-9\/]+$/ || &error($text{'cloud_bb_ekey'});

# If key changed, re-login using the b2 command
if ($in{'bb_keyid'} ne $config{'bb_keyid'} ||
    $in{'bb_key'} ne $config{'bb_key'}) {
	my ($out, $err) = &run_bb_command("authorize-account",
					  [$in{'bb_keyid'}, $in{'bb_key'}]);
	if ($err) {
		&error(&text('cloud_bb_elogin',
			     "<tt>".&html_escape($err)."</tt>"));
		}
	$config{'bb_keyid'} = $in{'bb_keyid'};
	$config{'bb_key'} = $in{'bb_key'};
	}
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);

return undef;
}

# cloud_bb_clear()
# Reset the Backblaze account to the default
sub cloud_bb_clear
{
delete($config{'bb_key'});
delete($config{'bb_keyid'});
delete($config{'cloud_bb_owner'});
delete($config{'cloud_bb_reseller'});
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
}

######## Functions for Backblaze ########

sub cloud_azure_get_state
{
if ($config{'azure_account'} && $config{'azure_name'} && $config{'azure_id'}) {
	return { 'ok' => 1,
		 'desc' => &text('cloud_azaccount',
				 "<tt>$config{'azure_account'}</tt>",
				 "<tt>$config{'azure_name'}</tt>"),
	       };
	}
else {
	return { 'ok' => 0 };
	}
}

sub cloud_azure_show_inputs
{
my $rv;

# Azure account
$rv .= &ui_table_row($text{'cloud_azure_account'},
	&ui_textbox("azure_account", $config{'azure_account'}, 60));

# Storage account name
if ($config{'azure_name'}) {
	$rv .= &ui_table_row($text{'cloud_azure_name'},
		&ui_textbox("azure_name", $config{'azure_name'}, 40));
	}
else {
	$rv .= &ui_table_row($text{'cloud_azure_name'},
		&ui_opt_textbox("azure_name", $config{'azure_name'}, 40,
				$text{'cloud_azure_auto'}));
	}

# Storage subscription ID
if ($config{'azure_id'}) {
	$rv .= &ui_table_row($text{'cloud_azure_id'},
		&ui_textbox("azure_id", $config{'azure_id'}, 40));
	}
else {
	$rv .= &ui_table_row($text{'cloud_azure_id'},
		&ui_opt_textbox("azure_id", $config{'azure_id'}, 40,
				$text{'cloud_azure_auto'}));
	}

return $rv;
}

sub cloud_azure_parse_inputs
{
# Save account and check that it's in use
$in{'azure_account'} =~ /^\S+\@\S+$/ || &error($text{'cloud_eazure_eaccount'});
$config{'azure_account'} = $in{'azure_account'};
my $out = &call_az_cmd("account", ["list"]);
ref($out) && @$out || &error($text{'cloud_eazure_eaccount3'});
$out->[0]->{'user'}->{'name'} eq $in{'azure_account'} ||
	&error(&text('cloud_eazure_eaccount2', $out->[0]->{'user'}->{'name'}));

# Fetch list of storage accounts
my $stors = &call_az_cmd("storage", ["account", "list"]);
ref($stors) || &error($stors);
@$stors || &error($text{'cloud_eazure_estor'});
if ($in{'azure_name_def'}) {
	$config{'azure_name'} = $stors->[0]->{'name'};
	}
else {
	$in{'azure_name'} =~ /^[a-z0-9]+$/ ||
		&error($text{'cloud_eazure_ename'});
	$config{'azure_name'} = $in{'azure_name'};
	}
if ($in{'azure_id_def'}) {
	$stors->[0]->{'id'} =~ /^\/subscriptions\/([^\/]+)\// ||
		&error($text{'cloud_eazure_eid2'});
	$config{'azure_id'} = $1;
	}
else {
	$in{'azure_id'} =~ /^[a-z0-9\-]+$/ ||
		&error($text{'cloud_eazure_eid'});
	$config{'azure_id'} = $in{'azure_id'};
	}

# Make sure the storage account entered works
my $list = &call_az_cmd("storage", ["container", "list"]);
ref($list) || &error(&text('cloud_eazure_elist', (split(/\r?\n/, $list))[0]));

&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);

return undef;
}

# cloud_azure_clear()
# Reset the Azure account to the default
sub cloud_azure_clear
{
&lock_file($module_config_file);
delete($config{'azure_account'});
delete($config{'azure_name'});
delete($config{'azure_id'});
&save_module_config();
&unlock_file($module_config_file);
}



1;
