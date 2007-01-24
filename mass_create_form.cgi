#!/usr/local/bin/perl
# Show a form for creating multiple Virtual servers from a text file.
# This is in the format :
#	domain:owner:pass:[user]:parent-domain
# Features are selected on the form itself

require './virtual-server-lib.pl';
&ReadParse();
&can_create_master_servers() || &can_create_sub_servers() ||
	&error($text{'form_ecannot'});
&ui_print_header(undef, $text{'cmass_title'}, "", "cmass");

print &ui_form_start("mass_create.cgi", "form-data");
print &ui_table_start($text{'cmass_header'}, "width=100%", 2);

# Source file / data
if (&master_admin()) {
	push(@sopts, [ 1, &text('cmass_local',
			   &ui_textbox("local", undef, 40))."<br>" ]);
	}
push(@sopts, [ 0, &text('cmass_upload', &ui_upload("upload", 40))."<br>" ]);
push(@sopts, [ 2, &text('cmass_text', &ui_textarea("text", "", 5, 60))."<br>"]);
print &ui_table_row($text{'cmass_file'},
		    &ui_radio("file_def", 0, \@sopts));

# Templates for parent and sub domains
@ptmpls = &list_available_templates(undef, undef);
print &ui_table_row($text{'cmass_ptmpl'},
	    &ui_select("ptemplate", undef,
		       [ map { [ $_->{'id'}, $_->{'name'} ] } @ptmpls ]));
@stmpls = &list_available_templates({ }, undef);
print &ui_table_row($text{'cmass_stmpl'},
	    &ui_select("stemplate", undef,
		       [ map { [ $_->{'id'}, $_->{'name'} ] } @stmpls ]));

# Owning reseller
@resels = sort { $a->{'name'} cmp $b->{'name'} } &list_resellers();
if (@resels && &master_admin()) {
	print &ui_table_row($text{'cmass_resel'},
		    &ui_select('resel', undef,
			[ [ undef, "&lt;$text{'cmass_none'}&gt;" ],
			  map { [ $_->{'name'} ] } @resels ]));
	}

# Show checkboxes for features
print &ui_table_hr();
print "<tr> <td colspan=2><table width=100%>\n";
$i = 0;
foreach $f (@opt_features) {
	# Don't allow access to features that this user hasn't been
	# granted for his subdomains.
	next if (!&can_use_feature($f));
	$can_feature{$f}++;

	if ($config{$f} == 3) {
		# This feature is always on, so don't show it
		print &ui_hidden($f, 1),"\n";
		next;
		}

	local $txt = $text{'form_'.$f};
	print "<tr>\n" if ($i%2 == 0);
	print "<td>",&ui_checkbox($f, 1, "", $config{$f} == 1, undef,
			  !$config{$f} && defined($config{$f})),"</td>\n";
	print "<td><b>",&hlink($txt, $f),"</b></td>";
	print "</tr>\n" if ($i++%2 == 1);
	}

# Show checkboxes for plugins
foreach $f (@feature_plugins) {
	next if (!&plugin_call($f, "feature_suitable"));
	next if (!&can_use_feature($f));

	print "<tr>\n" if ($i%2 == 0);
	$label = &plugin_call($f, "feature_label", 0);
	print "<td>",&ui_checkbox($f, 1, "", 1),"</td>\n";
	print "<td><b>$label</b></td>\n";
	print "</tr>\n" if ($i++%2 == 1);
	}
print "</table></td> </tr>\n";

print &ui_table_end();
print &ui_form_end([ [ "create", $text{'create'} ] ]);

&ui_print_footer("", $text{'index_return'});
