
require 'virtual-server-lib.pl';

# acl_security_form(&options)
# Output HTML for editing security options for the virtual server module
sub acl_security_form
{
print "<tr> <td colspan=4>$text{'acl_warn'}</td> </tr>\n";

print "<tr> <td valign=top rowspan=4><b>$text{'acl_domains'}</b></td>\n";
printf "<td rowspan=4><input type=radio name=domains_def value=1 %s> %s\n",
	$_[0]->{'domains'} eq '*' ? "checked" : "", $text{'acl_all'};
printf "<input type=radio name=domains_def value=0 %s> %s<br>\n",
	$_[0]->{'domains'} eq '*' ? "" : "checked", $text{'acl_sel'};
local %doms = map { $_, 1 } split(/\s+/, $_[0]->{'domains'});
print "<select name=domains multiple size=5>\n";
local $d;
foreach $d (&list_domains()) {
	printf "<option value=%s %s>%s\n",
		$d->{'id'}, $doms{$d->{'id'}} ? "selected" : "", $d->{'dom'};
	}
print "</select></td> </tr>\n";

foreach $q ('create', 'import', 'migrate', 'edit', 'local', 'stop') {
	print "<tr> <td><b>",$text{'acl_'.$q},"</b></td> <td>\n";
	printf "<input type=radio name=%s value=1 %s> %s\n",
		$q, $_[0]->{$q} == 1 ? "checked" : "", $text{'yes'};
	if ($q eq "create") {
		printf "<input type=radio name=%s value=2 %s> %s\n",
			$q, $_[0]->{$q} == 2 ? "checked" : "",
			$text{'acl_only'};
		}
	elsif ($q eq "edit") {
		printf "<input type=radio name=%s value=2 %s> %s\n",
			$q, $_[0]->{$q} == 2 ? "checked" : "",
			$text{'acl_lim'};
		}
	printf "<input type=radio name=%s value=0 %s> %s\n",
		$q, $_[0]->{$q} == 0 ? "checked" : "", $text{'no'};
	print "</td> </tr>\n";
	}

print "<tr> <td valign=top><b>$text{'limits_features'}</b></td>\n";
print "<td colspan=3><table>\n";
foreach $f (@opt_features) {
	print "<tr>\n" if ($i%2 == 0);
        printf "<td><input type=checkbox name=features value=%s %s> %s</td>\n",
                $f, $_[0]->{"feature_$f"} ? "checked" : "",
                $text{'feature_'.$f};
        print "</tr>\n" if ($i++%2 == 1);
	}
print "</table></td> </tr>\n";
}

# acl_security_save(&options)
# Parse the form for security options for the useradmin module
sub acl_security_save
{
$_[0]->{'domains'} = $in{'domains_def'} ? "*" :
			join(" ", split(/\0/, $in{'domains'}));
$_[0]->{'create'} = $in{'create'};
$_[0]->{'import'} = $in{'import'};
$_[0]->{'edit'} = $in{'edit'};
$_[0]->{'local'} = $in{'local'};
$_[0]->{'stop'} = $in{'stop'};
%sel_features = map { $_, 1 } split(/\0/, $in{'features'});
foreach $f (@opt_features) {
        $_[0]->{"feature_".$f} = $sel_features{$f};
        }
}

