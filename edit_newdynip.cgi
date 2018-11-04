#!/usr/local/bin/perl
# Show a page for setting up dynamic IP updating (via dyndns, etc..)

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newdynip_ecannot'});
&ui_print_header(undef, $text{'newdynip_title'}, "", "dynip");

print "$text{'newdynip_desc'}<p>\n";
print &ui_form_start("save_newdynip.cgi", "post");
print &ui_table_start($text{'newdynip_header'}, undef, 2);

# Is regular update enabled?
$job = &find_cron_script($dynip_cron_cmd);
print &ui_table_row($text{'newdynip_enabled'},
	&ui_yesno_radio("enabled", $job ? 1 : 0));

# Service to use
print &ui_table_row($text{'newdynip_service'},
	&ui_select("service", $config{'dynip_service'},
		   [ map { [ $_->{'name'}, $_->{'desc'} ] }
			 &list_dynip_services() ],
		   1, 0, 0, 0,
		   "onChange='form.external.disabled = value != \"external\"'")." ".
	&ui_textbox("external", $config{'dynip_external'}, 50,
		    $config{'dynip_service'} ne 'external'));

# Hostname to update
print &ui_table_row($text{'newdynip_host'},
	&ui_textbox("host", $config{'dynip_host'}, 40));

# Work out IP automatically?
print &ui_table_row($text{'newdynip_auto'},
	&ui_radio("auto", int($config{'dynip_auto'}),
		  [ [ 0, $text{'newdynip_auto0'} ],
		    [ 1, $text{'newdynip_auto1'} ] ]));

# Login and password
print &ui_table_row($text{'newdynip_user'},
	&ui_textbox("duser", $config{'dynip_user'}, 20));
print &ui_table_row($text{'newdynip_pass'},
	&ui_textbox("dpass", $config{'dynip_pass'}, 20));

# Email address to notify
print &ui_table_row($text{'newdynip_notify'},
	&ui_opt_textbox("email", $config{'dynip_email'}, 40,
			$text{'newdynip_none'}));

# Current settings
print &ui_table_hr();

if ($config{'dynip_service'}) {
	# Last updated IP
	$ip = &get_last_dynip_update($config{'dynip_service'});
	print &ui_table_row($text{'newdynip_last'},
			    $ip ? "<tt>$ip</tt>"
				: "<i>$text{'newdynip_never'}</i>");
	}

# Primary interface IP
print &ui_table_row($text{'newdynip_iface'},
		    "<tt>".&get_default_ip()."</tt>");

# External IP
print &ui_table_row($text{'newdynip_external'},
		    "<tt>".&get_external_ip_address()."</tt>");

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'newdynip_ok'} ] ]);

&ui_print_footer("", $text{'index_return'});

