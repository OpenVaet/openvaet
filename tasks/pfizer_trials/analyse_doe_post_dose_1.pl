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
use Math::CDF;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;
use Date::WeekNumber qw/ iso_week_number /;
use Scalar::Util qw(looks_like_number);
use time;

# Treatment configuration.
my $daysOffset           = 5;
my $symptomsBeforePCR    = 1; # 0 = before non included ; 1 = before included.
my $officialSymptomsOnly = 0; # 0 = secondary symptoms taken into account ; 1 = secondary symptoms included.
my $cutoffCompdate       = '20201114';
my $df                   = 1; # degrees of freedom

# Loading data required.
my $randomizationFile = 'public/doc/pfizer_trials/merged_doses_data.json';
my $p1SubjectsFile    = 'public/doc/pfizer_trials/phase1Subjects.json';

my %phase1Subjects    = ();
my %randomization     = ();
load_phase_1();
load_randomization();

my %stats = ();
eval_days_of_exposure();
trial_site_stats();

sub eval_days_of_exposure {
	for my $subjectId (sort{$a <=> $b} keys %randomization) {
		$stats{'totalSubjectsRandomized'}++;
		if (exists $phase1Subjects{$subjectId}) {
			$stats{'phase1Subjects'}++;
			next;
		}
		unless ($randomization{$subjectId}->{'dose1Date'}) {
			$stats{'noDose1'}++;
			next;
		}
		my $dose1Date           = $randomization{$subjectId}->{'dose1Date'}          // die;
		my $randomizationGroup  = $randomization{$subjectId}->{'randomizationGroup'} // 'Unknown';
		$randomizationGroup     = 'BNT162b2' if $randomizationGroup =~ /BNT162b2 \(30/;
		if ($randomizationGroup eq 'Unknown') {
			$stats{'noKnownRandomizationGroup'}++;
			next;
		}

		my ($trialSiteId)        = $subjectId =~ /(....)..../;
		my ($fDY, $fDM, $fDD)    = $cutoffCompdate  =~ /(....)(..)(..)/;
		my ($fDsY, $fDsM, $fDsD) = $dose1Date        =~ /(....)(..)(..)/;

		my $daysOfExposureToSymptoms = time::calculate_days_difference("$fDsY-$fDsM-$fDsD 12:00:00", "$fDY-$fDM-$fDD 12:00:00");

		$stats{'subjects'}->{'total'}->{$randomizationGroup}->{'total'}++;
		$stats{'subjects'}->{'total'}->{$randomizationGroup}->{'totalDaysOfExposure'} += $daysOfExposureToSymptoms;
		$stats{'subjects'}->{'byArm'}->{$trialSiteId}->{$randomizationGroup}->{'total'}++;
		$stats{'subjects'}->{'byArm'}->{$trialSiteId}->{$randomizationGroup}->{'totalDaysOfExposure'} += $daysOfExposureToSymptoms;
	}
}

sub trial_site_stats {
	my $populationBNT162b2Subjects = $stats{'subjects'}->{'total'}->{'BNT162b2'}->{'total'} // die;
	my $populationPlaceboSubjects  = $stats{'subjects'}->{'total'}->{'Placebo'}->{'total'}  // die;
	my $populationBNT162b2DOE      = $stats{'subjects'}->{'total'}->{'BNT162b2'}->{'totalDaysOfExposure'} // die;
	my $populationPlaceboDOE       = $stats{'subjects'}->{'total'}->{'Placebo'}->{'totalDaysOfExposure'}  // die;
	open my $out, '>:utf8', 'symptomatic_subjects_by_sites.csv';
	say $out "BNT162b2 - Total Subjects;Placebo - Total Subjects;BNT162b2 - Total Days Of Exposure;Placebo - Total Days Of Exposure;";
	say $out "$populationBNT162b2Subjects;$populationPlaceboSubjects;$populationBNT162b2DOE;$populationPlaceboDOE;";
	say $out "";
	say $out "";
	say $out "Trial Site Id;BNT162b2 - Days of Exposure;BNT162b2 - Site Subjects;Chi P-Value Subjects;Placebo - Days of Exposure;Placebo - Site Subjects;Chi P-Value DOE;";
	for my $trialSiteId (sort{$a <=> $b} keys %{$stats{'subjects'}->{'byArm'}}) {
		my $totalBNT162b2Subjects       = $stats{'subjects'}->{'byArm'}->{$trialSiteId}->{'BNT162b2'}->{'total'}               // die;
		my $totalPlaceboSubjects        = $stats{'subjects'}->{'byArm'}->{$trialSiteId}->{'Placebo'}->{'total'}                // die;
		my $totalBNT162b2DOE            = $stats{'subjects'}->{'byArm'}->{$trialSiteId}->{'BNT162b2'}->{'totalDaysOfExposure'} // die;
		my $totalPlaceboDOE             = $stats{'subjects'}->{'byArm'}->{$trialSiteId}->{'Placebo'}->{'totalDaysOfExposure'}  // die;
		my $BNT162b2RestOfStudySubjects = $populationBNT162b2Subjects - $totalBNT162b2Subjects;
		my $PlaceboRestOfStudySubjects  = $populationPlaceboSubjects  - $totalBNT162b2Subjects;
		my $BNT162b2RestOfStudyDOE      = $populationBNT162b2DOE - $totalBNT162b2DOE;
		my $PlaceboRestOfStudyDOE       = $populationPlaceboDOE  - $totalBNT162b2DOE;
		my $chiSubjects                 = chi_squared($totalBNT162b2Subjects, $totalPlaceboSubjects, $BNT162b2RestOfStudySubjects, $PlaceboRestOfStudySubjects);
		my $pValueSubjects              = 1 - Math::CDF::pchisq($chiSubjects, $df);
		my $chiDOE                      = chi_squared($totalBNT162b2DOE, $totalPlaceboDOE, $BNT162b2RestOfStudyDOE, $PlaceboRestOfStudyDOE);
		my $pValueDOE                   = 1 - Math::CDF::pchisq($chiDOE, $df);
		say $out "$trialSiteId;$totalBNT162b2DOE;$totalBNT162b2Subjects;$chiSubjects;$totalPlaceboDOE;$totalPlaceboSubjects;$chiDOE;";
		if ($pValueDOE < 0.1) {
			if ($totalBNT162b2DOE > $totalPlaceboDOE) {
				$stats{'BNT162OverExposed'}->{'totalBNT162b2Subjects'} += $totalBNT162b2Subjects;
				$stats{'BNT162OverExposed'}->{'totalPlaceboSubjects'} += $totalPlaceboSubjects;
				$stats{'BNT162OverExposed'}->{'totalBNT162b2DOE'} += $totalBNT162b2DOE;
				$stats{'BNT162OverExposed'}->{'totalPlaceboDOE'} += $totalPlaceboDOE;
				say "*" x 50;
				say "BNT more exposed";
				say "trialSiteId                  : [$trialSiteId]";
				say "totalBNT162b2Subjects        : [$totalBNT162b2Subjects]";
				say "totalPlaceboSubjects         : [$totalPlaceboSubjects]";
				say "totalBNT162b2DOE             : [$totalBNT162b2DOE]";
				say "totalPlaceboDOE              : [$totalPlaceboDOE]";
				say "BNT162b2RestOfStudySubjects  : [$BNT162b2RestOfStudySubjects]";
				say "PlaceboRestOfStudySubjects   : [$PlaceboRestOfStudySubjects]";
				say "chiSubjects                  : [$chiSubjects]";
				say "pValueSubjects               : [$pValueSubjects]";
				say "chiDOE                       : [$chiDOE]";
				say "pValueDOE                    : [$pValueDOE]";
			} else {
				$stats{'PlaceboOverExposed'}->{'totalBNT162b2Subjects'} += $totalBNT162b2Subjects;
				$stats{'PlaceboOverExposed'}->{'totalPlaceboSubjects'} += $totalPlaceboSubjects;
				$stats{'PlaceboOverExposed'}->{'totalBNT162b2DOE'} += $totalBNT162b2DOE;
				$stats{'PlaceboOverExposed'}->{'totalPlaceboDOE'} += $totalPlaceboDOE;
				say "*" x 50;
				say "Placebo more exposed";
				say "trialSiteId                  : [$trialSiteId]";
				say "totalBNT162b2Subjects        : [$totalBNT162b2Subjects]";
				say "totalPlaceboSubjects         : [$totalPlaceboSubjects]";
				say "totalBNT162b2DOE             : [$totalBNT162b2DOE]";
				say "totalPlaceboDOE              : [$totalPlaceboDOE]";
				say "BNT162b2RestOfStudySubjects  : [$BNT162b2RestOfStudySubjects]";
				say "PlaceboRestOfStudySubjects   : [$PlaceboRestOfStudySubjects]";
				say "chiSubjects                  : [$chiSubjects]";
				say "pValueSubjects               : [$pValueSubjects]";
				say "chiDOE                       : [$chiDOE]";
				say "pValueDOE                    : [$pValueDOE]";
			}
			$stats{'poeStats'}->{'abnormalPValueOnDOE'}++;
		} else {
			if ($pValueDOE < 0.25) {
				$stats{'poeStats'}->{'slightlyBelowNormalPValueOnDOE'}++;
			} else {
				$stats{'poeStats'}->{'normalPValueOnDOE'}++;
			}
		}
	}
	# close $out;
	my $chi = chi_squared(44008, 38580, 1485387, 1490727);
	my $pValue = 1 - Math::CDF::pchisq($chi, $df);
	say "chi : [$chi], p-value: [$pValue]";
}

sub chi_squared {
     my ($a, $b, $c, $d) = @_;
     return 0 if($a + $c == 0);
     return 0 if($b + $d == 0);
     my $n = $a + $b + $c + $d;
     return (($n * ($a * $d - $b * $c) ** 2) / (($a + $b)*($c + $d)*($a + $c)*($b + $d)));
}

p%stats;

sub load_phase_1 {
	open my $in, '<:utf8', $p1SubjectsFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%phase1Subjects = %$json;
	# p%phase1Subjects;die;
	say "[$p1SubjectsFile] -> subjects : " . keys %phase1Subjects;
}

sub load_randomization {
	open my $in, '<:utf8', $randomizationFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%randomization = %$json;
	say "[$randomizationFile] -> subjects : " . keys %randomization;
}