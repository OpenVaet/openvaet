#!/usr/bin/perl
use strict;
use warnings;
use v5.26;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
no autovivification;
use utf8;
use JSON;
use Math::Round qw(nearest);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;

# Defines the variable.
my $file       = 'public/doc/pfizer_trials/efficacy_stats.json'; # File storing trial sites countries data.
my $sims       = 1000000; # Number of random tests performed.

# Setting countries incidence rate (from JH for USA & Argentina, and static 3 for the less represented countries).
my %countriesEstimatedIR              = ();
$countriesEstimatedIR{'Argentina'}    = 7;
$countriesEstimatedIR{'Brazil'}       = 3;
$countriesEstimatedIR{'Germany'}      = 3;
$countriesEstimatedIR{'South Africa'} = 3;
$countriesEstimatedIR{'Turkey'}       = 3;
$countriesEstimatedIR{'USA'}          = 3.5;

my %sites = ();
load_sites();

my %simulationResults   = ();
my $totalSims           = 0;
my $cpt                 = 0;
my $consecutive8OrAbove = 0;
my $highestConsecutive  = 0;
while ($totalSims < $sims) {
	$cpt++;
	$totalSims++;

	# Every 100 sims, renders current stats.
	if ($cpt == 100) {
		$cpt = 0;
		my ($total, $count, $min, $max) = (0, 0, 10000000, 0);
		for my $tS (keys %simulationResults) {
			$total++;
			my $res = $simulationResults{$tS} // 0;
			$min = $res if $min > $res;
			$max = $res if $max < $res;
			$count += $res;
		}
		my $avg = nearest(0.1, $count / $total);
		my $pct = nearest(0.0000001, $consecutive8OrAbove * 100 / $totalSims);
		STDOUT->printflush("\rSimulating [$totalSims] - [$min | $avg | $max] - [$highestConsecutive] - [$consecutive8OrAbove - $pct %]                ")
	}
	my %sim = ();
	my %infected = ();
	# For each day...
	for my $day (1 .. 30) {
		# For each site
		for my $country (sort keys %sites) {
			my $totalSubjects = $sites{$country}->{'subjects'}   // die;
			my $dailyIP10M    = $sites{$country}->{'dailyIP10M'} // die;
			# For each subject on site.
			for my $subject (1 .. $totalSubjects) {
				# Skips the patient if he already fell sick during that simulation.
				next if exists $infected{$subject};
				# If the patient scores below or equal IR set for the country on a random score,
				# considering he caught covid.
				my $rand = nearest(1, rand(10000000));
				if ($rand <= $dailyIP10M) {
					$infected{$subject} = 1;
					$sim{$day}->{$country}->{$subject} = 1;
					# die "$day | $country | $subject -> Positive ($rand)";
				}
			}
		}
	}
	my $positiveCases       = 0;
	my $formerCountry;
	my $consecutiveSubjects = 0;
	my $site1231Cases       = 0;
	for my $day (sort{$a <=> $b} keys %sim) {
		for my $country (sort keys %{$sim{$day}}) {
			if ($formerCountry && ($formerCountry ne $country)) {
				$consecutiveSubjects = 0;
			}
			for my $subject (sort{$a <=> $b} keys %{$sim{$day}->{$country}}) {
				$positiveCases++;
				$site1231Cases++ if $country eq 'Argentina';
				$consecutiveSubjects++;
				if ($country eq 'Argentina') {
					$highestConsecutive = $consecutiveSubjects if $highestConsecutive < $consecutiveSubjects;
					if ($consecutiveSubjects == 8) {
						$consecutive8OrAbove++;
						say "\n8 consecutive subjects on site 1231 after [$totalSims] simulations.";
					}
				}
			}
			$formerCountry = $country;
		}
	}
	if ($site1231Cases) {
		$simulationResults{$totalSims} = $site1231Cases;
	}
}

sub load_sites {
	my $json;
	open my $in, '<:utf8', $file;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	my %sitesRaw = %$json;
	for my $country (sort keys %sitesRaw) {
		my $averageSubjectsOn30DaysSeptember = $sitesRaw{$country}->{'averageSubjectsOn30DaysSeptember'} // next;
		$averageSubjectsOn30DaysSeptember = nearest(1, $averageSubjectsOn30DaysSeptember);
		$sites{$country}->{'subjects'} = $averageSubjectsOn30DaysSeptember;
	}
	for my $country (sort keys %sites) {
		my $iR         = $countriesEstimatedIR{$country} // die "country : $country";       # Total of cases / 1 000 subjects we expect to fall sick monthly.
		my $iRP        = $iR / 1000;
		my $sRP        = 1 - $iRP;
		my $dailyIP    = 1 - $sRP ** (1 / 30);
		my $dailyIP10M = nearest(1, $dailyIP * 10000000);
		die if $dailyIP10M > 10000000;
		say "iRP        : $iRP";
		say "dailyIP    : $dailyIP";
		say "dailyIP10M : $dailyIP10M";
		$sites{$country}->{'dailyIP10M'} = $dailyIP10M;
	}
}

# p%sites;