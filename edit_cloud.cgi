#!/usr/local/bin/perl
# Edit settings for one provider

require './virtual-server-lib.pl';
&ReadParse();
&can_cloud_providers() || &error($text{'clouds_ecannot'});

&ui_print_header(undef, $text{'cloud_title'}, "");

# Lookup the provider
@provs = &list_cloud_providers();
($prov) = grep { $_->{'name'} eq $in{'name'} } @provs;
$prov || &error($text{'cloud_egone'});
$sfunc = "cloud_".$prov->{'name'}."_get_state";
$state = &$sfunc($p);

# First check if provider can be used
my $cfunc = "check_".$prov->{'name'};
my $longdesc = $prov->{'longdesc'};
if (ref($longdesc) eq 'CODE') {
	$longdesc = &$longdesc();
	}
if (defined(&$cfunc)) {
	my ($err, $warn) = &$cfunc();
	if ($err) {
		print &ui_alert_box(
			&text('cloud_echeck', $prov->{'desc'}, $err), 'warn', undef, undef, '');
		if ($longdesc) {
			print &ui_alert_box($longdesc, 'info', undef, undef, '');
			}
		&ui_print_footer("list_clouds.cgi", $text{'clouds_return'});
		return;
		}
	print &ui_alert_box($warn, 'warn') if ($warn);
	}

if ($longdesc) {
	print $longdesc,"<p>\n";
	}

print &ui_form_start("save_cloud.cgi", "post");
print &ui_hidden("name", $in{'name'});
print &ui_table_start($text{'cloud_header'}, undef, 2);

# Cloud provider name
print &ui_table_row($text{'cloud_provider'},
		    $prov->{'desc'});
print &ui_table_row($text{'cloud_url'},
		    &ui_link($prov->{'url'}, $prov->{'url'}, undef,
			     "target=_blank"));

# Provider options
$ifunc = "cloud_".$prov->{'name'}."_show_inputs";
print &$ifunc($prov);

# Allow use by other users?
print &ui_table_row($text{'cloud_useby'},
	&ui_checkbox("useby_reseller", 1, $text{'cloud_byreseller'},
		     $config{'cloud_'.$in{'name'}.'_reseller'})."\n".
	&ui_checkbox("useby_owner", 1, $text{'cloud_byowner'},
		     $config{'cloud_'.$in{'name'}.'_owner'}));

# Current users
@users = grep { &backup_uses_cloud($_, $prov) } &list_scheduled_backups();
if (@users) {
	$utable = &ui_columns_start([ $text{'sched_dest'},
				      $text{'sched_doms'} ], 100);
	foreach my $s (@users) {
		@dests = &get_scheduled_backup_dests($s);
		@nices = map { &nice_backup_url($_, 1) } @dests;
		$utable .= &ui_columns_row([
			&ui_link("backup_form.cgi?sched=$s->{'id'}",
				 join("<br>\n", @nices)),
			&nice_backup_doms($s),
			]);
		}
	$utable .= &ui_columns_end();
	}
else {
	$utable = $text{'cloud_nousers'};
	}
print &ui_table_row($text{'cloud_users'}, $utable);

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'save'} ],
		     $state->{'ok'} && $prov->{'clear'} ?
			( [ 'clear', $text{'cloud_clear'} ] ) : ( ) ]);

&ui_print_footer("list_clouds.cgi", $text{'clouds_return'});
