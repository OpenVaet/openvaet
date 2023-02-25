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

my $exclusionsFile    = 'public/doc/pfizer_trials/pfizer_excluded_patients.json';
my $deviationsFile    = 'public/doc/pfizer_trials/pfizer_sddv_patients.json';
my $pcrTestsFile      = 'public/doc/pfizer_trials/pfizer_mb_patients.json';
my $symptomsFile      = 'public/doc/pfizer_trials/pfizer_patients_symptoms.json';
my $randomizationFile = 'public/doc/pfizer_trials/merged_doses_data.json';
my $p1SubjectsFile    = 'public/doc/pfizer_trials/phase1Subjects.json';
my $demographicFile   = 'public/doc/pfizer_trials/pfizer_trial_demographics_merged.json';
my $pdfCasesFile      = 'public/doc/pfizer_trials/pfizer_trial_cases_merged.json';
my $daysOffset        = 5;

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

# Flushing .PDF cases prior cut-off
for my $subjectId (sort{$a <=> $b} keys %pdfCases) {
	unless ($pdfCases{$subjectId}->{'swabDate'} <= 20201114) {
		delete $pdfCases{$subjectId};
	}
}

# First isolating subjects with positive PCRs & positive PCRs with symptoms.
my %subjectsWithPositivePCRs = ();
my ($totalPositivePCRs, $totalPCRs, $totalPositivePCRsSubjects, $positiveCovidWithoutSymptoms, $positiveCovidWithSymptoms) = (0, 0, 0, 0, 0);
for my $subjectId (sort{$a <=> $b} keys %pcrTests) {
	# next if exists $phase1Subjects{$subjectId};
	my $hasPositivePCRPreCutOff = 0;
	my $firstPositivePCRDate;
	my %visitsByDates = ();
	my $randomizationGroup = $randomization{$subjectId}->{'randomizationGroup'} // 'Unknown';
	for my $visitDate (sort keys %{$pcrTests{$subjectId}->{'mbVisits'}}) {
		next unless exists $pcrTests{$subjectId}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'};
		my $compdate = $visitDate;
		$compdate =~ s/\D//g;
		next unless $compdate >= 20200720;
		next unless $compdate <= 20201114;
		my $pcrResult = $pcrTests{$subjectId}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'}->{'mbResult'} // die;
		$totalPCRs++;
		if ($pcrResult eq 'POS') {
			# say "visitDate         : $visitDate";
			# say "pcrResult         : $pcrResult";
			$totalPositivePCRs++;
			$hasPositivePCRPreCutOff = 1;
			$visitsByDates{$compdate}->{'visitDate'} = $visitDate;
			$visitsByDates{$compdate}->{'Cepheid RT-PCR assay for SARS-CoV-2'} = $pcrResult;
			$subjectsWithPositivePCRs{$subjectId}->{'randomizationGroup'} = $randomizationGroup;
			$subjectsWithPositivePCRs{$subjectId}->{'positivePCR'}->{$compdate}->{'visitDate'} = $visitDate;
			$subjectsWithPositivePCRs{$subjectId}->{'positivePCR'}->{$compdate}->{'Cepheid RT-PCR assay for SARS-CoV-2'} = $pcrResult;
		}
	}
	if ($hasPositivePCRPreCutOff) {
		# say "*" x 50;
		# say "subjectId            : $subjectId";
		for my $compdate (sort{$a <=> $b} keys %visitsByDates) {
			$firstPositivePCRDate = $compdate;
			last;
		}
		# say "firstPositivePCRDate : $firstPositivePCRDate";
		my ($fY, $fM, $fD) = $firstPositivePCRDate =~ /(....)(..)(..)/;
		$firstPositivePCRDate = "$fY-$fM-$fD 12:00:00";
		$totalPositivePCRsSubjects++;
		$subjectsWithPositivePCRs{$subjectId}->{'firstPositivePCRDate'} = $firstPositivePCRDate;
		my $hasCovidWithSymptoms = 0;
		my $closestDayFromSymptomToCovid = 99;
		unless (exists $symptoms{$subjectId}) {
			$positiveCovidWithoutSymptoms++;
			$stats{'positiveWithoutSymptoms'}->{$randomizationGroup}++;
			$closestDayFromSymptomToCovid = undef;
		} else {

			# Verifying offset between symptoms & positive diagnose.
			for my $visitCompdate (sort{$a <=> $b} keys %visitsByDates) {
				my $visitDate = $visitsByDates{$visitCompdate}->{'visitDate'} // die;
				$visitDate = "$visitDate 12:00:00";
				for my $symptomDatetime (sort keys %{$symptoms{$subjectId}->{'symptoms'}}) {
					my ($symptomDate)   = split ' ', $symptomDatetime;
					my $symptomCompdate = $symptomDate;
					$symptomCompdate    =~ s/\D//g;
					next unless $symptomCompdate <= 20201114;
					my $daysDifference = time::calculate_days_difference($symptomDatetime, $visitDate);
					$visitsByDates{$symptomDatetime}->{'daysDifference'} = $daysDifference;
					if ($daysDifference >= 0) {
						if ($daysDifference <= $daysOffset) {
							$hasCovidWithSymptoms = 1;
							my $difToZero = abs(0 - $daysDifference);
							$closestDayFromSymptomToCovid = $difToZero if $difToZero < $closestDayFromSymptomToCovid;
							for my $symptomName (sort keys %{$symptoms{$subjectId}->{'symptoms'}->{$symptomDatetime}}) {
								next unless $symptoms{$subjectId}->{'symptoms'}->{$symptomDatetime}->{$symptomName} eq 'Y';
								$subjectsWithPositivePCRs{$subjectId}->{'positivePCR'}->{$visitCompdate}->{'symptoms'}->{$daysDifference}->{$symptomName} = $symptomDatetime;
							}
						}
					} else {
						if ($daysDifference < 0 && $daysDifference >= "-$daysOffset") {
							$hasCovidWithSymptoms = 1;
							my $difToZero = abs(0 - $daysDifference);
							$closestDayFromSymptomToCovid = $difToZero if $difToZero < $closestDayFromSymptomToCovid;
							for my $symptomName (sort keys %{$symptoms{$subjectId}->{'symptoms'}->{$symptomDatetime}}) {
								next unless $symptoms{$subjectId}->{'symptoms'}->{$symptomDatetime}->{$symptomName} eq 'Y';
								$subjectsWithPositivePCRs{$subjectId}->{'positivePCR'}->{$visitCompdate}->{'symptoms'}->{$daysDifference}->{$symptomName} = $symptomDatetime;
							}
						}
					}
					# say "$symptomDatetime -> $visitDate ($daysDifference days)";
				}
			}
			# say "------>";
			# say "hasCovidWithSymptoms         : $hasCovidWithSymptoms";
			# say "closestDayFromSymptomToCovid : $closestDayFromSymptomToCovid";
			# p$symptoms{$subjectId};
			# die;
			if ($hasCovidWithSymptoms) {
				$positiveCovidWithSymptoms++;
				$stats{'positiveWithSymptoms'}->{$randomizationGroup}++;
				$stats{'positiveWithSymptoms'}->{'total'}++;
				unless (exists $pdfCases{$subjectId}) {
					# say "Subject [$subjectId] ($randomizationGroup) isn't listed as a case in PDF.";
					$stats{'pdfCases'}->{'nonListedInPDF'}->{$randomizationGroup}->{'total'}++;
					# $stats{'pdfCases'}->{'nonListedInPDF'}->{$randomizationGroup}->{'subjects'}->{$subjectId}++;
				}
				# p$randomization{$subjectId};
				# die;
			} else {
				$closestDayFromSymptomToCovid = undef;
				$positiveCovidWithoutSymptoms++;
				$stats{'positiveWithoutSymptoms'}->{$randomizationGroup}++;
			}
			$subjectsWithPositivePCRs{$subjectId}->{'hasCovidWithSymptoms'} = $hasCovidWithSymptoms;
		}
		$stats{'totalPositivePCRs'}->{$randomizationGroup}++;
		$stats{'totalPositivePCRs'}->{'total'}++;
	}
}
# p%subjectsWithPositivePCRs;
say "*" x 50;
say "*" x 50;
say "positiveCovidWithSymptoms    : $positiveCovidWithSymptoms";
say "positiveCovidWithoutSymptoms : $positiveCovidWithoutSymptoms";
say "totalPositivePCRsSubjects    : $totalPositivePCRsSubjects";
say "totalPositivePCRs            : $totalPositivePCRs";
say "totalPCRs                    : $totalPCRs";

