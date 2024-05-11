#!/usr/local/bin/perl
# Run the script's install dependencies functions

require './virtual-server-lib.pl';
&ReadParse();
my $d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_scripts() || &error($text{'edit_ecannot'});

# Get the script being started
my @got = &list_domain_scripts($d);
my ($sinfo) = grep { $_->{'id'} eq $in{'script'} } @got;
$sinfo || &error($text{'stopscript_egone'});
my $script = &get_script($sinfo->{'name'});
$script || &error($text{'stopscript_egone'});

# Work out PHP version for this domain/directory
my $phpver = &get_domain_php_version_for_directory($d, $sinfo->{'opts'}->{'dir'});

# Print the header and starting message
&ui_print_unbuffered_header(&domain_in($d), $text{'scripts_rdepstitle'}, "");
&$first_print(&text('scripts_reinstallingdeps', $script->{'desc'}));
&$indent_print();

# Run the install dependencies functions
if ($phpver) {
        &setup_php_modules($d, $script, $sinfo->{'version'}, $phpver, $sinfo->{'opts'});
        &setup_pear_modules($d, $script, $sinfo->{'version'}, $phpver, $sinfo->{'opts'});
        }
&setup_perl_modules($d, $script, $sinfo->{'version'}, $sinfo->{'opts'});
&setup_ruby_modules($d, $script, $sinfo->{'version'}, $sinfo->{'opts'});
&setup_python_modules($d, $script, $sinfo->{'version'}, $sinfo->{'opts'});

# Done
&$outdent_print();
&$second_print($text{'setup_done'});

# Run post-actions
&run_post_actions();

# Print footer
&ui_print_footer("edit_script.cgi?dom=$in{'dom'}&script=$in{'script'}",
		  $text{'scripts_ereturn'},
		 "list_scripts.cgi?dom=$in{'dom'}", $text{'scripts_return'},
		 &domain_footer_link($d));
