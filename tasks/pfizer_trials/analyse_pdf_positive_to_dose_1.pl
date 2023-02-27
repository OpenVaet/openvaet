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
use Date::WeekNumber qw/ iso_week_number /;
use Scalar::Util qw(looks_like_number);
use time;

# Treatment configuration.
my $daysOffset           = 5;
my $symptomsBeforePCR    = 1; # 0 = before non included ; 1 = before included.
my $officialSymptomsOnly = 0; # 0 = secondary symptoms taken into account ; 1 = secondary symptoms included.

# Loading data required.
my $exclusionsFile    = 'public/doc/pfizer_trials/pfizer_excluded_patients.json';
my $deviationsFile    = 'public/doc/pfizer_trials/pfizer_sddv_patients.json';
my $pcrTestsFile      = 'public/doc/pfizer_trials/pfizer_mb_patients.json';
my $symptomsFile      = 'public/doc/pfizer_trials/pfizer_patients_symptoms.json';
my $randomizationFile = 'public/doc/pfizer_trials/merged_doses_data.json';
my $p1SubjectsFile    = 'public/doc/pfizer_trials/phase1Subjects.json';
my $demographicFile   = 'public/doc/pfizer_trials/pfizer_trial_demographics_merged.json';
my $pdfCasesFile      = 'public/doc/pfizer_trials/pfizer_trial_cases_merged.json';
my %demographics      = ();
my %phase1Subjects    = ();
my %exclusions        = ();
my %deviations        = ();
my %pcrTests          = ();
my %symptoms          = ();
my %randomization     = ();
my %pdfCases          = ();
load_demographics();
load_phase_1();
load_randomization();
load_exclusions();
load_deviations();
load_pcr_tests();
load_symptoms();
load_pdf_cases();

my %stats = ();
my %weeklyStats = ();

# Flushing .PDF cases & exclusions post cut-off on November 14.
delete_post_cutoff_pdf_cases();


sub load_demographics {
	open my $in, '<:utf8', $demographicFile or die "Missing file [$demographicFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%demographics = %$json;
	say "[$demographicFile] -> patients : " . keys %demographics;
}

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

sub load_exclusions {
	open my $in, '<:utf8', $exclusionsFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%exclusions = %$json;
	say "[$exclusionsFile] -> subjects : " . keys %exclusions;
}

sub load_deviations {
	open my $in, '<:utf8', $deviationsFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%deviations = %$json;
	say "[$deviationsFile] -> subjects : " . keys %deviations;
}

sub load_pcr_tests {
	open my $in, '<:utf8', $pcrTestsFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%pcrTests = %$json;
	# p$pcrTests{'44441222'};
	say "[$pcrTestsFile] -> subjects : " . keys %pcrTests;
}