# Verifying if we found all the positive cases listed in the .PDF.
for my $subjectId (sort{$a <=> $b} keys %pdfCases) {
	next unless $pdfCases{$subjectId}->{'swabDate'} <= 20201114;
	# die;
	my $randomizationGroup = $randomization{$subjectId}->{'randomizationGroup'} // 'Unknown';
	unless ($subjectsWithPositivePCRs{$subjectId}->{'hasCovidWithSymptoms'}) {
		# say "Subject [$subjectId] ($randomizationGroup) is listed as a case in PDF but doesn't come out from analysis.";
		$stats{'pdfCases'}->{'notFoundOnAnalysis'}->{$randomizationGroup}->{'total'}++;
		$stats{'pdfCases'}->{'notFoundOnAnalysis'}->{$randomizationGroup}->{'subjects'}->{$subjectId}++;
	}
	$stats{'pdfCases'}->{'total'}->{$randomizationGroup}++;
}
# p%stats;
# die;

# Then isolating subjects who had "Covid-like" symptoms.
my %symptomsByGroups     = ();
my %subjectsWithSymptoms = ();
for my $subjectId (sort{$a <=> $b} keys %symptoms) {
	next if exists $phase1Subjects{$subjectId};
	my $randomizationGroup  = $randomization{$subjectId}->{'randomizationGroup'} // 'Unknown';
	my $ageYears            = $demographics{$subjectId}->{'ageYears'}            // 'Unknown';
	if (exists $exclusions{$subjectId}) {
		# p$exclusions{$subjectId};
		# die;
		$stats{'excludedSubjects'}->{$randomizationGroup}++;
		# next;
	}
	# p$symptoms{$subjectId};
	# die;
	my %symptomsByDates = ();
	for my $symptomDatetime (sort keys %{$symptoms{$subjectId}->{'symptoms'}}) {
		my ($symptomDate)   = split ' ', $symptomDatetime;
		my $symptomCompdate = $symptomDate;
		$symptomCompdate    =~ s/\D//g;
		next unless $symptomCompdate <= 20201114;
		# p$demographics{$subjectId};
		# die;
		my $totalSymptoms       = 0;
		for my $symptomName (sort keys %{$symptoms{$subjectId}->{'symptoms'}->{$symptomDatetime}}) {
			next unless $symptoms{$subjectId}->{'symptoms'}->{$symptomDatetime}->{$symptomName} eq 'Y';
			$totalSymptoms++;
		}
		next unless $totalSymptoms;
		$symptomsByGroups{$randomizationGroup}->{'total'}++;
		$symptomsByDates{$symptomCompdate} = $symptomDatetime;
	}
	next unless keys %symptomsByDates;
	my %visitsByDates = ();
	for my $visitDate (sort keys %{$pcrTests{$subjectId}->{'mbVisits'}}) {
		next unless exists $pcrTests{$subjectId}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'};
		my $visitCompdate = $visitDate;
		$visitCompdate =~ s/\D//g;
		next unless $visitCompdate >= 20200720;
		next unless $visitCompdate <= 20201114;
		my $pcrResult = $pcrTests{$subjectId}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'}->{'mbResult'} // die;
		$visitsByDates{$visitCompdate}->{'visitDate'} = $visitDate;
		$visitsByDates{$visitCompdate}->{'Cepheid RT-PCR assay for SARS-CoV-2'} = $pcrResult;
	}

	# say "*" x 50;
	# say "subjectId            : $subjectId";
	# say "randomizationGroup   : $randomizationGroup";
	my $lastCovidDate;
	my $hadCovidWithTest            = 0;
	my $hadCovidSymptoms            = 0;
	my $hasSymptomsWithPositiveTest = 0;
	for my $symptomCompdate (sort{$a <=> $b} keys %symptomsByDates) {
		my $symptomDatetime = $symptomsByDates{$symptomCompdate} // die;
		# say "symptomDatetime             : $symptomDatetime";
		my $totalSymptoms       = 0;
		for my $symptomName (sort keys %{$symptoms{$subjectId}->{'symptoms'}->{$symptomDatetime}}) {
			next unless $symptoms{$subjectId}->{'symptoms'}->{$symptomDatetime}->{$symptomName} eq 'Y';
			$totalSymptoms++;
		}
		die unless $totalSymptoms;
		$hadCovidSymptoms = 1;
		if ($lastCovidDate) {
			my $lastCovidDatetime = "$lastCovidDate 12:00:00";
			my $daysDifferenceToPositiveCovid = time::calculate_days_difference($symptomDatetime, $lastCovidDatetime);
			next if $daysDifferenceToPositiveCovid < 21;			
		}
		# $symptomsByGroups{$randomizationGroup}->{'byTotalSymptoms'}->{$totalSymptoms}++;

		# Fetching nearest test from the symptoms occurence.
		my $hasSymptomsWithTest = 0;
		my $closestDayFromSymptomToTest = 99;
		# $symptomsByGroups{$randomizationGroup}->{'byAges'}->{$ageYears}++;
		# say "symptomCompdate : $symptomCompdate";
		# die;
		for my $visitCompdate (sort{$a <=> $b} keys %visitsByDates) {
			my $visitDate = $visitsByDates{$visitCompdate}->{'visitDate'} // die;
			my $pcrResult = $pcrTests{$subjectId}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'}->{'mbResult'} // die;
			$visitDate    = "$visitDate 12:00:00";
			my $daysDifference = time::calculate_days_difference($symptomDatetime, $visitDate);
			next if $visitCompdate < $symptomCompdate;
			last if $visitCompdate > $symptomCompdate && $daysDifference > $daysOffset;
			$hasSymptomsWithTest = 1;
			my $difToZero = abs(0 - $daysDifference);
			$closestDayFromSymptomToTest = $difToZero if $difToZero < $closestDayFromSymptomToTest;
			if ($pcrResult eq 'POS') {
				$hasSymptomsWithPositiveTest = 1;
				$lastCovidDate = $visitDate;
			}
			# say "$symptomDatetime -> $visitDate ($daysDifference days | $pcrResult)";
		}
		# say "hasSymptomsWithTest         : $hasSymptomsWithTest";
		# say "closestDayFromSymptomToTest : $closestDayFromSymptomToTest";
		if ($hasSymptomsWithTest) {
			$hadCovidWithTest = 1;
			$stats{'symptomsWithTest'}->{$randomizationGroup}->{'total'}++;
			die if $lastCovidDate && !$subjectsWithPositivePCRs{$subjectId}->{'hasCovidWithSymptoms'};
		} else {
			$stats{'symptomsWithoutTest'}->{$randomizationGroup}->{'total'}++;
		}
		$stats{'withSymptoms'}->{$randomizationGroup}->{'total'}++;
		$stats{'withSymptoms'}->{'total'}++;
	}
	if ($hadCovidSymptoms) {
		$stats{'subjectsWithSymptoms'}->{$randomizationGroup}->{'total'}++;
		$stats{'subjectsWithSymptoms'}->{'total'}++;
	}
	if ($hadCovidWithTest) {
		$stats{'subjectsWithSymptomsAndTest'}->{$randomizationGroup}->{'total'}++;
		$stats{'subjectsWithSymptomsAndTest'}->{'total'}++;
	}
	if ($hasSymptomsWithPositiveTest) {
		$stats{'subjectsWithSymptomsAndPositiveTest'}->{$randomizationGroup}->{'total'}++;
		$stats{'subjectsWithSymptomsAndPositiveTest'}->{'total'}++;
	}
}
p%symptomsByGroups;
p%stats;

# Displaying subtraction "total symptomatic" - "found positive with symptoms"
for my $arm (sort keys %symptomsByGroups) {
	my $symptomatic = $symptomsByGroups{$arm}->{'total'} // die;
	my $positiveWithSymptoms = $stats{'positiveWithSymptoms'}->{$arm} // die;
	my $offset = $symptomatic - $positiveWithSymptoms;
	# say "[$arm] -> $symptomatic - $positiveWithSymptoms = [$offset]";
}
die;