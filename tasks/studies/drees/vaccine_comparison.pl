#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use Data::Printer;
use Data::Dumper;
use JSON;
use Scalar::Util qw(looks_like_number);
use FindBin;
use lib "$FindBin::Bin/../../../lib";

# Project's libraries.
use global;
use time;



# vacsi-tot-fra-YYYY-MM-DD-HHhmm.csv (échelle nationale)   : Fichiers avec le nombre de personnes ayant reçu au moins une dose ou complètement vaccinées,
														   # arrêté à la dernière date disponible
# vacsi-tot-v-fra-YYYY-MM-DD-HHhmm.csv (échelle nationale) : Fichiers avec le nombre de personnes ayant reçu au moins une dose,
														   # ou deux doses, ou trois doses par vaccin, arrêté à la dernière date disponible
# vacsi-v-fra-YYYY-MM-DD-HHhmm.csv (échelle nationale)     : Fichiers avec le nombre quotidien de personnes ayant reçu au moins une dose, deux
														   # doses ou trois doses par vaccin, et par date d’injection
# vacsi-fra-YYYY-MM-DD-HHhmm.csv (échelle nationale)       : Fichiers avec le nombre quotidien de personnes ayant reçu au moins une dose,
														   # par date d’injection

my %rawData  = ();

my $folder   = "tasks/studies/drees/data";
my $ansmFile = "stats/ansm_data.json";

my %vaccines = ();
$vaccines{0} = 'Tous vaccins';
$vaccines{1} = 'Pfizer (Comirnaty) - Adulte';
$vaccines{2} = 'Moderna (Spikevax)';
$vaccines{3} = 'Astrazeneca (Vaxzevria)';
$vaccines{4} = 'Janssen (Jcovden)';
$vaccines{5} = 'Pfizer (Comirnaty) - Enfant';
$vaccines{6} = 'Nuvaxovid (Novavax)';

for my $file (glob "$folder/*\.csv") {
	parse_file($file);
}

open my $out, '>:utf8', $ansmFile;
print $out encode_json\%rawData;
close $out; 

p%rawData;