sub load_symptoms {
	open my $in, '<:utf8', $symptomsFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%symptoms = %$json;
	say "[$symptomsFile] -> subjects : " . keys %symptoms;
	# p$symptoms{'44441222'};
	# die;
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

sub load_pdf_cases {
	open my $in, '<:utf8', $pdfCasesFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%pdfCases = %$json;
	say "[$pdfCasesFile] -> subjects : " . keys %pdfCases;
}

sub delete_post_cutoff_pdf_cases {
	for my $subjectId (sort{$a <=> $b} keys %pdfCases) {
		unless ($pdfCases{$subjectId}->{'swabDate'} <= 20201114) {
			delete $pdfCases{$subjectId};
		}
	}
}

for my $subjectId (sort keys %pdfCases) {
	die if exists $phase1Subjects{$subjectId};
	die unless exists $randomization{$subjectId};

	# Reorganizing visits by dates.
	my ($hasPositivePCR,
		%pcrsByDates)      = subject_pcrs_by_dates($subjectId);
	unless (keys %pcrsByDates && $hasPositivePCR) {
		say "subject [$subjectId] has no positive central lab PCR.";
	}
	# Reorganizing symptoms by dates.
	my ($hasSymptoms, %symptomsByDates) = subject_symptoms_by_dates($subjectId);
	die unless keys %symptomsByDates && $hasSymptoms;
	# if ($subjectId eq '10111148') {
	# 	p$pdfCases{$subjectId};
	# 	p$randomization{$subjectId};
	# 	p%pcrsByDates;
	# 	p%symptomsByDates;
	# 	die;
	# }
	# p$pdfCases{$subjectId};
	# p$randomization{$subjectId};
	# p%pcrsByDates;
	# p%symptomsByDates;
	my $dose1Date = $randomization{$subjectId}->{'dose1Date'} // die;
	my $swabDate  = $pdfCases{$subjectId}->{'swabDate'}       // die;
	my $randomizationGroup = $randomization{$subjectId}->{'randomizationGroup'} // 'Unknown';
	die if $swabDate <= $dose1Date;
	my ($firstPCRPositiveDate, $firstSymptomDate);
	for my $symptomCompdate (sort{$a <=> $b} keys %symptomsByDates) {
		my $symptomDatetime = $symptomsByDates{$symptomCompdate}->{'symptomDatetime'} // die;
		my ($symptomDate)   = split ' ', $symptomDatetime;
		my $totalSymptoms   = $symptomsByDates{$symptomCompdate}->{'totalSymptoms'}   || die;
		my $visitName       = $symptomsByDates{$symptomCompdate}->{'visitName'}       || die;

		# Fetching nearest test from the symptoms occurence.
		my $symptomsWithTest = 0;
		my $closestDayFromSymptomToTest = 99;
		for my $visitCompdate (sort{$a <=> $b} keys %pcrsByDates) {
			my $visitDate      = $pcrsByDates{$visitCompdate}->{'visitDate'} // die;
			my $pcrResult      = $pcrsByDates{$visitCompdate}->{'pcrResult'} // die;
			my $visitDatetime  = "$visitDate 12:00:00";
			my $daysDifference = time::calculate_days_difference($symptomDatetime, $visitDatetime);
			if (!$symptomsBeforePCR) { # If symptomsBeforePCR = 0, skipping the symptoms which have occured before the PCR.
				next if $symptomCompdate < $visitCompdate; # Verify that the symptom have occured on the day or after the PCR.
			}
			next if $daysDifference > $daysOffset;
			# say "visitDate                   : $visitDate";
			# say "pcrResult                   : $pcrResult";
			# say "daysDifference              : $daysDifference";
			# die;
			$symptomsWithTest = 1;
			my $difToZero = abs(0 - $daysDifference);
			$closestDayFromSymptomToTest = $difToZero if $difToZero < $closestDayFromSymptomToTest;
			if ($pcrResult eq 'POS') {
				unless ($firstPCRPositiveDate) {
					$firstPCRPositiveDate = $visitDate;
					$firstSymptomDate = $symptomDate;
				}
			}
			# say "$symptomDatetime -> $visitDate ($daysDifference days | $pcrResult)";
		}
	}
	unless ($firstPCRPositiveDate) {
		for my $visitCompdate (sort{$a <=> $b} keys %pcrsByDates) {
			if ($pcrsByDates{$visitCompdate}->{'pcrResult'} eq 'POS') {
				$firstPCRPositiveDate = $visitCompdate;
				last;
			}
		}
	}
	unless ($firstPCRPositiveDate && $firstSymptomDate) {
		$firstPCRPositiveDate = '' unless $firstPCRPositiveDate;
		$firstSymptomDate = '' unless $firstSymptomDate;
		say "subject [$subjectId] is missing either a PCR date [$firstPCRPositiveDate] or a symptom date [$firstSymptomDate].";
	}
	$firstPCRPositiveDate =~ s/\D//g;
	$firstSymptomDate     =~ s/\D//g;
	if ($firstPCRPositiveDate) {
		say "subject [$subjectId] ($randomizationGroup) - Positive PCR on [$firstPCRPositiveDate], <= dose 1 on [$dose1Date], first symptoms on [$firstSymptomDate]" if $firstPCRPositiveDate <= $dose1Date;
	}
	if ($firstSymptomDate) {
		say "subject [$subjectId] ($randomizationGroup) - Positive Symptoms on [$firstSymptomDate], <= dose 1 on [$dose1Date], first PCR on [$firstPCRPositiveDate]" if $firstSymptomDate <= $dose1Date;
	}
	# die;
}

sub subject_pcrs_by_dates {
	my $subjectId      = shift;
	my %pcrsByDates    = ();
	my $hasPositivePCR = 0;
	for my $visitDate (sort keys %{$pcrTests{$subjectId}->{'mbVisits'}}) {

		# Skips the visits unless it contains PCRs.
		next unless exists $pcrTests{$subjectId}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'};
		my $visitCompdate = $visitDate;
		$visitCompdate =~ s/\D//g;

		# Skips the visit unless it fits with the phase 3.
		next unless $visitCompdate >= 20200720;
		next unless $visitCompdate <= 20201114;
		my $pcrResult = $pcrTests{$subjectId}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'}->{'mbResult'} // die;
		$pcrsByDates{$visitCompdate}->{'visitDate'} = $visitDate;
		$pcrsByDates{$visitCompdate}->{'pcrResult'} = $pcrResult;
		if ($pcrResult eq 'POS') {
			$hasPositivePCR = 1;
		}
	}
	return ($hasPositivePCR,
		%pcrsByDates);
}

sub subject_symptoms_by_dates {
	my $subjectId       = shift;
	# die;
	my %symptomsByDates = ();
	my $hasSymptoms     = 0;
	for my $symptomDatetime (sort keys %{$symptoms{$subjectId}->{'symptomsReports'}}) {
		my ($symptomDate)   = split ' ', $symptomDatetime;
		my $symptomCompdate = $symptomDate;
		$symptomCompdate    =~ s/\D//g;
		next unless $symptomCompdate <= 20201114;
		my $totalSymptoms   = 0;
		for my $symptomName (sort keys %{$symptoms{$subjectId}->{'symptomsReports'}->{$symptomDatetime}->{'symptoms'}}) {
			next unless $symptoms{$subjectId}->{'symptomsReports'}->{$symptomDatetime}->{'symptoms'}->{$symptomName} eq 'Y';
			my $symptomCategory = symptom_category_from_symptom($symptomName);
			if ($officialSymptomsOnly) {
				next unless $symptomCategory eq 'OFFICIAL';
			}
			$symptomsByDates{$symptomCompdate}->{'symptoms'}->{$symptomName} = 1;
			$totalSymptoms++;
		}
		next unless $totalSymptoms;
		$hasSymptoms = 1;
		$symptomsByDates{$symptomCompdate}->{'visitName'}       = $symptoms{$subjectId}->{'symptomsReports'}->{$symptomDatetime}->{'visitName'};
		$symptomsByDates{$symptomCompdate}->{'symptomDatetime'} = $symptomDatetime;
		$symptomsByDates{$symptomCompdate}->{'totalSymptoms'}   = $totalSymptoms;
	}
	# die;
	return ($hasSymptoms,
		%symptomsByDates);
}

sub symptom_category_from_symptom {
	my $symptomName = shift;
	my $symptomCategory;
	if (
		$symptomName eq 'NEW OR INCREASED COUGH' ||
		$symptomName eq 'NEW OR INCREASED SORE THROAT' ||
		$symptomName eq 'CHILLS' ||
		$symptomName eq 'FEVER' ||
		$symptomName eq 'DIARRHEA' ||
		$symptomName eq 'NEW LOSS OF TASTE OR SMELL' ||
		$symptomName eq 'NEW OR INCREASED SHORTNESS OF BREATH' ||
		$symptomName eq 'NEW OR INCREASED MUSCLE PAIN' ||
		$symptomName eq 'VOMITING'
	) {
		$symptomCategory = 'OFFICIAL';
	} elsif (
		$symptomName eq 'NEW OR INCREASED NASAL CONGESTION' ||
		$symptomName eq 'HEADACHE' ||
		$symptomName eq 'FATIGUE' ||
		$symptomName eq 'RHINORRHOEA' ||
		$symptomName eq 'NAUSEA' ||
		$symptomName eq 'NEW OR INCREASED WHEEZING'
	) {
		$symptomCategory = 'SECONDARY';
	} else {
		die "symptomName : $symptomName";
	}
	return $symptomCategory;
}