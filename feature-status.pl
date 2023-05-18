# Functions for setting up web status monitoring for a domain

sub require_status
{
return if ($require_status++);
&foreign_require("status");
}

sub check_depends_status
{
local ($d) = @_;
if (!&domain_has_website($d)) {
	return $text{'setup_edepstatus'};
	}
return undef;
}

# check_status_clash()
# No need to check for clashes ..
sub check_status_clash
{
return 0;
}

# setup_status(&domain)
# Creates a new status monitor for this domain's website
sub setup_status
{
my ($d) = @_;

&$first_print($text{'setup_status'});
&require_status();
local $tmpl = &get_template($d->{'template'});

# Create website monitor
local $serv = &make_monitor($d, 0);
&status::save_service($serv);
&$second_print($text{'setup_done'});

if (&domain_has_ssl($d)) {
	# Add SSL website monitor too
	&$first_print($text{'setup_statusssl'});
	local $serv = &make_monitor($d, 1);
	&status::save_service($serv);
	&$second_print($text{'setup_done'});
	}

if (&domain_has_ssl($d) && $tmpl->{'statussslcert'}) {
	# Add SSL cert monitor
	&$first_print($text{'setup_statussslcert'});
	local $certserv = &make_sslcert_monitor($d);
	&status::save_service($certserv);
	&$second_print($text{'setup_done'});
	}
return 1;
}

# make_monitor(&domain, ssl)
# Returns a hash ref for a status object for monitoring a webserver
sub make_monitor
{
local ($d, $ssl) = @_;
local $tmpl = &get_template($d->{'template'});
local $host = &get_domain_http_hostname($d);
local $serv = { 'id' => $d->{'id'}.($ssl ? "_ssl" : "_web"),
		'type' => 'http',
		'desc' => $ssl ? "Website $host (SSL)" 
			       : "Website $host",
		'fails' => 2,
		'email' => &monitor_email($d),
		'host' => $host,
		'port' => $ssl ? $d->{'web_sslport'} : $d->{'web_port'},
		'nosched' => 0,
		'ssl' => $ssl,
		'alarm' => $tmpl->{'statustimeout'},
		'tmpl' => $tmpl->{'statustmpl'},
		'page' => '/',
		'virtualmin' => $d->{'id'},
	      };
return $serv;
}

# make_sslcert_monitor(&domain)
# Returns a hash ref for a status object for monitoring an SSL domain's cert
sub make_sslcert_monitor
{
local ($d) = @_;
local $tmpl = &get_template($d->{'template'});
local $host = &get_domain_http_hostname($d);
local $serv = { 'id' => $d->{'id'}."_sslcert",
		'type' => 'sslcert',
		'desc' => "SSL cert $host",
		'fails' => 2,
		'email' => &monitor_email($d),
		'url' => 'https://'.$host.':'.$d->{'web_sslport'}.'/',
	        'days' => 7,
		'mismatch' => $tmpl->{'statussslcert'} == 2 ? 1 : 0,
		'nosched' => 0,
		'alarm' => $tmpl->{'statustimeout'},
		'tmpl' => $tmpl->{'statustmpl'},
		'virtualmin' => $d->{'id'},
	      };
return $serv;
}

# monitor_email(&domain)
# Returns the addresses to send email to for a monitor
sub monitor_email
{
local ($d) = @_;
local $tmpl = &get_template($d->{'template'});
local @rv;
if ($tmpl->{'status'} ne 'none') {
	push(@rv, $tmpl->{'status'});
	}
if (!$tmpl->{'statusonly'}) {
	push(@rv, &extract_address_parts($d->{'emailto'}));
	}
return join(",", @rv);
}

