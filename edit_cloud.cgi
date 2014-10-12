#!/usr/local/bin/perl
# Edit settings for one provider

require './virtual-server-lib.pl';
&ReadParse();
&can_cloud_providers() || &error($text{'clouds_ecannot'});

&ui_print_header(undef, $text{'cloud_title'}, "");

@provs = &list_cloud_providers();
($prov) = grep { $_->{'name'} eq $in{'name'} } @provs;
$prov || &error($text{'cloud_egone'});

print &ui_form_start("save_cloud.cgi", "post");
print &ui_hidden("name", $in{'name'});
print &ui_table_start($text{'cloud_header'}, undef, 2);

# Cloud provider name
print &ui_table_row($text{'cloud_provider'},
		    $prov->{'desc'});

# Provider options
$ifunc = "cloud_".$prov->{'name'}."_show_inputs";
print &$ifunc($prov);

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
print &ui_form_end([ [ undef, $text{'save'} ] ]);

&ui_print_footer("list_clouds.cgi", $text{'clouds_return'});
