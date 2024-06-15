#!/usr/local/bin/perl
# Do the validation

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'newvalidate_err'});
&can_use_validation() || &error($text{'newvalidate_ecannot'});

# Check and parse inputs
if ($in{'servers_def'}) {
	@doms = &list_visible_domains();
	}
else {
	foreach $id (split(/\0/, $in{'servers'})) {
		$d = &get_domain($id);
		if ($d) {
			&can_edit_domain($d) ||
				&error($text{'newvalidate_ecannot'});
			push(@doms, $d)
			}
		}
	}
@doms || &error($text{'newvalidate_edoms'});
if ($in{'features_def'}) {
	@feats = ( @validate_features, &list_feature_plugins() );
	}
else {
	@feats = split(/\0/, $in{'features'});
	}
@feats || &error($text{'newvalidate_efeats'});

&ui_print_header(undef, $text{'newvalidate_title'}, "");

&$first_print($text{'newvalidate_doing'});
&$indent_print();

# Do it
foreach my $d (@doms) {
	# Call all the feature validators
	@errs = ( );
	$count = 0;
	foreach $f (@feats) {
		next if (!$d->{$f});
		if (&indexof($f, &list_feature_plugins()) < 0) {
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
		&$first_print("<b>".&show_domain_name($d).
			($d->{'disabled'} ?
				" [$text{'enable_disabled'}]" : '')."</b>");
		if (@errs) {
			&$second_print("<font color=#ff0000>&nbsp;&nbsp;&mdash;",join("<br>&nbsp;&nbsp;&mdash;\n", @errs),"</font>");
			}
		else {
			&$second_print("$text{'newvalidate_good'}");
			}
		}
	}

&$outdent_print();
&$second_print("$text{'setup_done'}");
&ui_print_footer("", $text{'index_return'},
		 "edit_newvalidate.cgi", $text{'newvalidate_return'});

