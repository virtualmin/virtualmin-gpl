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
$dynip_service = $config{'dynip_service'} || 'dyndns';
$show_external = $dynip_service =~ /^(external|webmin)$/;
$show_server = $dynip_service eq 'dyndns';
$external_input = &ui_textbox("external", $config{'dynip_external'}, 30,
			     !$show_external);
$server_input = &ui_textbox("server",
			   $config{'dynip_server'} || "members.dyndns.org",
			   30, !$show_server);
print &ui_table_row(&hlink($text{'newdynip_service'}, "newdynip_service"),
	&ui_select("service", $dynip_service,
		   [ map { [ $_->{'name'}, $_->{'desc'} ] }
			 &list_dynip_services() ],
		   1, 0, 0, 0,
		   "onChange='sync_dynip_service_fields()'")." ".
	"<span id='dynip_external_input'".
		($show_external ? "" : " hidden style='display: none !important'").">".
		$external_input."</span>".
	"<span id='dynip_server_input'".
		($show_server ? "" : " hidden style='display: none !important'").">".
		$server_input."</span>");

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

# Update all domains on IP change?
print &ui_table_row($text{'newdynip_update'},
	&ui_yesno_radio("update", $config{'dynip_update'}));

# Current state
print &ui_table_hr();

if ($config{'dynip_service'}) {
	# Last updated IP
	$ip = &get_last_dynip_update($config{'dynip_service'});
	print &ui_table_row($text{'newdynip_last'},
			    $ip ? "<tt>$ip</tt>"
				: "<i>$text{'newdynip_never'}</i>");
	}

# Primary interface IPv4
print &ui_table_row($text{'newdynip_iface'},
		    "<tt>".&get_default_ip()."</tt>");

# Primary interface IPv6
if (!&supports_ip6()) {
	# Not supported
	print &ui_table_row($text{'edit_ip6'},
			    "<i>$text{'edit_noip6support'}</i>");
	}
else {
	# Supported
	my $ip6 = &get_default_ip6();
	print &ui_table_row($text{'newdynip_iface6'},
			    $ip6 ? "<tt>$ip6</tt>"
				: "<i>$text{'newdynip_none'}</i>");
	}

# External IPv4
my $eip4 = &get_external_ip_address(0, 4);
	print &ui_table_row($text{'newdynip_external'},
			    $eip4
				? "<tt>$eip4</tt>"
				: "⚠ ".$text{'newdynip_eext'});

# External IPv6
if (!&supports_ip6()) {
	# Not supported
	print &ui_table_row($text{'edit_ip6'},
			    "<i>$text{'edit_noip6support'}</i>");
	}
else {
	# Supported
	my $eip6 = &get_external_ip_address(0, 6);
	print &ui_table_row($text{'newdynip_external6'},
			    $eip6
				? "<tt>$eip6</tt>"
				: "⚠ ".$text{'newdynip_eext6'});
	}

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'newdynip_ok'} ] ]);

# Show only the input used by the selected dynamic DNS service
print <<'EOF';
<script type='text/javascript'>
function sync_dynip_service_fields()
{
var service = document.querySelector('[name="service"]');
var external = document.querySelector('[name="external"]');
var server = document.querySelector('[name="server"]');
var external_span = document.getElementById('dynip_external_input');
var server_span = document.getElementById('dynip_server_input');
if (!service) {
	return;
	}
var show_external = service.value == 'external' || service.value == 'webmin';
var show_server = service.value == 'dyndns';

if (external) {
	external.disabled = !show_external;
	}
if (external_span) {
	external_span.hidden = !show_external;
	external_span.style.setProperty('display', show_external ? '' : 'none',
		show_external ? '' : 'important');
	}
if (server) {
	server.disabled = !show_server;
	}
if (server_span) {
	server_span.hidden = !show_server;
	server_span.style.setProperty('display', show_server ? '' : 'none',
		show_server ? '' : 'important');
	}
}
sync_dynip_service_fields();
window.addEventListener('pageshow', sync_dynip_service_fields);
</script>
EOF

&ui_print_footer("", $text{'index_return'});
