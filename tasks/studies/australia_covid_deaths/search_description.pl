

open my $in, '<:utf8', 'australian_death_reports.json';
while (<$in>) {
	$json .= $_;
}
close $in;