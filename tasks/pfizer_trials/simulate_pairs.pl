#!/usr/bin/perl
use strict;
use warnings;
use v5.26;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
no autovivification;
use Scalar::Util qw(looks_like_number);
use utf8;
use JSON;
use Math::Round qw(nearest);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;

# Defines the variable.
my $file       = 'tasks/pfizer_trial_consecutive_doses/eligible_efficacy_subjects.csv'; # File storing trial subjects data.
my $sims       = 1000000; # Number of random tests performed.

# Setting countries incidence rate (from JH for USA & Argentina, and static 3 for the less represented countries).
my %countriesEstimatedIR              = ();
$countriesEstimatedIR{'Argentina'}    = 7;
$countriesEstimatedIR{'Brazil'}       = 3;
$countriesEstimatedIR{'Germany'}      = 3;
$countriesEstimatedIR{'South Africa'} = 3;
$countriesEstimatedIR{'Turkey'}       = 3;
$countriesEstimatedIR{'USA'}          = 3.5;

# Loading raw data required on each subject.
my %subjects = ();
load_subjects();

# Creating a hash containing each day of exposure.
my %dates = ();
prepare_subjects_by_dates();

my %simulationResults   = ();
my $totalSims           = 0;
my $cpt                 = 0;
my $consecutive6OrAbove = 0;
my $highestConsecutive  = 0;
while ($totalSims < $sims) {
	$cpt++;
	$totalSims++;

	# Every 10 sims, renders current stats.
	if ($cpt == 10) {
		$cpt = 0;
		my ($total, $count, $min, $max) = (0, 0, 10000000, 0);
		for my $tS (keys %simulationResults) {
			$total++;
			my $res = $simulationResults{$tS} // 0;
			$min = $res if $min > $res;
			$max = $res if $max < $res;
			$count += $res;
		}
		my $avg = 0;
		$avg    = nearest(0.1, $count / $total) if $total;
		my $pct = nearest(0.0000001, $consecutive6OrAbove * 100 / $totalSims);
		$min    = 0 if $min == 10000000;
		STDOUT->printflush("\rSimulating [$totalSims] - [$min | $avg | $max] - [$highestConsecutive] - [$consecutive6OrAbove - $pct %]                ")
	}
	my %sim = ();
	my %infected = ();
	# For each day...
	for my $day (sort{$a <=> $b} keys %dates) {
		# For each site
		for my $subjectId (sort keys %{$dates{$day}}) {
			my $dailyIP10M    = $subjects{$subjectId}->{'dailyIP10M'} // die;
			# Skips the patient if he already fell sick during that simulation.
			next if exists $infected{$subjectId};
			# If the patient scores below or equal IR set for the country on a random score,
			# considering he caught covid.
			my $rand = nearest(1, rand(10000000));
			if ($rand <= $dailyIP10M) {
				$infected{$subjectId} = 1;
				$sim{$subjectId} = 1;
				# die "$day | $subjectId -> Positive ($rand)";
			}
		}
	}
	my $positiveCases       = 0;
	my $formerSubject;
	my $consecutiveSubjects = 0;
	for my $subjectId (sort{$a <=> $b} keys %sim) {
		$positiveCases++;
		if ($formerSubject && ($formerSubject + 1 == $subjectId)) {
			$consecutiveSubjects++;
			$highestConsecutive = $consecutiveSubjects if $highestConsecutive < $consecutiveSubjects;
			if ($consecutiveSubjects == 6) {
				$consecutive6OrAbove++;
				say "\n6 consecutive pairs after [$totalSims] simulations.";
			}
		}
		$formerSubject = $subjectId;
	}
	if ($consecutive6OrAbove) {
		$simulationResults{$totalSims} = $consecutive6OrAbove;
	}
}

sub load_subjects {
	open my $in, '<:utf8', $file;
	my $rNum = 0;
	while (<$in>) {
		$rNum++;
		next if ($rNum == 1);
		my @elems = split ';', $_;
		my $subjectId        = $elems[0]  // die;
		my $trialSiteId      = $elems[1]  // die;
		my $trialSiteCountry = $elems[2] // die;
		my $daysOfExposure   = $elems[3] // die;
		next unless looks_like_number $daysOfExposure;
		my $dose2Date        = $elems[4] // die;
		my $iR               = $countriesEstimatedIR{$trialSiteCountry} // die "trialSiteCountry : $trialSiteCountry";       # Total of cases / 1 000 subjects we expect to fall sick monthly.
		my $iRP              = $iR / 1000;
		my $sRP              = 1 - $iRP;
		my $dailyIP          = 1 - $sRP ** (1 / 30);
		my $dailyIP10M       = nearest(1, $dailyIP * 10000000);
		die if $dailyIP10M > 10000000;
		# say "subjectId         : $subjectId";
		# say "trialSiteId       : $trialSiteId";
		# say "trialSiteCountry  : $trialSiteCountry";
		# say "daysOfExposure    : $daysOfExposure";
		# say "dose2Date         : $dose2Date";
		# say "dailyIP10M        : $dailyIP10M";
		my ($septemberExposure, $octoberExposure, $novemberExposure) = (0, 0, 0);
		if ($daysOfExposure > 14) {
			$novemberExposure = 14;
			$daysOfExposure   = $daysOfExposure - 14;
			if ($daysOfExposure > 31) {
				$octoberExposure = 31;
				$daysOfExposure  = $daysOfExposure - 31;
				if ($daysOfExposure > 30) {
					$septemberExposure = 30;
				} else {
					$septemberExposure = $daysOfExposure;
				}
			} else {
				$octoberExposure = $daysOfExposure;
			}
		} else {
			$novemberExposure = $daysOfExposure;
		}
		# say "septemberExposure : $septemberExposure";
		# say "octoberExposure   : $octoberExposure";
		# say "novemberExposure  : $novemberExposure";
		$subjects{$subjectId}->{'dailyIP10M'}        = $dailyIP10M;
		$subjects{$subjectId}->{'septemberExposure'} = $septemberExposure;
		$subjects{$subjectId}->{'octoberExposure'}   = $octoberExposure;
		$subjects{$subjectId}->{'novemberExposure'}  = $novemberExposure;
	}
	close $in;
}

sub prepare_subjects_by_dates {
	for my $subjectId (sort{$a <=> $b} keys %subjects) {
		my $septemberExposure = $subjects{$subjectId}->{'septemberExposure'} // die;
		my $octoberExposure   = $subjects{$subjectId}->{'octoberExposure'}   // die;
		my $novemberExposure  = $subjects{$subjectId}->{'novemberExposure'}  // die;
		if ($septemberExposure > 0) {
			my $fromDaySeptember = 31 - $septemberExposure;
			for my $day ($fromDaySeptember .. 30) {
				$day = "0$day" if $day < 10;
				my $compDay = "09$day";
				$dates{$compDay}->{$subjectId} = 1;
			}
			my $fromDayOctober = 32 - $octoberExposure;
			for my $day ($fromDayOctober .. 31) {
				$day = "0$day" if $day < 10;
				my $compDay = "10$day";
				$dates{$compDay}->{$subjectId} = 1;
			}
			my $fromDayNovember = 15 - $novemberExposure;
			for my $day ($fromDayNovember .. 14) {
				$day = "0$day" if $day < 10;
				my $compDay = "11$day";
				$dates{$compDay}->{$subjectId} = 1;
			}
		}
	}
}

# p%sites;