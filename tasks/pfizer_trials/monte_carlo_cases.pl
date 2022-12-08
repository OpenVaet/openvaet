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
my $file       = 'public/doc/pfizer_trials/efficacy_stats.json'; # File storing trial sites data.
my $sims       = 100000000; # Number of random tests performed.
my $iR         = 5;         # Total of cases / 1 000 subjects we expect to fall sick monthly.
my $iRP        = $iR / 1000;
my $sRP        = 1 - $iRP;
my $dailyIP    = 1 - $sRP ** (1 / 30);
my $dailyIP10M = nearest(1, $dailyIP * 10000000);
die if $dailyIP10M > 10000000;
say "iRP        : $iRP";
say "dailyIP    : $dailyIP";
say "dailyIP10M : $dailyIP10M";

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
		STDOUT->printflush("\rSimulating [$totalSims] - [$min | $avg | $max] - [$highestConsecutive] - [$consecutive8OrAbove]                ")
	}
	my %sim = ();
	# For each day...
	for my $day (1 .. 30) {
		# For each site
		for my $country (sort keys %sites) {
			my $totalSubjects = $sites{$country} // die;
			# For each subject on site.
			for my $subject (1 .. $totalSubjects) {
				my $rand = nearest(1, rand(10000000));
				if ($rand <= $dailyIP10M) {
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
		$sites{$country} = $averageSubjectsOn30DaysSeptember;
	}
}

# p%sites;