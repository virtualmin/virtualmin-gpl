# Functions for checking and manipulating domain names. Used by both Virtualmin
# and Cloudmin.

# shorten_domain_name(&dom)
# Returns a domain name shorten to the display max
sub shorten_domain_name
{
local ($d) = @_;
local $show = &show_domain_name($d->{'showdom'} || $d->{'dom'});

# Split into characters, some of which may be HTML entities that are multiple
# letters in the string (like &foo; or &#55;) but appear as one letter
local @chars;
local $tosplit = $show;
if ($tosplit =~ /\&|;/) {
	while($tosplit =~ s/^(\&[^;]+;)// ||
	      $tosplit =~ s/^(.)//) {
		push(@chars, $1);
		}
	}
else {
	@chars = split(//, $tosplit);
	}

local $rv;
if ($config{'name_max'} && scalar(@chars) > $config{'name_max'}) {
	# Show first and last max/2 chars, with ... between.
	local $s = int($config{'name_max'} / 2);
	$rv = join("", @chars[0 .. $s-1])."...".
	      join("", @chars[$#chars-$s .. $#chars]);
	}
else {
	$rv = $show;
	}
$rv =~ s/ /&nbsp;/g;
return $rv;
}

# show_domain_name(&dom|dname)
# Converts a domain name to human-readable form for display. Currently this
# takes IDN encoding into account
sub show_domain_name
{
local $name = ref($_[0]) ? $_[0]->{'dom'} : $_[0];
local $spacer;
if ($name =~ s/^(\s+)//) {
	$spacer = $1;
	}
if ($name =~ /^xn--/ || $name =~ /\.xn--/) {
	# Convert xn-- parts to unicode
	push(@INC, $module_root_directory)
		if (&indexof($module_root_directory, @INC) < 0);
	eval "use IDNA::Punycode";
	if (!$@) {
		$name = join(".",
			  map { decode_punycode($_) } split(/\./, $name));
		if ($ENV{'MINISERV_CONFIG'}) {
			# In browser, so convert to entity format for HTML
			local $ename;
			foreach my $c (split(//, $name)) {
				local $o = ord($c);
				$ename .= $o > 255 ? "&#$o;" : $c;
				}
			$name = $ename;
			}
		}
	}
return $spacer.$name;
}

# parse_domain_name(input)
# Returns an IDN-encoding domain name, where needed
sub parse_domain_name
{
local $name = &entities_to_ascii($_[0]);
$name =~ s/^\s+//;	# Strip leading and trailing spaces from user input
$name =~ s/\s+$//;
if ($name !~ /^[a-z0-9\.\-\_]+$/i) {
	# Convert unicode to xn-- format
	eval "use IDNA::Punycode";
	if (!$@) {
		$name = join(".",
			  map { encode_punycode($_) } split(/\./, $name));
		$name =~ s/^xn---/xn--/g;	# IDNA::Punycode gets this wrong
		$name =~ s/\.xn---/\.xn--/g;
		}
	}
return $name;
}

# valid_domain_name(input)
# Returns an error message if a domain name is not valid, undef if OK.
# Expects parse_domain_name to have been already called.
sub valid_domain_name
{
local ($name) = @_;
$name =~ /^[A-Za-z0-9\.\-]+$/ || return $text{'setup_edomain'};
$name =~ /^\./ && return $text{'setup_edomain2'};
$name =~ /\.$/ && return $text{'setup_edomain2'};
$name =~ /\.xn(-+)([^\.]+)$/ && return $text{'setup_edomain3'};
if ($name =~ /^(www)\./i) {
	return &text('setup_edomainprefix', "$1");
	}
return undef;
}

1;

