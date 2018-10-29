#!/usr/local/bin/perl
# Show a form for creating multiple Virtual servers from a text file.
# This is in the format :
#	domain:owner:pass:[user]:parent-domain
# Features are selected on the form itself

require './virtual-server-lib.pl';
&ReadParse();
&can_create_master_servers() || &can_create_sub_servers() ||
	&error($text{'form_ecannot'});
&can_create_batch() || &error($text{'cmass_ecannot'});
&ui_print_header(undef, $text{'cmass_title'}, "", "cmass");

print $text{'cmass_help'};
print "<br><tt>$text{'cmass_format'}</tt><p>";

@tds = ( "width=30%" );
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
		    &ui_radio("file_def", 0, \@sopts), 1, \@tds);

# Separator character
print &ui_table_row($text{'umass_separator'},
		    &ui_radio("separator", ":",
			      [ [ ":", $text{'umass_separatorcolon'} ],
				[ ",", $text{'umass_separatorcomma'} ],
				[ "tab", $text{'umass_separatortab'} ] ]));

# Templates for parent and sub domains
@ptmpls = &list_available_templates(undef, undef);
if (&can_create_master_servers()) {
	print &ui_table_row($text{'cmass_ptmpl'},
		    &ui_select("ptemplate", &get_init_template(0),
			       [ map { [ $_->{'id'}, $_->{'name'} ] }@ptmpls ]),
		    1, \@tds);
	}
@stmpls = &list_available_templates({ }, undef);
print &ui_table_row($text{'cmass_stmpl'},
	    &ui_select("stemplate", &get_init_template(1),
		       [ map { [ $_->{'id'}, $_->{'name'} ] } @stmpls ]),
	    1, \@tds);

# Plan for parent domains
@plans = sort { $a->{'name'} cmp $b->{'name'} } &list_available_plans();
if (&can_create_master_servers() && @plans) {
	print &ui_table_row($text{'cmass_plan'},
		&ui_select("plan", $defplan->{'id'},
			   [ map { [ $_->{'id'}, $_->{'name'} ] } @plans ]));
	}

# Owning reseller
if (defined(&list_resellers)) {
	@resels = sort { $a->{'name'} cmp $b->{'name'} } &list_resellers();
	}
if (@resels && &master_admin()) {
	print &ui_table_row($text{'cmass_resel'},
		    &ui_select('resel', undef,
			[ [ undef, "&lt;$text{'cmass_none'}&gt;" ],
			  map { [ $_->{'name'} ] } @resels ]),
	    	    1, \@tds);
	}

# Show checkboxes for features
print &ui_table_hr();
@grid = ( );
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
	push(@grid, &ui_checkbox($f, 1, "", $config{$f} == 1, undef,
			  !$config{$f} && defined($config{$f}))." ".
		    "<b>".&hlink($txt, $f)."</b>");
	}

# Show checkboxes for plugins
%inactive = map { $_, 1 } split(/\s+/, $config{'plugins_inactive'});
foreach $f (&list_feature_plugins()) {
	next if (!&plugin_call($f, "feature_suitable"));
	next if (!&can_use_feature($f));

	$label = &plugin_call($f, "feature_label", 0);
	$hlink = &plugin_call($f, "feature_hlink");
	$label = &hlink($label, $hlink, $f) if ($hlink);
	push(@grid, &ui_checkbox($f, 1, "", !$inactive{$f})." ".
		    "<b>$label</b>");
	}
$ftable = &ui_grid_table(\@grid, 2, 100,
	[ "width=30% align=left", "width=70% align=left" ]);
print &ui_table_row(undef, $ftable, 2);

print &ui_table_end();
print &ui_form_end([ [ "create", $text{'create'} ] ]);

&ui_print_footer("", $text{'index_return'});
