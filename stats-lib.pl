# Common functions for Virtualmin historic stats

# historic_stat_info(name, [&maxes])
# Returns a hash ref with info about the units and class of some stat
sub historic_stat_info
{
local ($name, $maxes) = @_;
if ($name =~ /count$/) {
	return { 'type' => 'email', 'units' => $text{'history_messages'} };
	}
elsif ($name =~ /^load/) {
	return { 'type' => 'cpu', 'units' => $text{'history_cores'} };
	}
elsif ($name =~ /^cpu(idle|io|kernel|user)$/) {
	return { 'type' => 'cpu', 'units' => $text{'history_pc'} };
	}
elsif ($name eq "cputemp") {
	return { 'type' => 'cpu', 'units' => $text{'history_degrees'} };
	}
elsif ($name =~ /^b(in|out)$/) {
	return { 'type' => 'system', 'units' => $text{'history_bps'} };
	}
elsif ($name eq "drivetemp") {
	return { 'type' => 'system', 'units' => $text{'history_degrees'} };
	}
elsif ($name eq "tx" || $name eq "rx") {
	return { 'type' => 'system', 'units' => $text{'history_kbsec'},
		 'scale' => 1024 };
	}
elsif ($name eq "aliases" || $name eq "doms" || $name eq "users") {
	return { 'type' => 'virt' };
	}
elsif ($name =~ /^(mem|hostmem|swap)(used|free)$/) {
	return { 'type' => 'system', 'units' => 'MB',
		 'scale' => 1024*1024 };
	}
elsif ($name =~ /^(disk|hostdisk)(used|free)$/) {
	return { 'type' => 'system', 'units' => 'GB',
		 'scale' => 1024*1024*1024 };
	}
elsif ($name =~ /^quota/) {
	return { 'type' => 'virt',
		 'units' => $maxes && $maxes->{$name} < 10*1024*1024*1024 ?
				"MB" : "GB",
		 'scale' => $maxes && $maxes->{$name} < 10*1024*1024*1024 ?
				1024*1024 : 1024*1024*1024 };
	}
elsif ($name eq "procs") {
	return { 'type' => 'system' };
	}
return undef;
}

# get_historic_graph_colors()
# Returns colors from graph lines, ripped from Gnuplot
sub get_historic_graph_colors
{
return (
        "#ff0000",  "#00c000",  "#0080ff",  "#c000ff",  "#00eeee",  "#c04000",
        "#eeee00",  "#2020c0",  "#ffc020",  "#008040",  "#a080ff",  "#804000",
        "#ff80ff",  "#00c060",  "#00c0c0",  "#006080",  "#c06080",  "#008000",
        "#40ff80",  "#306080",  "#806000",  "#404040",  "#408000",  "#000080",
        "#806010",  "#806060",  "#806080",  "#0000c0",  "#0000ff",  "#006000",
        "#e3b0c0",  "#40c080",  "#60a0c0",  "#60c000",  "#60c0a0",  "#800000",
        "#800080",  "#602080",  "#606060",  "#202020",  "#204040",  "#204080",
        "#608020",  "#608060",  "#608080",  "#808040",  "#208020",  "#808080",
        "#a0a0a0",  "#a0d0e0",  "#c02020",  "#008080",  "#c06000",  "#80c0e0",
        "#c060c0",  "#c08000",  "#c08060",  "#ff4000",  "#ff4040",  "#80c0ff",
        "#ff8060",  "#ff8080",  "#c0a000",  "#c0c0c0",  "#c0ffc0",  "#ff0000",
        "#ff00ff",  "#ff80a0",  "#c0c0a0",  "#ff6060",  "#00ff00",  "#ff8000",
        "#ffa000",  "#80e0e0",  "#a0e0e0",  "#a0ff20",  "#c00000",  "#c000c0",
        "#a02020",  "#a020ff",  "#802000",  "#802020",  "#804020",  "#804080",
        "#8060c0",  "#8060ff",  "#808000",  "#c0c000",  "#ff8040",  "#ffa040",
        "#ffa060",  "#ffa070",  "#ffc0c0",  "#ffff00",  "#ffff80",  "#ffffc0"
        );
}

sub get_history_periods
{
return (
        [ 'year', 365*24*60*60 ],
        [ 'month', 31*24*60*60 ],
        [ 'week', 7*24*60*60 ],
        [ 'day', 24*60*60 ],
        [ 'hour', 60*60 ],
        );
}

1;

