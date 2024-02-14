# Functions for generically handling cloud storage providers

# list_cloud_providers()
# Returns a list of hash refs with details of known providers
sub list_cloud_providers
{
my @rv = ( { 'name' => 's3',
	     'prefix' => [ 's3', 's3rrs' ],
	     'clear' => 0,
	     'url' => 'https://aws.amazon.com/s3/',
	     'desc' => $text{'cloud_s3desc'},
	     'longdesc' => \&cloud_s3_longdesc },
	   { 'name' => 'rs',
	     'prefix' => [ 'rs' ],
	     'clear' => 0,
	     'url' => 'https://www.rackspace.com/openstack/public/files',
	     'desc' => $text{'cloud_rsdesc'},
	     'longdesc' => $text{'cloud_rs_longdesc'} } );
if ($virtualmin_pro) {
	my $ourl = &get_miniserv_base_url()."/$module_name/oauth.cgi";
	push(@rv, { 'name' => 'google',
		    'prefix' => [ 'gcs' ],
		    'clear' => 1,
		    'url' => 'https://cloud.google.com/storage',
		    'desc' => $text{'cloud_googledesc'},
		    'longdesc' => \&cloud_google_longdesc });
	push(@rv, { 'name' => 'dropbox',
		    'prefix' => [ 'dropbox' ],
		    'clear' => 1,
		    'url' => 'https://www.dropbox.com/',
		    'desc' => $text{'cloud_dropboxdesc'},
		    'longdesc' => $text{'cloud_dropbox_longdesc'} });
	push(@rv, { 'name' => 'bb',
		    'prefix' => [ 'bb' ],
		    'clear' => 1,
		    'url' => 'https://www.backblaze.com/',
		    'desc' => $text{'cloud_bbdesc'},
		    'longdesc' => $text{'cloud_bb_longdesc'} });
	push(@rv, { 'name' => 'azure',
		    'prefix' => [ 'azure' ],
		    'clear' => 1,
		    'url' => 'https://azure.microsoft.com/',
		    'desc' => $text{'cloud_azdesc'},
		    'longdesc' => $text{'cloud_az_longdesc'} });
	push(@rv, { 'name' => 'drive',
		    'prefix' => [ 'drive' ],
		    'clear' => 1,
		    'url' => 'https://drive.google.com/',
		    'desc' => $text{'cloud_drivedesc'},
		    'longdesc' => \&cloud_drive_longdesc });
	}
# Sort based on hash desc key
@rv = sort { $a->{'desc'} cmp $b->{'desc'} } @rv;
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
my @s3s = &list_s3_accounts();
if (@s3s == 1) {
	my $desc = $s3s[0]->{'iam'} ? $text{'cloud_s3creds'} :
			&text('cloud_s3account',
                              "<tt>$s3s[0]->{'access'}</tt>");
	return { 'ok' => 1,
		 'desc' => $desc,
	       };
	}
elsif (@s3s > 1) {
	return { 'ok' => 1,
		 'desc' => &text('cloud_s3accounts', scalar(@s3s)),
	       };
	}
else {
	return { 'ok' => 0 };
	}
}

sub cloud_s3_longdesc
{
my @s3s = &list_s3_accounts();
return &text('cloud_s3_longdesc2', 'list_s3s.cgi');
}

sub cloud_s3_show_inputs
{
my $rv;

# Upload chunk size
$rv .= &ui_table_row($text{'cloud_s3_chunk'},
	&ui_opt_textbox("s3_chunk", $config{'s3_chunk'}, 6,
			$text{'default'}." (5 MB)"));

# Available accounts
my @s3s = &list_s3_accounts();
my $ac;
if (@s3s) {
	$ac = &ui_columns_start([ $text{'s3s_access'},
                                  $text{'s3s_desc'} ]);
	foreach my $s3 (@s3s) {
		$ac .= &ui_columns_row([ $s3->{'access'}, $s3->{'desc'} ]);
		}
	$ac .= &ui_columns_end();
	}
else {
	$ac = "<i>$text{'cloud_s3_noaccounts'}</i>";
	}
$rv .= &ui_table_row($text{'cloud_s3_accounts'}, $ac);

return $rv;
}

sub cloud_s3_parse_inputs
{
my ($in) = @_;

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
	 [ 'https://identity.api.rackspacecloud.com/v1.0;ORD', 'US - Chicago' ],
       );
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

######## Functions for Google Drive ########

