#!/usr/local/bin/perl
# Show one template for editing

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newtmpl_ecannot'});
&ReadParse();

@tmpls = &list_templates();
@hargs = ( 0, 0, undef, undef, undef,
	   &virtualmin_ui_apply_radios("onLoad") );
if ($in{'new'}) {
	if ($in{'clone'}) {
		# Start with template we are cloning
		($tmpl) = grep { $_->{'id'} == $in{'clone'} } @tmpls;
		$tmpl || &error("Failed to find template with ID $in{'clone'} to clone");
		$tmpl->{'name'} .= " (Clone)";
		$tmpl->{'standard'} = 0;
		&ui_print_header(undef, $text{'tmpl_title3'}, "", "tmpls",
			 	 @hargs);
		}
	else {
		&ui_print_header(undef, $text{'tmpl_title1'}, "", "tmpls",
			 	 @hargs);
		}
	}
else {
	($tmpl) = grep { $_->{'id'} == $in{'id'} } @tmpls;
	$tmpl || &error("Failed to find template with ID $in{'id'}");
	&ui_print_header($tmpl->{'name'}, $text{'tmpl_title2'}, "", "tmpls",
			 @hargs);
	}

# Show section selector form
$in{'editmode'} ||= 'basic';
if (!$in{'new'}) {
	# Work out template section to edit
	@editmodes = &list_template_editmodes();
	$idx = &indexof($in{'editmode'}, @editmodes);
	if ($in{'nprev'}) {
		$idx--;
		$idx = @editmodes-1 if ($idx < 0);
		}
	elsif ($in{'nnext'}) {
		$idx++;
		$idx = 0 if ($idx >= @editmodes);
		}
	$in{'editmode'} = $editmodes[$idx];

	# Can only edit basic settings for new template!
	print &ui_form_start("edit_tmpl.cgi");
	print &ui_hidden("id", $in{'id'}),"\n";
	print &ui_hidden("new", $in{'new'}),"\n";
	print $text{'tmpl_editmode'},"\n";
	%isfeature = map { $_, 1 } @features;
	print &ui_select("editmode", $in{'editmode'},
		 [ map { [ $_, $text{'feature_'.$_} ||
			       $text{'tmpl_editmode_'.$_} ] }
		       @editmodes ],
		 1, 0, 0, 0, "onChange='form.submit()'" );
	print &ui_submit($text{'tmpl_switch'});
	print "&nbsp;&nbsp;\n";
	print &ui_submit($text{'tmpl_nprev'}, "nprev");
	print &ui_submit($text{'tmpl_nnext'}, "nnext");
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

# none_def_input(name, value, final-option, no-none, no-default, none-text,
#		 &disable-fields)
sub none_def_input
{
local ($name, $value, $final, $nonone, $nodef, $nonemsg, $dis) = @_;
local $rv;
local $mode = $value eq "none" ? 0 :
	      $value eq "" ? 1 : 2;
local @opts;
push(@opts, 0) if (!$nonone);
push(@opts, 1) if (!$tmpl->{'default'} && !$nodef);
push(@opts, 2);
if (@opts > 1) {
	local $m;
	local $dis1 = @$dis ? &js_disable_inputs($dis, [ ]) : undef;
	local $dis2 = @$dis ? &js_disable_inputs([ ], $dis) : undef;
	foreach $m (@opts) {
		local $disn = $m == 2 ? $dis2 : $dis1;
		$rv .= &ui_oneradio($name."_mode", $m,
			$m == 0 ? ($nonemsg || $text{'newtmpl_none'}) :
			$m == 1 ? $text{'tmpl_default'} : $final,
			$mode == $m,
			$disn ? "onClick='$disn'" : "")."\n";
		}
	}
else {
	$rv .= &ui_hidden($name."_mode", $opts[0])."\n";
	}
return $rv;
}


