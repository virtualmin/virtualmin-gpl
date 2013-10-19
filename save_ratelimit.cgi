#!/usr/bin/perl
# Enable and configure or disable rate limiting

require './virtual-server-lib.pl';
&error_setup($text{'ratelimit_err'});
&can_edit_templates() || &error($text{'ratelimit_ecannot'});
&ReadParse();

# Validate inputs
$in{'max_def'} || &check_ratelimit_field("max", $text{'ratelimit_emax'});

&ui_print_unbuffered_header(undef, $text{'ratelimit_title'}, "");

if ($in{'enable'} && !&is_ratelimit_enabled()) {
	# Need to enable
	&enable_ratelimit();
	}
elsif (!$in{'enable'} && &is_ratelimit_enabled()) {
	# Need to disable
	&disable_ratelimit();
	}

# Update config
&lock_file(&get_ratelimit_config_file());
$conf = &get_ratelimit_config();
&parse_ratelimit_field("max", $conf, "virtualmin_limit");
&unlock_file(&get_ratelimit_config_file());
$err = &apply_ratelimit_config();
&error("<tt>".&html_escape($err)."</tt>") if ($err);

&ui_print_footer("ratelimit.cgi", $text{'ratelimit_return'});

# check_ratelimit_field(name, message)
# Checks the rate-limit field of some name
sub check_ratelimit_field
{
my ($name, $msg) = @_;
$in{$name."_num"} =~ /^\d+$/ || &error($msg." : ".$text{'ratelimit_enum'});
$in{$name."_time"} =~ /^\d+$/ || &error($msg." : ".$text{'ratelimit_etime'});
}

# parse_ratelimit_field(name, &config, config-limit-name)
# Update the ratelimit of some type
sub parse_ratelimit_field
{
my ($name, $conf, $ratelimit) = @_;

# Get existing limit objects
my ($rl) = grep { $_->{'name'} eq 'ratelimit' &&
	          $_->{'values'}->[0] eq $ratelimit } @$conf;
my ($racl) = grep { $_->{'name'} eq 'racl' &&
		    $_->{'values'}->[0] eq 'blacklist' &&
		    $_->{'values'}->[3] eq 'ratelimit' &&
	            $_->{'values'}->[4] eq $ratelimit } @$conf;
if ($in{$name."_def"}) {
	# Remove existing lines
	&save_ratelimit_directive($conf, $rl, undef);
	&save_ratelimit_directive($conf, $racl, undef);
	}
else {
	# Add or update
	my $newrl = { 'name' => 'ratelimit',
		      'values' => [
			$ratelimit, 'rcpt', $in{$name."_num"},
			"/", $in{$name."_time"}.$in{$name."_units"} ],
		    };
	my $newracl = { 'name' => 'racl',
			'values' => [
			  'blacklist', 'from', '/.*/', 'ratelimit', $ratelimit,
			  'msg', 'Message quota exceeded' ],
		      };
	&save_ratelimit_directive($conf, $rl, $newrl);
	&save_ratelimit_directive($conf, $racl, $newracl);
	}
}
