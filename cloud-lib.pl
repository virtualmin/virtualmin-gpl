# Functions for generically handling cloud storage providers

# list_cloud_providers()
# Returns a list of hash refs with details of known providers
sub list_cloud_providers
{
my @rv = ( { 'name' => 's3',
	     'prefix' => [ 's3', 's3rrs' ],
	     'desc' => $text{'cloud_s3desc'} },
	   { 'name' => 'rs',
	     'prefix' => [ 'rs' ],
	     'desc' => $text{'cloud_rsdesc'} } );
if ($virtualmin_pro) {
	push(@rv, { 'name' => 'google',
		    'prefix' => [ 'gcs' ],
		    'desc' => $text{'cloud_googledesc'},
		    'longdesc' => $text{'cloud_google_longdesc'} });
	push(@rv, { 'name' => 'dropbox',
		    'prefix' => [ 'dropbox' ],
		    'desc' => $text{'cloud_dropboxdesc'},
		    'longdesc' => $text{'cloud_dropbox_longdesc'} });
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
else {
	return { 'ok' => 0 };
	}
}

sub cloud_s3_show_inputs
{
my $rv;

# Default login
$rv .= &ui_table_row($text{'cloud_s3_akey'},
	&ui_radio("s3_akey_def", $config{'s3_akey'} ? 0 : 1,
		  [ [ 1, $text{'cloud_noneset'} ],
		    [ 0, $text{'cloud_below'} ] ])."<br>\n".
	&ui_grid_table([ "<b>$text{'cloud_s3_access'}</b>",
		         &ui_textbox("s3_akey", $config{'s3_akey'}, 50),
		         "<b>$text{'cloud_s3_secret'}</b>",
                         &ui_textbox("s3_skey", $config{'s3_skey'}, 50) ], 2));

# S3 endpoint hostname, for non-amazon implementations
$rv .= &ui_table_row($text{'cloud_s3_endpoint'},
	&ui_opt_textbox("s3_endpoint", $config{'s3_endpoint'}, 40,
			$text{'cloud_s3_amazon'}));

# Upload chunk size
$rv .= &ui_table_row($text{'cloud_s3_chunk'},
	&ui_opt_textbox("s3_chunk", $config{'s3_chunk'}, 6,
			$text{'default'}." (5 MB)"));

return $rv;
}

sub cloud_s3_parse_inputs
{
my ($in) = @_;

# Parse default login
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

# Parse endpoint hostname
if ($in->{'s3_endpoint_def'}) {
	delete($config{'s3_endpoint'});
	}
else {
	&to_ipaddress($in->{'s3_endpoint'}) ||
		&error($text{'cloud_es3_endpoint'});
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

&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);

return undef;
}

# cloud_s3_clear()
# Reset the S3 account to the default
sub cloud_s3_clear
{
delete($config{'s3_akey'});
delete($config{'s3_skey'});
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
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

# cloud_s3_clear()
# Reset the Rackspace account to the default
sub cloud_s3_clear
{
delete($config{'s3_user'});
delete($config{'s3_key'});
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
if ($config{'google_account'} && $config{'google_oauth'}) {
	return { 'ok' => 1,
		 'desc' => &text('cloud_gaccount',
				 "<tt>$config{'google_account'}</tt>",
				 "<tt>$config{'google_project'}</tt>"),
	       };
	}
else {
	return { 'ok' => 0 };
	}
}

sub cloud_google_show_inputs
{
my $rv;

# Google account
$rv .= &ui_table_row($text{'cloud_google_account'},
	&ui_textbox("google_account", $config{'google_account'}, 40));

# Google OAuth2 client ID
$rv .= &ui_table_row($text{'cloud_google_clientid'},
	&ui_textbox("google_clientid", $config{'google_clientid'}, 60));

# Google client secret
$rv .= &ui_table_row($text{'cloud_google_secret'},
	&ui_textbox("google_secret", $config{'google_secret'}, 40));

# GCE project name
$rv .= &ui_table_row($text{'cloud_google_project'},
	&ui_textbox("google_project", $config{'google_project'}, 40));

# OAuth2 code
if ($config{'google_oauth'}) {
	$rv .= &ui_table_row($text{'cloud_google_oauth'},
		             "<tt>$config{'google_oauth'}</tt>");
	}

# OAuth2 token
if ($config{'google_token'}) {
	$rv .= &ui_table_row($text{'cloud_google_token'},
		             "<tt>$config{'google_token'}</tt>");
	}

return $rv;
}

sub cloud_google_parse_inputs
{
my ($in) = @_;
my $reauth = 0;

if ($in{'google_set_oauth'}) {
	# Special mode - saving the oauth token
	$in->{'google_oauth'} =~ /^\S+$/ ||
		&error($text{'cloud_egoogle_oauth'});
	$config{'google_oauth'} = $in->{'google_oauth'};
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

	$reauth++ if (!$config{'google_oauth'});
	}

if ($config{'google_oauth'} && !$config{'google_token'}) {
	# Need to get access token for the first time
	my $gce = { 'oauth' => $config{'google_oauth'},
	            'clientid' => $config{'google_clientid'},
		    'secret' => $config{'google_secret'} };
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

&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);

if ($in{'google_set_oauth'} || !$reauth) {
	# Nothing more to do - either the OAuth2 token was just set, or the
	# settings were saved with no change
	return undef;
	}

return $text{'cloud_descoauth'}."<p>\n".
       &ui_link("https://accounts.google.com/o/oauth2/auth?".
                "scope=https://www.googleapis.com/auth/devstorage.read_write&".
                "redirect_uri=urn:ietf:wg:oauth:2.0:oob&".
                "response_type=code&".
                "client_id=".&urlize($in->{'google_clientid'})."&".
		"login_hint=".&urlize($in->{'google_account'}),
                $text{'cloud_openoauth'},
                undef,
                "target=_blank")."<p>\n".
       &ui_form_start("save_cloud.cgi", "post").
       &ui_hidden("name", "google").
       &ui_hidden("google_set_oauth", 1).
       "<b>$text{'cloud_newoauth'}</b> ".
       &ui_textbox("google_oauth", undef, 80)."<p>\n".
       &ui_form_end([ [ undef, $text{'save'} ] ]);
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
	my ($ok, $token, $uid) = &get_dropbox_oauth_access_token();
	$ok || &error(&text('cloud_egoogletoken', $token));
	$config{'dropbox_token'} = $token;
	$config{'dropbox_uid'} = $uid;
	$config{'dropbox_tstart'} = time();
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
       &ui_link("https://www.dropbox.com/1/oauth2/authorize?".
		"response_type=code&client_id=$dropbox_app_key",
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
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
}

1;