sub cloud_drive_get_state
{
if ($config{'drive_account'} &&
    ($config{'drive_oauth'} || $config{'drive_rtoken'})) {
	return { 'ok' => 1,
		 'desc' => &text('cloud_gaccount',
				 "<tt>$config{'drive_account'}</tt>",
				 "<tt>$config{'drive_project'}</tt>"),
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

sub cloud_drive_longdesc
{
if (!$config{'drive_account'} && $virtualmin_pro &&
    &can_use_gcloud_storage_creds()) {
	return $text{'cloud_drive_creds'};
	}
else {
	my $ourl = &get_miniserv_base_url()."/$module_name/oauth.cgi";
	return &text('cloud_drive_longdesc', $ourl);
	}
}

sub cloud_drive_show_inputs
{
my $rv;

if ($virtualmin_pro && &can_use_gcloud_storage_creds() &&
   !$config{'drive_account'}) {
	$rv .= &ui_table_row($text{'cloud_drive_account'},
		&get_gcloud_account());

	# Optional GCE project name
	$rv .= &ui_table_row($text{'cloud_google_project'},
		&ui_opt_textbox("drive_project", $config{'drive_project'}, 40,
			$text{'default'}." (".&get_gcloud_project().")"));
	}
else {
	# Google account
	$rv .= &ui_table_row($text{'cloud_google_account'},
		&ui_textbox("drive_account", $config{'drive_account'}, 40));

	# Google OAuth2 client ID
	$rv .= &ui_table_row($text{'cloud_google_clientid'},
		&ui_textbox("drive_clientid", $config{'drive_clientid'}, 80));

	# Google client secret
	$rv .= &ui_table_row($text{'cloud_google_secret'},
		&ui_textbox("drive_secret", $config{'drive_secret'}, 60));

	# GCE project name
	$rv .= &ui_table_row($text{'cloud_google_project'},
		&ui_textbox("drive_project", $config{'drive_project'}, 40));
	}

# OAuth2 code
if ($config{'drive_oauth'}) {
	$rv .= &ui_table_row($text{'cloud_google_oauth'},
		             "<tt>$config{'drive_oauth'}</tt>");
	}

return $rv;
}

sub cloud_drive_parse_inputs
{
my ($in) = @_;
my $reauth = 0;
my $authed = 0;

if ($virtualmin_pro && &can_use_gcloud_storage_creds() &&
   !$config{'drive_account'}) {
	# Just parse project name
	$authed = 1;
	if ($in->{'drive_project_def'}) {
		$config{'drive_project'} = '';
		}
	else {
		$in->{'drive_project'} =~ /^\S+$/ ||
			&error($text{'cloud_egoogle_project'});
		$config{'drive_project'} = $in->{'drive_project'};
		}
	}
else {
	# Parse google account
	$in->{'drive_account'} =~ /^\S+\@\S+$/ ||
		&error($text{'cloud_egoogle_account'});
	$reauth++ if ($config{'drive_account'} ne $in->{'drive_account'});
	$config{'drive_account'} = $in->{'drive_account'};

	# Parse client ID
	$in->{'drive_clientid'} =~ /^\S+$/ ||
		&error($text{'cloud_egoogle_clientid'});
	$reauth++ if ($config{'drive_clientid'} ne $in->{'drive_clientid'});
	$config{'drive_clientid'} = $in->{'drive_clientid'};

	# Parse client secret
	$in->{'drive_secret'} =~ /^\S+$/ ||
		&error($text{'cloud_egoogle_secret'});
	$reauth++ if ($config{'drive_secret'} ne $in->{'drive_secret'});
	$config{'drive_secret'} = $in->{'drive_secret'};

	# Parse project name
	$in->{'drive_project'} =~ /^\S+$/ ||
		&error($text{'cloud_egoogle_project'});
	$reauth++ if ($config{'drive_project'} ne $in->{'drive_project'});
	$config{'drive_project'} = $in->{'drive_project'};
	}

&lock_file($module_config_file);
if (!$authed) {
	$reauth++ if (!$config{'drive_oauth'});
	$config{'cloud_oauth_mode'} = $reauth ? 'drive' : undef;
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
                "scope=https://www.googleapis.com/auth/drive&".
                "redirect_uri=".&urlize($url)."&".
                "response_type=code&".
                "client_id=".&urlize($in->{'drive_clientid'})."&".
                "login_hint=".&urlize($in->{'drive_account'})."&".
                "access_type=offline&".
                "prompt=consent", $text{'cloud_openoauth'},
                undef, "target=_blank")."<p>\n".
       $text{'cloud_descoauth2'}."<p>\n";
}

# cloud_drive_clear()
# Reset the GCS account to the default
sub cloud_drive_clear
{
delete($config{'drive_account'});
delete($config{'drive_clientid'});
delete($config{'drive_secret'});
delete($config{'drive_oauth'});
delete($config{'drive_token'});
delete($config{'drive_rtoken'});
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
}

1;
