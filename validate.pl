#!/usr/local/bin/perl
# Validate some or all virtual servers, and email a report to the admin

package virtual_server;
$main::no_acl_check++;
require './virtual-server-lib.pl';
&foreign_require("mailboxes");

if ($ARGV[0] eq "--debug") {
	$debug_mode = 1;
	}

# Find the virtual servers
@ids = split(/\s+/, $config{'validate_servers'});
if (@ids) {
	foreach $id (@ids) {
		$d = &get_domain($id);
		push(@doms, $d) if ($d);
		}
	}
else {
	@doms = &list_domains();
	}

# Find the features
@feats = split(/\s+/, $config{'validate_features'});
if (!@feats) {
	@feats = ( @validate_features, &list_feature_plugins() );
	}

# Call validation functions on each domain
$out = "";
if ($config{'validate_config'}) {
	$out .= "Virtual server validation\n";
	$out .= "-------------------------\n";
	}
foreach $d (sort { $a->{'dom'} cmp $b->{'dom'} } @doms) {
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

	# Add message to output
	if ($count && (@errs || $config{'validate_always'})) {
		$out .= $d->{'dom'}."\n";
		if (@errs) {
			foreach $e (@errs) {
				$out .= "    ".&html_tags_to_text($e)."\n";
				}
			}
		else {
			$out .= "    OK\n";
			}
		}
	$ecount += scalar(@errs);
	}
$out .= "\n";

# Check Virtualmin config
if ($config{'validate_config'}) {
	&set_all_capture_print();
	$err = &check_virtual_server_config();
	if ($err || $config{'validate_always'}) {
		$out .= "Virtualmin configuration check\n";
		$out .= "------------------------------\n";
		$out .= $print_output;
		if ($err) {
			$out .= $err,"\n";
			$out .= "Configuration errors found\n";
			}
		else {
			$out .= "Configuration OK\n";
			}
		}
	$ecount++ if ($err);
	}

# Send email
if ($debug_mode) {
	print $out;
	}
elsif ($ecount || $config{'validate_always'}) {
	&mailboxes::send_text_mail(&get_global_from_address(),
				   $config{'validate_email'},
				   undef,
				   $ecount ? 'Virtualmin Validation Failed'
					   : 'Virtualmin Validation Successful',
				   $out);
	}

