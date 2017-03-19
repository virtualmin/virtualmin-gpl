#!/usr/local/bin/perl
# Display system cloning form

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});

# Check limits
if ($d->{'parent'} && !&can_create_sub_servers() ||
    !$d->{'parent'} && !&can_create_master_servers()) {
	&error($text{'clone_ecannot'});
	}
($dleft, $dreason, $dmax) = &count_domains(
	$d->{'alias'} ? "aliasdoms" :
	$d->{'parent'} ? "realdoms" : "topdoms");
&error(&text('setup_emax', $dmax)) if ($dleft == 0);

&ui_print_header(&domain_in($d), $text{'clone_title'}, "", "clone");

print $text{'clone_warn'},"<p>\n";
print &ui_form_start("clone.cgi");
print &ui_hidden("dom", $d->{'id'}),"\n";
print &ui_table_start($text{'clone_header'}, undef, 2);

# Domain being cloned
print &ui_table_row($text{'clone_dom'},
	"<tt>".&show_domain_name($d)."</tt>");

# New domain name
print &ui_table_row($text{'clone_newdom'},
	&ui_textbox("newdomain", undef, 40));

# New username and password
if (!$d->{'parent'}) {
	print &ui_table_row($text{'clone_newuser'},
		&ui_textbox("newuser", undef, 20));

	print &ui_table_row($text{'clone_newpass'},
		&ui_radio("newpass_def", 1,
			  [ [ 1, $text{'clone_samepass'} ],
			    [ 0, &ui_password("newpass", undef, 20) ] ]));
	}

# IP address
if ($d->{'virt'} && &can_select_ip()) {
	$tmpl = &get_template($d->{'template'});
	$ipfield = &ui_textbox("ip", undef, 20)." ".
		   &ui_checkbox("virtalready", 1, $text{'form_virtalready'});
	if ($tmpl->{'ranges'} eq 'none') {
		# Must enter an IP
		print &ui_table_row($text{'clone_newip'}, $ipfield);
		}
	else {
		# Can select an IP, or allocate
		print &ui_table_row($text{'clone_newip'},
			&ui_radio("ip_def", 1,
				  [ [ 1, $text{'clone_alloc'}."<br>" ],
				    [ 0, $text{'clone_vip'} ] ]).
			" ".$ipfield);
		}
	}

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'clone_ok'} ] ]);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});
