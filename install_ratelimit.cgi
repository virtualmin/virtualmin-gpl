#!/usr/local/bin/perl
# Attempt to install email ratelimiting package

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'ratelimit_ecannot'});

&ui_print_header(undef, $text{'ratelimit_title4'}, "");

$cfile = &get_ratelimit_config_file();
$before = -e $cfile;

print &text('ratelimit_installing'),"<br>\n";
&$indent_print();
$ok = &install_ratelimit_package();
&$outdent_print();
print $ok ? $text{'ratelimit_installed'}
	  : $text{'ratelimit_installfailed'},"<p>\n";

# If config didn't exist before, remove any list and racl lines
# to disable default greylisting
if (!$before || 1) {
	print &text('ratelimit_clearing'),"<br>\n";
	$conf = &get_ratelimit_config();
	@copy = @$conf;		# Make a copy because deleting changes $conf
	foreach my $c (@copy) {
		if ($c->{'name'} eq 'list' ||
		    $c->{'name'} eq 'racl' && $c->{'values'}->[1] ne 'default') {
			&save_ratelimit_directive($conf, $c, undef);
			}
		}
	($nospf) = grep { $_->{'name'} eq 'nospf' } @$conf;
	if (!$nospf) {
		&save_ratelimit_directive($conf, undef,
			{ 'name' => 'nospf',
			  'values' => [] });
		}
	&flush_file_lines();
	&apply_ratelimit_config();
	print $text{'setup_done'},"<p>\n";
	}

&ui_print_footer("ratelimit.cgi", $text{'ratelimit_return'});
