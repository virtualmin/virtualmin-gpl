#!/usr/local/bin/perl
# Do the validation

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'newvalidate_err'});
&can_edit_templates() || &error($text{'newvalidate_ecannot'});

# Check and parse inputs
if ($in{'servers_def'}) {
	@doms = &list_domains();
	}
else {
	foreach $id (split(/\0/, $in{'servers'})) {
		$d = &get_domain($id);
		push(@doms, $d) if ($d);
		}
	}
@doms || &error($text{'newvalidate_edoms'});
if ($in{'features_def'}) {
	@feats = ( @features, @feature_plugins );
	}
else {
	@feats = split(/\0/, $in{'features'});
	}
@feats || &error($text{'newvalidate_efeats'});

&ui_print_header(undef, $text{'newvalidate_title'}, "");

print "<b>$text{'newvalidate_doing'}</b><p>\n";

# Do it
print "<dl>\n";
foreach $d (@doms) {
	# Call all the feature validators
	@errs = ( );
	$count = 0;
	foreach $f (@feats) {
		next if (!$d->{$f});
		if (&indexof($f, @feature_plugins) < 0) {
			# Core feature
			next if (!$config{$f});
			$vfunc = "validate_$f";
			$err = &$vfunc($d);
			$name = $text{'feature_'.$f};
			}
		else {
			# Plugin feature
			$err = &plugin_call($f, "feature_validate", $d);
			$name = &plugin_call($f, "feature_name");
			}
		push(@errs, "$name : $err") if ($err);
		$count++;
		}

	# Print message, if anything done
	if ($count) {
		print "<dt>$d->{'dom'}\n";
		if (@errs) {
			print "<dd><font color=#ff0000>",
			      join("<br>\n", @errs),"</font>\n";
			}
		else {
			print "<dd>$text{'newvalidate_good'}\n";
			}
		}
	}
print "</dl>\n";

&ui_print_footer("", $text{'index_return'});