sub parse_file {
	my $file = shift;
	die "missing file [$file]" unless -f $file;
	open my $in, '<:utf8', $file;
	($file, my $updateDate) = $file =~ /(.*)-(....-..-..-..h..)\.csv/;
	$file =~ s/tasks\/studies\/drees\/data\///;
	say "parsing file [$file] - [$updateDate]";
	my @labels;
	$rawData{$file}->{'updateDate'} = $updateDate;
	while (<$in>) {
		chomp $_;
		unless (scalar @labels) {
			@labels = split ';', $_;
		} else {
			my @values = split ';', $_;
			if ($file eq 'ansm_stats_by_substances_and_sexes') {
				my $vaccineName   = $values[0] // die;
				my $sexName       = $values[1] // die;
				my $total1stDoses = $values[2] // die;
				my $total2ndDoses = $values[3] // die;
				my $total3rdDoses = $values[4] // die;
				my $total4thDoses = $values[5] // die;
				my $totalDoses    = $values[6] // die;
				$rawData{$file}->{$vaccineName}->{$sexName}->{'total1stDoses'} = $total1stDoses;
				$rawData{$file}->{$vaccineName}->{$sexName}->{'total2ndDoses'} = $total2ndDoses;
				$rawData{$file}->{$vaccineName}->{$sexName}->{'total3rdDoses'} = $total3rdDoses;
				$rawData{$file}->{$vaccineName}->{$sexName}->{'total4thDoses'} = $total4thDoses;
				$rawData{$file}->{$vaccineName}->{$sexName}->{'totalDoses'}    = $totalDoses;
			} elsif ($file eq 'ansm_stats_by_substances') {
				my $vaccineName   = $values[0] // die;
				my $totalDoses    = $values[1] // die;
				$rawData{$file}->{$vaccineName}->{'totalDoses'} = $totalDoses;
			} elsif ($file eq 'ansm_stats_astra_by_sexes') {
				my $sexName       = $values[0] // die;
				my $total1stDoses = $values[1] // die;
				my $total2ndDoses = $values[2] // die;
				my $total3rdDoses = $values[3] // die;
				my $totalDoses    = $values[4] // die;
				$rawData{$file}->{'AstraZeneca'}->{$sexName}->{'total1stDoses'} = $total1stDoses;
				$rawData{$file}->{'AstraZeneca'}->{$sexName}->{'total2ndDoses'} = $total2ndDoses;
				$rawData{$file}->{'AstraZeneca'}->{$sexName}->{'total3rdDoses'} = $total3rdDoses;
				$rawData{$file}->{'AstraZeneca'}->{$sexName}->{'totalDoses'}    = $totalDoses;
			} elsif ($file eq 'vacsi-fra') {
				# my $fra = $values[0] // die;
				# if ($fra ne 'FR') {
				# 	die;
				# }
				# my $day           = $values[1] // die;
				# my $total1stDoses = $values[2] // die;
				# my $total2ndDoses = $values[3] // die;
				# my $total3rdDoses = $values[4] // die;
				# my $total4thDoses = $values[5] // die;
				# p@labels;
				# p@values;
				# die;
			} elsif ($file eq 'vacsi-tot-fra') {
				my $fra = $values[0] // die;
				if ($fra ne 'FR') {
					die;
				}
				my $day           = $values[1] // die;
				my $total1stDoses = $values[2] // die;
				my $total2ndDoses = $values[3] // die;
				my $total3rdDoses = $values[4] // die;
				my $total4thDoses = $values[5] // die;
				my $population    = $values[6] // die;
				my $totalDoses    = $total1stDoses + $total2ndDoses + $total3rdDoses + $total4thDoses;
				$rawData{$file}->{'day'}           = $day;
				$rawData{$file}->{'total1stDoses'} = $total1stDoses;
				$rawData{$file}->{'total2ndDoses'} = $total2ndDoses;
				$rawData{$file}->{'total3rdDoses'} = $total3rdDoses;
				$rawData{$file}->{'total4thDoses'} = $total4thDoses;
				$rawData{$file}->{'population'}    = $population;
				$rawData{$file}->{'totalDoses'}    = $totalDoses;
			} elsif ($file eq 'vacsi-tot-v-fra') {
				my $fra           = $values[0] // die;
				if ($fra ne 'FR') {
					die;
				}
				my $vaccineRef    = $values[1] // die;
				my $vaccineName   = $vaccines{$vaccineRef} // die;
				my $day           = $values[2] // die;
				my $total1stDoses = $values[3] // die;
				my $total2ndDoses = $values[4] // die;
				my $total3rdDoses = $values[5] // die;
				my $total4thDoses = $values[6] // die;
				my $population    = $values[7] // die;
				my $totalDoses    = $total1stDoses + $total2ndDoses + $total3rdDoses + $total4thDoses;
				if (exists $rawData{$file}->{'day'} && $rawData{$file}->{'day'} ne $day) {
					die;
				}
				$rawData{$file}->{'day'}                           = $day;
				$rawData{$file}->{$vaccineName}->{'total1stDoses'} = $total1stDoses;
				$rawData{$file}->{$vaccineName}->{'total2ndDoses'} = $total2ndDoses;
				$rawData{$file}->{$vaccineName}->{'total3rdDoses'} = $total3rdDoses;
				$rawData{$file}->{$vaccineName}->{'total4thDoses'} = $total4thDoses;
				$rawData{$file}->{$vaccineName}->{'population'}    = $population;
				$rawData{$file}->{$vaccineName}->{'totalDoses'}    = $totalDoses;
				if ($vaccineRef != 0) {
					$rawData{$file}->{'Tous vaccins verified'}->{'total1stDoses'}  += $total1stDoses;
					$rawData{$file}->{'Tous vaccins verified'}->{'total2ndDoses'}  += $total2ndDoses;
					$rawData{$file}->{'Tous vaccins verified'}->{'total3rdDoses'}  += $total3rdDoses;
					$rawData{$file}->{'Tous vaccins verified'}->{'total4thDoses'}  += $total4thDoses;
					$rawData{$file}->{'Tous vaccins verified'}->{'totalDoses'}     += $total4thDoses;
				}
				# p@labels;
				# die;
			} elsif ($file eq 'vacsi-v-fra') {
				# p@labels;
				# die;
			} else {
				die;
			}
		}
	}
	close $in;
}