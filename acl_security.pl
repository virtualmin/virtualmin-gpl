use strict;
use warnings;
no warnings 'redefine';
no warnings 'uninitialized';

require 'virtual-server-lib.pl'; ## no critic
our (%in, %text, @opt_features);

# acl_security_form(&options)
# Output HTML for editing security options for the virtual server module
sub acl_security_form
{
my ($o) = @_;

print &ui_table_span($text{'acl_warn'});

my @selected_domains = split(/\s+/, $o->{'domains'} || '');
my @domain_opts = map { [ $_->{'id'}, $_->{'dom'} ] } &list_domains();
print &ui_table_row(
	$text{'acl_domains'},
	&ui_radio("domains_def", $o->{'domains'} eq '*' ? 1 : 0,
		  [ [ 1, $text{'acl_all'} ],
		    [ 0, $text{'acl_sel'} ] ])."<br>\n".
	&ui_select("domains", \@selected_domains, \@domain_opts, 5, 1),
	3
);

foreach my $q ('create', 'import', 'migrate', 'edit', 'local', 'stop') {
	my $enabled = defined($o->{$q}) ? $o->{$q} : 0;
	my $input;
	if ($q eq "create") {
		$input = &ui_radio($q, $enabled,
			[ [ 1, $text{'yes'} ],
			  [ 2, $text{'acl_only'} ],
			  [ 0, $text{'no'} ] ]);
		}
	elsif ($q eq "edit") {
		$input = &ui_radio($q, $enabled,
			[ [ 1, $text{'yes'} ],
			  [ 2, $text{'acl_lim'} ],
			  [ 0, $text{'no'} ] ]);
		}
	else {
		$input = &ui_yesno_radio($q, $enabled);
		}
	print &ui_table_row($text{'acl_'.$q}, $input);
	}

my @feature_grid;
foreach my $f (@opt_features) {
	push(@feature_grid, &ui_checkbox("features", $f, $text{'feature_'.$f},
					 $o->{"feature_$f"}));
	}
print &ui_table_row($text{'limits_features'},
		    &ui_grid_table(\@feature_grid, 2), 3);
}

# acl_security_save(&options)
# Parse the form for security options for the virtual server module
sub acl_security_save
{
my ($o) = @_;

$o->{'domains'} = $in{'domains_def'} ? "*" :
			join(" ", split(/\0/, $in{'domains'}));
foreach my $q ('create', 'import', 'edit', 'local', 'stop') {
	$o->{$q} = $in{$q};
	}
my %sel_features = map { $_, 1 } split(/\0/, $in{'features'});
foreach my $f (@opt_features) {
	$o->{"feature_".$f} = $sel_features{$f};
	}
}
