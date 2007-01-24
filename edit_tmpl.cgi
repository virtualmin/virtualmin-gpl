#!/usr/local/bin/perl
# Show one template for editing

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newtmpl_ecannot'});
&ReadParse();

@tmpls = &list_templates();
if ($in{'new'}) {
	if ($in{'clone'}) {
		# Start with template we are cloning
		($tmpl) = grep { $_->{'id'} == $in{'clone'} } @tmpls;
		$tmpl || &error("Failed to find template with ID $in{'clone'} to clone");
		$tmpl->{'name'} .= " (Clone)";
		&ui_print_header(undef, $text{'tmpl_title3'}, "", "tmpls");
		}
	else {
		&ui_print_header(undef, $text{'tmpl_title1'}, "", "tmpls");
		}
	}
else {
	($tmpl) = grep { $_->{'id'} == $in{'id'} } @tmpls;
	$tmpl || &error("Failed to find template with ID $in{'id'}");
	&ui_print_header($tmpl->{'name'}, $text{'tmpl_title2'}, "", "tmpls");
	}

# Show section selector form
$in{'editmode'} ||= 'basic';
if (!$in{'new'}) {
	# Can only edit basic settings for new template!
	print &ui_form_start("edit_tmpl.cgi");
	print &ui_hidden("id", $in{'id'}),"\n";
	print &ui_hidden("new", $in{'new'}),"\n";
	print $text{'tmpl_editmode'},"\n";
	%isfeature = map { $_, 1 } @features;
	print &ui_select("editmode", $in{'editmode'},
		 [ map { [ $_, $text{'feature_'.$_} ||
			       $text{'tmpl_editmode_'.$_} ] }
		       &list_template_editmodes() ],
		 1, 0, 0, 0, "onChange='form.submit()'" );
	print &ui_submit($text{'tmpl_switch'});
	print &ui_form_end();
	}

print &ui_form_start("save_tmpl.cgi", "post");
print &ui_hidden("id", $in{'id'}),"\n";
print &ui_hidden("new", $in{'new'}),"\n";
print &ui_hidden("cloneof", $in{'clone'}),"\n";
print &ui_hidden("editmode", $in{'editmode'}),"\n";
$emode = $text{'feature_'.$in{'editmode'}} ||
	 $text{'tmpl_editmode_'.$in{'editmode'}};
print &ui_table_start($text{'tmpl_header'}." (".$emode.")", "100%", 2);

# Show selected options type
$sfunc = "show_template_".$in{'editmode'};
&$sfunc($tmpl);

print &ui_table_end();

# Buttons to save, create or delete
print &ui_form_end([
	[ "save", $in{'new'} ? $text{'create'} : $text{'save'} ],
	[ "next", $in{'new'} ? $text{'tmpl_cnext'} : $text{'tmpl_snext'} ],
	$in{'new'} || $tmpl->{'default'} ? ( ) :
		( [ "clone", $text{'tmpl_clone'} ] ),
	!$in{'new'} && !$tmpl->{'standard'} ?
		( [ "delete", $text{'delete'} ] ) : ( ),
	]);

&ui_print_footer("edit_newtmpl.cgi", $text{'newtmpl_return'},
		 "", $text{'index_return'});

# none_def_input(name, value, final-option, no-none, no-default, none-text)
sub none_def_input
{
local $rv;
local $mode = $_[1] eq "none" ? 0 :
	      $_[1] eq "" ? 1 : 2;
local @opts;
push(@opts, 0) if (!$_[3]);
push(@opts, 1) if (!$tmpl->{'default'} && !$_[4]);
push(@opts, 2);
if (@opts > 1) {
	local $m;
	foreach $m (@opts) {
		$rv .= &ui_oneradio("$_[0]_mode", $m,
			$m == 0 ? ($_[5] || $text{'newtmpl_none'}) :
			$m == 1 ? $text{'default'} : $_[2], $mode == $m)."\n";
		}
	}
else {
	$rv .= &ui_hidden("$_[0]_mode", $opts[0])."\n";
	}
return $rv;
}


