#!/usr/local/bin/perl

do '../web-lib.pl';
&init_config();
do '../ui-lib.pl';
&ReadParse();

&ui_print_unbuffered_header(undef, "Eval Test", "");
$mod = $in{'mod'} || "useradmin";
$lib = $mod eq "useradmin" ? "user-lib.pl" : "$mod-lib.pl";

$count = 100.0;
print "Doing $count requires of $mod/$lib ..<p>\n";

$start = time();
for($i=0; $i<$count; $i++) {
	&foreign_require($mod, $lib);
	undef(%main::done_foreign_require);
	}
$end = time();
printf ".. time per require for $mod = %f<p>\n",
	($end - $start)/$count;

print &ui_form_start("evaltest.cgi");
print "Module: ",&ui_textbox("mod", $mod, 20),"\n",
      &ui_submit("OK");
print &ui_form_end();

&ui_print_footer("/", "index");

