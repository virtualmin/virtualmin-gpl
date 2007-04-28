# Functions for setting up web status monitoring for a domain

sub require_status
{
return if ($require_status++);
&foreign_require("status", "status-lib.pl");
}

sub check_depends_status
{
if (!$_[0]->{'web'}) {
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
&$first_print($text{'setup_status'});
&require_status();

# Create website monitor
local $serv = &make_monitor($_[0], 0);
&status::save_service($serv);
&$second_print($text{'setup_done'});

if ($_[0]->{'ssl'}) {
	# Add SSL website monitor too
	&$first_print($text{'setup_statusssl'});
	local $serv = &make_monitor($_[0], 1);
	&status::save_service($serv);
	&$second_print($text{'setup_done'});
	}
}

# make_monitor(&domain, ssl)
sub make_monitor
{
local ($d, $ssl) = @_;
local $tmpl = &get_template($d->{'template'});
local $serv = { 'id' => $d->{'id'}.($ssl ? "_ssl" : "_web"),
		'type' => 'http',
		'desc' => $ssl ? "Website www.$d->{'dom'} (SSL)" 
				: "Website www.$d->{'dom'}",
		'fails' => 1,
		'email' => &monitor_email($d),
		'host' => "www.$d->{'dom'}",
		'port' => $ssl ? $d->{'web_sslport'} : $d->{'web_port'},
		'nosched' => 0,
		'ssl' => $ssl,
		'alarm' => $tmpl->{'statustimeout'},
		'page' => '/' };
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
	push(@rv, $d->{'emailto'});
	}
return join(",", @rv);
}

# modify_status(&domain, &olddomain)
# Possible update the hostname of the web server
sub modify_status
{
if ($_[0]->{'dom'} ne $_[1]->{'dom'} ||
    $_[0]->{'emailto'} ne $_[1]->{'emailto'}) {
	# Update HTTP monitor
	&$first_print($text{'save_status'});
	&require_status();
	local $serv = &status::get_service($_[0]->{'id'}."_web");
	if ($serv) {
		$serv->{'host'} = "www.$_[0]->{'dom'}";
		$serv->{'desc'} = "Website www.$_[0]->{'dom'}";
		$serv->{'email'} = &monitor_email($_[0]);
		&status::save_service($serv);
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'delete_nostatus'});
		}

	if ($_[0]->{'ssl'}) {
		# Update HTTPS monitor
		&$first_print($text{'save_statusssl'});
		&require_status();
		local $serv = &status::get_service($_[0]->{'id'}."_ssl");
		if ($serv) {
			$serv->{'host'} = "www.$_[0]->{'dom'}";
			$serv->{'desc'} = "Website www.$_[0]->{'dom'} (SSL)";
			$serv->{'email'} = $_[0]->{'emailto'};
			&status::save_service($serv);
			&$second_print($text{'setup_done'});
			}
		else {
			&$second_print($text{'delete_nostatus'});
			}
		}
	}
if ($_[0]->{'ssl'} && !$_[1]->{'ssl'}) {
	# Turned on SSL .. add monitor
	&require_status();
	&$first_print($text{'setup_status'});
	local $serv = &make_monitor($_[0], 1);
	&status::save_service($serv);
	&$second_print($text{'setup_done'});
	}
elsif (!$_[0]->{'ssl'} && $_[1]->{'ssl'}) {
	# Turned off SSL .. remove monitor
	&require_status();
	&$first_print($text{'delete_statusssl'});
	&require_status();
	local $serv = &status::get_service($_[0]->{'id'}."_ssl");
	if ($serv) {
		&status::delete_service($serv);
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'delete_nostatus'});
		}
	}
}

# delete_status(&domain)
# Just delete the status monitor for this domain
sub delete_status
{
# Remove HTTP status monitor
&$first_print($text{'delete_status'});
&require_status();
local $serv = &status::get_service($_[0]->{'id'}."_web");
if ($serv) {
	&status::delete_service($serv);
	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'delete_nostatus'});
	}

if ($_[0]->{'ssl'}) {
	# Remove HTTPS status monitor
	&$first_print($text{'delete_statusssl'});
	local $serv = &status::get_service($_[0]->{'id'}."_ssl");
	if ($serv) {
		&status::delete_service($serv);
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'delete_nostatus'});
		}
	}
}

# validate_status(&domain)
# Check for the required monitors
sub validate_status
{
local ($d) = @_;
&require_status();
local $serv = &status::get_service($_[0]->{'id'}."_web");
return &text('validate_estatusweb') if (!$serv);
if ($d->{'ssl'}) {
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
if ($_[0]->{'ssl'}) {
	&$first_print($text{'disable_statusssl'});
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
if ($_[0]->{'ssl'}) {
	&$first_print($text{'enable_statusssl'});
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
}

# show_template_status(&tmpl)
# Outputs HTML for editing status monitoring related template options
sub show_template_status
{
local ($tmpl) = @_;

local @status_fields = ( "status", "statusonly", "statustimeout",
			 "statustimeout_def" );
print &ui_table_row(
	&hlink($text{'tmpl_status'}, "template_status"),
	&none_def_input("status", $tmpl->{'status'},
			$text{'tmpl_statusemail'}, 0, 0, undef,
			\@status_fields)."\n".
	&ui_textbox("status", $tmpl->{'status'} eq "none" ? undef :
				$tmpl->{'status'}, 50));

print &ui_table_row(
	&hlink($text{'tmpl_statusonly'}, "template_statusonly"),
	&ui_radio("statusonly", int($tmpl->{'statusonly'}),
		  [ [ 0, $text{'yes'} ], [ 1, $text{'no'} ] ]));

print &ui_table_row(
	&hlink($text{'tmpl_statustimeout'}, "template_statustimeout"),
	&ui_opt_textbox("statustimeout", $tmpl->{'statustimeout'},
			5, &text('tmpl_statustimeoutdef', 10)));
}

# parse_template_status(&tmpl)
# Updates status monitoring related template options from %in
sub parse_template_status
{
local ($tmpl) = @_;

# Save status monitoring settings
$tmpl->{'status'} = &parse_none_def("status");
if ($in{'status_mode'} == 2) {
	$in{'status'} =~ /\S/ || &error($text{'tmpl_estatus'});
	$tmpl->{'statusonly'} = $in{'statusonly'};
	$in{'statustimeout_def'} || $in{'statustimeout'} =~ /^\d+$/ ||
		&error($text{'tmpl_estatustimeout'});
	$tmpl->{'statustimeout'} = $in{'statustimeout_def'} ? undef :
					$in{'statustimeout'};
	}
}

$done_feature_script{'status'} = 1;

1;

