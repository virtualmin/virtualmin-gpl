#!/usr/local/bin/perl
# Remove a MySQL clone module, or change the default

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newmysqls_ecannot'});
&ReadParse();
&error_setup($in{'default'} ? $text{'newmysqls_derr2'}
			    : $text{'newmysqls_derr'});
my @d = split(/\0/, $in{'d'});
@d || &error($text{'newmysqls_enone'});
my @mymods = &list_remote_mysql_modules();

if ($in{'default'}) {
	# Just change the default
	my $dc;
	foreach my $m (@mymods) {
		my $c = $m->{'config'};
		if ($m->{'minfo'}->{'dir'} eq $d[0]) {
			$c->{'virtualmin_default'} = 1;
			}
		else {
			$c->{'virtualmin_default'} = 0;
			}
		&save_module_config($c, $m->{'minfo'}->{'dir'});
		}
	if ($dc) {
		&webmin_log("default", "newmysql",
			    $dc->{'host'} || $dc->{'sock'}, $dc);
		}
	}
else {
	# Build and validate list to remove
	my %modmap = map { $_->{'minfo'}->{'dir'}, $_ } @mymods;
	my @alldoms = grep { $_->{'mysql'} } &list_domains();
	my @del;
	foreach my $d (@d) {
		my $mm = $modmap{$d};
		$mm || &error($text{'newmysqls_egone'});
		$mm->{'minfo'}->{'dir'} eq 'mysql' &&
			&error($text{'newmysqls_edelete'});
		$mm->{'config'}->{'virtualmin_default'} &&
			&error($text{'newmysqls_edefault'});
		my @doms = grep { $_->{'mysql_module'} eq
			       $mm->{'minfo'}->{'dir'} } @alldoms;
		@doms == 0 || &error(&text('newmysqls_einuse', scalar(@doms)));
		push(@del, $mm);
		}

	# Delete them
	foreach my $mm (@del) {
		&delete_remote_mysql_module($mm);
		}

	&webmin_log("delete", "newmysqls", scalar(@d));
	}
&redirect("edit_newmysqls.cgi");
