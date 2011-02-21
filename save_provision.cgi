#!/usr/bin/perl
# Save provisioning settings

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'provision_ecannot'});
&error_setup($text{'provision_err'});
&ReadParse();
%oldconfig = %config;

# Validate and store inputs
foreach $f (&list_provision_features()) {
	push(@oldpfeatures, $f) if ($config{'provision_'.$f});
	push(@pfeatures, $f) if ($in{'provision_'.$f});
	}
if ($in{'provision_cloudmin'}) {
	# Use Virtualmin's provisioning service
	$in{'provision_server'} = $cloudmin_provisioning_server;
	$in{'provision_port'} = $cloudmin_provisioning_port;
	$in{'provision_ssl'} = $cloudmin_provisioning_ssl;
	}
if (@pfeatures) {
	&to_ipaddress($in{'provision_server'}) ||
	  defined(&to_ip6address) && &to_ip6address($in{'provision_server'}) ||
	     &error($text{'provision_eserver'});
	$in{'provision_port'} =~ /^[1-9][0-9]*$/ ||
	     &error($text{'provision_eport'});
	$in{'provision_user'} =~ /^[a-zA-Z0-9\.\-\_\@]+$/ ||
	     &error($text{'provision_euser'});
	$in{'provision_pass'} =~ /:/ &&
	     &error($text{'provision_epass'});
	}
$config{'provision_server'} = $in{'provision_server'};
$config{'provision_port'} = $in{'provision_port'};
$config{'provision_ssl'} = $in{'provision_ssl'} || 0;
$config{'provision_user'} = $in{'provision_user'};
$config{'provision_pass'} = $in{'provision_pass'};
foreach $f (&list_provision_features()) {
	$config{'provision_'.$f} = $in{'provision_'.$f} || 0;
	}

&ui_print_header(undef, $text{'provision_title'}, "");

# Check that provisioning works for the server and login
&$first_print(&text('provision_checking', "<tt>$in{'provision_server'}</tt>"));
$err = &check_provision_login();
if ($err) {
	&$second_print(&text('provision_echeck', $err));
	goto FAILED;
	}
else {
	&$second_print($text{'setup_done'});
	}

# If any domains exist that were provisioned old-style for mysql, complain
if ($in{'provision_mysql'} && !$oldconfig{'provision_mysql'}) {
	&$first_print($text{'provision_mysqlcheck'});
	@mydoms = grep { $_->{'mysql'} && !$_->{'provision_mysql'} }
		       &list_domains();
	if (@mydoms && $in{'override'}) {
		# Some exist, but override mode is on
		&$second_print($text{'provision_mysqlcheckskip'});
		}
	elsif (@mydoms) {
		# Some exist .. show error and override button
		&$second_print(&text('provision_mysqlcheckfail',
			join(" ", map { $_->{'dom'} } @mydoms)));

		print &ui_form_start("save_provision.cgi");
		foreach $i (keys %in) {
			print &ui_hidden($i, $in{$i});
			}
		print "<b>",$text{'provision_mysqlcheckoverride'},"</b><p>\n";
		print &ui_form_end([ [ "override",
				       $text{'provision_override'} ] ]);
		goto FAILED;
		}
	else {
		&$second_print($text{'provision_mysqlcheckok'});
		}
	}

# Get limits from the server and display
&$first_print(&text('provision_limits'));
($ok, $feats) = &provision_api_call("list-provision-features", {}, 1);
use Data::Dumper;
foreach $f (@$feats) {
	$v = $f->{'values'};
	push(@lmsgs, &text('provision_limit',
			   $v->{'limit'}->[0], $v->{'description'}->[0]).
		     ($v->{'usage'}->[0] ? " ".&text('provision_used',
						     $v->{'usage'}->[0]) : ""));
	}
&$second_print(&text('provision_limitsgot', join(', ', @lmsgs)));

# Save config and tell the user
&$first_print($text{'provision_saving'});
&save_module_config();
&$second_print($text{'setup_done'});

FAILED:
&ui_print_footer("", $text{'index_return'});