# modify_status(&domain, &olddomain)
# Possible update the hostname of the web server
sub modify_status
{
my ($d, $oldd) = @_;
&require_status();

if ($d->{'dom'} ne $oldd->{'dom'} ||
    $d->{'emailto'} ne $oldd->{'emailto'}) {
	# Update HTTP monitor
	&$first_print($text{'save_status'});
	local $serv = &status::get_service($d->{'id'}."_web");
	local $host = &get_domain_http_hostname($d);
	if ($serv) {
		$serv->{'host'} = $host;
		$serv->{'desc'} = "Website $host";
		$serv->{'email'} = &monitor_email($d);
		&status::save_service($serv);
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'delete_nostatus'});
		}

	if (&domain_has_ssl_cert($d)) {
		# Update cert monitor
		local $certserv = &status::get_service($d->{'id'}."_sslcert");
		if ($certserv) {
			&$first_print($text{'save_statussslcert'});
			$certserv->{'url'} =
				'https://'.$host.':'.$d->{'web_sslport'}.'/',
			$certserv->{'desc'} = "SSL cert $host";
			$certserv->{'email'} = $d->{'emailto'};
			&status::save_service($certserv);
			&$second_print($text{'setup_done'});
			}
		}

	if (&domain_has_ssl($d)) {
		# Update HTTPS monitor
		&$first_print($text{'save_statusssl'});
		local $serv = &status::get_service($d->{'id'}."_ssl");
		if ($serv) {
			$serv->{'host'} = $host;
			$serv->{'desc'} = "Website $host (SSL)";
			$serv->{'email'} = $d->{'emailto'};
			&status::save_service($serv);
			&$second_print($text{'setup_done'});
			}
		else {
			&$second_print($text{'delete_nostatus'});
			}
		}
	}

if (&domain_has_ssl($d) && !&domain_has_ssl($oldd)) {
	# Turned on SSL .. add monitor
	&$first_print($text{'setup_status'});
	local $serv = &make_monitor($d, 1);
	&status::save_service($serv);
	&$second_print($text{'setup_done'});
	}
elsif (!&domain_has_ssl($d) && &domain_has_ssl($oldd)) {
	# Turned off SSL .. remove monitor (but not the cert monitor)
	&$first_print($text{'delete_statusssl'});
	local $serv = &status::get_service($d->{'id'}."_ssl");
	if ($serv) {
		&status::delete_service($serv);
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'delete_nostatus'});
		}
	}

if (&domain_has_ssl_cert($d) && !&domain_has_ssl_cert($oldd)) {
	# Added a cert ... add monitor
	&$first_print($text{'setup_status'});
	local $certserv = &make_sslcert_monitor($d);
	&status::save_service($certserv);
	&$second_print($text{'setup_done'});
	}
}

# delete_status(&domain)
# Just delete the status monitor for this domain
sub delete_status
{
my ($d) = @_;

# Remove HTTP status monitor
&$first_print($text{'delete_status'});
&require_status();
local $serv = &status::get_service($d->{'id'}."_web");
if ($serv) {
	&status::delete_service($serv);
	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'delete_nostatus'});
	}

if (&domain_has_ssl($d)) {
	# Remove HTTPS status monitor
	&$first_print($text{'delete_statusssl'});
	local $serv = &status::get_service($d->{'id'}."_ssl");
	if ($serv) {
		&status::delete_service($serv);
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'delete_nostatus'});
		}
	}

if (&domain_has_ssl_cert($d)) {
	# Remove SSL cert monitor
	&$first_print($text{'delete_statussslcert'});
	local $certserv = &status::get_service($d->{'id'}."_sslcert");
	if ($certserv) {
		&status::delete_service($certserv);
		}
	&$second_print($text{'setup_done'});
	}
return 1;
}

# validate_status(&domain)
# Check for the required monitors
sub validate_status
{
local ($d) = @_;
&require_status();
local $serv = &status::get_service($_[0]->{'id'}."_web");
return &text('validate_estatusweb') if (!$serv);
if (&domain_has_ssl($d)) {
	local $serv = &status::get_service($_[0]->{'id'}."_ssl");
	return &text('validate_estatusssl') if (!$serv);
	}
return undef;
}

# disable_status(&domain)
# Turns off the status monitor for this domain
sub disable_status
{
# Disable HTTP status monitor
&$first_print($text{'disable_status'});
&require_status();
local $serv = &status::get_service($_[0]->{'id'}."_web");
if ($serv) {
	$serv->{'nosched'} = 1;
	&status::save_service($serv);
	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'delete_nostatus'});
	}

# Disable HTTPS status monitor
if (domain_has_ssl($_[0])) {
	&$first_print($text{'disable_statusssl'});
	local $certserv = &status::get_service($_[0]->{'id'}."_sslcert");
	if ($certserv) {
		$certserv->{'nosched'} = 1;
		&status::save_service($certserv);
		}
	local $serv = &status::get_service($_[0]->{'id'}."_ssl");
	if ($serv) {
		$serv->{'nosched'} = 1;
		&status::save_service($serv);
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'delete_nostatus'});
		}
	}
