#!/usr/bin/perl
# Show rate limiting enable / disable form

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'ratelimit_ecannot'});
&ui_print_header(undef, $text{'ratelimit_title'}, "", "ratelimit");
&ReadParse();

# Check if can use
$err = &check_ratelimit();
if ($err) {
	print &text('ratelimit_failed', $err),"<p>\n";
	if (&can_install_ratelimit()) {
		print &ui_form_start("install_ratelimit.cgi");
		print &text('ratelimit_installdesc'),"<p>\n";
		print &ui_form_end([ [ undef, $text{'dkim_install'} ] ]);
		}
	&ui_print_footer("", $text{'index_return'});
	return;
	}

# If installed, check if version is usable
$ver = &get_milter_greylist_version();
if (&compare_versions($ver, "4.3.7") < 0) {
	print &text('ratelimit_badversion', $ver, "4.3.7"),"<p>\n";
	&ui_print_footer("", $text{'index_return'});
	return;
	}

# Show form to enable
print &ui_form_start("save_ratelimit.cgi");
print &ui_table_start($text{'ratelimit_header'}, undef, 2);

# Enabled?
print &ui_table_row($text{'ratelimit_enabled'},
	&ui_yesno_radio("enable", &is_ratelimit_enabled()));

# Max messages / hour for all domains
$conf = &get_ratelimit_config();
($rl) = grep { $_->{'name'} eq 'ratelimit' &&
	       $_->{'values'}->[0] eq 'virtualmin_limit' } @$conf;
print &ui_table_row($text{'ratelimit_max'},
	&ui_radio("max_def", $rl ? 0 : 1,
		  [ [ 1, $text{'form_unlimit'} ],
		    [ 0, &ratelimit_field("max", $rl) ] ]));

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});

# ratelimit_field(name, &ratelimit-object)
# Return HTML for a field for selecting a rate and time
sub ratelimit_field
{
my ($name, $rl) = @_;
my ($num, $time, $units);
if ($rl) {
	$num = $rl->{'values'}->[2];
	$time = $rl->{'values'}->[4];
	if ($time =~ s/([smhdwy])$//) {
		$units = $1;
		}
	else {
		$units = "s";
		}
	}
else {
	$time = 1;
	$units = "h";
	}
return &text('ratelimit_per',
	     &ui_textbox($name."_num", $num, 5),
	     &ui_textbox($name."_time", $time, 5),
	     &ui_select($name."_units", $units,
			[ map { [ $_, $text{'ratelimit_'.$_} ] }
			      ('s', 'm', 'h', 'd', 'w', 'y') ]));
}