return 1;
}

# enable_status(&domain)
# Turns on the status monitor for this domain
sub enable_status
{
# Enable HTTP status monitor
&$first_print($text{'enable_status'});
&require_status();
local $serv = &status::get_service($_[0]->{'id'}."_web");
if ($serv) {
	$serv->{'nosched'} = 0;
	&status::save_service($serv);
	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'delete_nostatus'});
	}

# Disable HTTPS status monitor
if (&domain_has_ssl($_[0])) {
	&$first_print($text{'enable_statusssl'});
	local $certserv = &status::get_service($_[0]->{'id'}."_sslcert");
	if ($certserv) {
		$certserv->{'nosched'} = 0;
		&status::save_service($certserv);
		}
	local $serv = &status::get_service($_[0]->{'id'}."_ssl");
	if ($serv) {
		$serv->{'nosched'} = 0;
		&status::save_service($serv);
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'delete_nostatus'});
		}
	}
return 1;
}

# show_template_status(&tmpl)
# Outputs HTML for editing status monitoring related template options
sub show_template_status
{
local ($tmpl) = @_;
&require_status();

local @status_fields = ( "status", "statusonly", "statustimeout",
			 "statustimeout_def", "statussslcert", "statustmpl" );
print &ui_table_row(
	&hlink($text{'tmpl_status'}, "template_status"),
	&none_def_input("status", $tmpl->{'status'},
			$text{'tmpl_statusemail'}, 0, 0, undef,
			\@status_fields, 1)."\n".
	&ui_textbox("status", $tmpl->{'status'} eq "none" ? undef :
				$tmpl->{'status'}, 50));

# Send email to server owner
print &ui_table_row(
	&hlink($text{'tmpl_statusonly'}, "template_statusonly"),
	&ui_radio("statusonly", int($tmpl->{'statusonly'}),
		  [ [ 0, $text{'yes'} ], [ 1, $text{'no'} ] ]));

# Default HTTP check timeout
print &ui_table_row(
	&hlink($text{'tmpl_statustimeout'}, "template_statustimeout"),
	&ui_opt_textbox("statustimeout", $tmpl->{'statustimeout'},
			5, &text('tmpl_statustimeoutdef', 10)));

# Check SSL cert too
print &ui_table_row(
        &hlink($text{'tmpl_statussslcert'}, "template_statussslcert"),
	&ui_radio("statussslcert", $tmpl->{'statussslcert'},
		  [ [ 0, $text{'no'} ],
		    [ 1, $text{'tmpl_statussslcert1'} ],
		    [ 2, $text{'tmpl_statussslcert2'} ] ]));

# Default email template
local @stmpls = &status::list_templates();
print &ui_table_row(
	&hlink($text{'tmpl_statustmpl'}, "template_statustmpl"),
	&ui_select("statustmpl", $tmpl->{'statustmpl'},
		   [ [ '', "&lt;$status::text{'mon_notmpl'}&gt;" ],
		     map { [ $_->{'id'}, $_->{'desc'} ] } @stmpls ]));
}

# parse_template_status(&tmpl)
# Updates status monitoring related template options from %in
sub parse_template_status
{
local ($tmpl) = @_;

# Save status monitoring settings
$tmpl->{'status'} = &parse_none_def("status");
if ($in{'status_mode'} != 1) {
	if ($in{'status_mode'} == 2) {
		$in{'status'} =~ /\S/ || &error($text{'tmpl_estatus'});
		}
	$tmpl->{'statusonly'} = $in{'statusonly'};
	$in{'statustimeout_def'} || $in{'statustimeout'} =~ /^\d+$/ ||
		&error($text{'tmpl_estatustimeout'});
	$tmpl->{'statustimeout'} = $in{'statustimeout_def'} ? undef :
					$in{'statustimeout'};
	if (defined($in{'statustmpl'})) {
		$tmpl->{'statustmpl'} = $in{'statustmpl'};
		}
	$tmpl->{'statussslcert'} = $in{'statussslcert'};
	}
}

$done_feature_script{'status'} = 1;

1;

