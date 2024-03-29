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
my $daysOffset           = 15;
my $symptomsBeforePCR    = 1; # 0 = before non included ; 1 = before included.
my $officialSymptomsOnly = 0; # 0 = secondary symptoms taken into account ; 1 = secondary symptoms included.
my $cutoffCompdate       = '20201114';

# Loading data required.
my $exclusionsFile    = 'public/doc/pfizer_trials/pfizer_excluded_patients.json';
my $deviationsFile    = 'public/doc/pfizer_trials/pfizer_sddv_patients.json';
my $pcrRecordsFile    = 'public/doc/pfizer_trials/pfizer_mb_patients.json';
my $faceFile          = 'public/doc/pfizer_trials/pfizer_face_patients.json';
my $symptomsFile      = 'public/doc/pfizer_trials/pfizer_patients_symptoms.json';
my $randomizationFile = 'public/doc/pfizer_trials/merged_doses_data.json';
my $p1SubjectsFile    = 'public/doc/pfizer_trials/phase1Subjects.json';
my $testsRefsFile     = 'public/doc/pfizer_trials/pfizer_di.json';
my $demographicFile   = 'public/doc/pfizer_trials/pfizer_trial_demographics_merged.json';
my $pdfCasesFile      = 'public/doc/pfizer_trials/pfizer_trial_cases_merged.json';
my $centralPCRsFile   = 'public/doc/pfizer_trials/subjects_with_pcr_and_symptoms.json';
my $advaFile          = "public/doc/pfizer_trials/pfizer_adva_patients.json";
my %advaData          = ();
my %faces             = ();
my %demographics      = ();
my %phase1Subjects    = ();
my %exclusions        = ();
my %deviations        = ();
my %pcrRecords        = ();
my %symptoms          = ();
my %randomization     = ();
my %pdfCases          = ();
my %testsRefs         = ();
load_demographics();
load_phase_1();
load_faces();
load_randomization();
load_exclusions();
load_deviations();
load_pcr_tests();
load_symptoms();
load_pdf_cases();
load_tests_refs();
load_adva_data();

my %stats = ();
symptoms_positive_data();

# Printing breakdown by test.
open my $out1, '>:utf8', 'breakdown_by_tests.csv';
say $out1 "Test;Total;";
for my $test (sort keys %{$stats{'localPCRsAnalysis'}}) {
	my $total = $stats{'localPCRsAnalysis'}->{$test} // die;
	say $out1 "$test;$total;";
}
close $out1;
p%stats;

sub load_demographics {
	open my $in, '<:utf8', $demographicFile or die "Missing file [$demographicFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%demographics = %$json;
	say "[$demographicFile] -> subjects : " . keys %demographics;
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

sub load_faces {
	open my $in, '<:utf8', $faceFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%faces = %$json;
	# p%faces;die;
	say "[$faceFile] -> subjects : " . keys %faces;
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
	open my $in, '<:utf8', $pcrRecordsFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%pcrRecords = %$json;
	# p$pcrRecords{'44441222'};
	say "[$pcrRecordsFile] -> subjects : " . keys %pcrRecords;
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

sub load_adva_data {
	open my $in, '<:utf8', $advaFile or die "Missing file [$advaFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%advaData = %$json;
	say "[$advaFile] -> patients : " . keys %advaData;
}

sub load_tests_refs {
	open my $in, '<:utf8', $testsRefsFile or die "Missing file [$testsRefsFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%testsRefs = %$json;
	say "[$testsRefsFile] -> tests    : " . keys %testsRefs;
}

# Then isolating subjects who had "Covid-like" symptoms.
sub symptoms_positive_data {
	my %subjectsVisits = ();
	open my $out, '>:utf8', 'conflicts_negative_to_positive.csv';
	say $out "subjectId;randomizationGroup;symptomDatetime;visitName;hasOfficialSymptoms;closestDayFromSymptomToLocalPCR;symptomsWithPositiveLocalPCR;symptomsWithPositiveCentralPCR;";
	for my $subjectId (sort{$a <=> $b} keys %symptoms) {
		die if exists $phase1Subjects{$subjectId};
		my $randomizationGroup  = $randomization{$subjectId}->{'randomizationGroup'} // 'Unknown';
		my $ageYears            = $demographics{$subjectId}->{'ageYears'}            // 'Unknown';
		my $unblindDatetime     = $advaData{$subjectId}->{'unblindDatetime'};
		$randomizationGroup     = 'BNT162b2' if $randomizationGroup =~ /BNT162b2 \(30/;
		my $unblindCompdate     = $cutoffCompdate;
		if ($unblindDatetime) {
			($unblindCompdate)   = split ' ', $unblindDatetime;
			$unblindCompdate        =~ s/\D//g;
		}
		# die "unblindDatetime : $unblindDatetime";

		# Reorganizing symptoms by dates.
		my ($hasSymptoms, %symptomsByDates) = subject_symptoms_by_dates($subjectId, $unblindCompdate);
		next unless keys %symptomsByDates && $hasSymptoms;

		$stats{'symptomsAnalysis'}->{'subjects'}->{'withSymptoms'}->{'total'}++;
		$stats{'symptomsAnalysis'}->{'subjects'}->{'withSymptoms'}->{$randomizationGroup}++;
		next if $randomizationGroup eq 'Unknown';

		# Reorganizing Central PCRs by dates.
		my ($hasPositiveCentralPCR,
			%centralPCRsByDates)    = subject_central_pcrs_by_dates($subjectId, $unblindCompdate);

		# Reorganizing Local PCRs by dates.
		my ($hasPositiveLocalPCR,
			%localPCRsByDates)      = subject_local_pcrs_by_dates($subjectId, $unblindCompdate);
		# if ($subjectId eq '10071444') {
		# 	say "*" x 50;
		# 	say "subjectId            : $subjectId";
		# 	say "randomizationGroup   : $randomizationGroup";
		# 	say "central              :";
		# 	p%centralPCRsByDates;
		# 	say "local                :";
		# 	p%localPCRsByDates;
		# 	say "symptoms by dates    :";
		# 	p%symptomsByDates;
		# 	die;
		# }
		if (exists $faces{$subjectId}) {
			$stats{'faceData'}->{'subjects'}->{'total'}++;
			$stats{'faceData'}->{'subjects'}->{$randomizationGroup}++;
		} else {
			die;
		}
		for my $symptomCompdate (sort{$a <=> $b} keys %symptomsByDates) {
			my $symptomDate         = $symptomsByDates{$symptomCompdate}->{'symptomDate'}         // die;
			my $totalSymptoms       = $symptomsByDates{$symptomCompdate}->{'totalSymptoms'}       || die;
			my $visitName           = $symptomsByDates{$symptomCompdate}->{'visitName'}           || die;
			my $hasOfficialSymptoms = $symptomsByDates{$symptomCompdate}->{'hasOfficialSymptoms'} // die;
			my $symptomDatetime     = "$symptomDate 12:00:00";
			# say "symptomDatetime             : $symptomDatetime";
			# say "totalSymptoms               : $totalSymptoms";
			# say "visitName                   : $visitName";
			$stats{'symptomsAnalysis'}->{'visitsDates'}->{'total'}++;
			$stats{'symptomsAnalysis'}->{'visitsDates'}->{$randomizationGroup}++;

			unless (exists $subjectsVisits{$subjectId}->{$visitName}) {
				$subjectsVisits{$subjectId}->{$visitName} = 1;
				$stats{'symptomsAnalysis'}->{'visits'}->{'total'}++;
				$stats{'symptomsAnalysis'}->{'visits'}->{$randomizationGroup}++;
			}

			# Fetching nearest test from the symptoms occurence.
			my $symptomsWithCentralPCR            = 0;
			my $symptomsWithLocalPCR              = 0;
			my $symptomsWithPositiveCentralPCR    = 0;
			my $symptomsWithPositiveLocalPCR      = 0;
			my $closestDayFromSymptomToCentralPCR = 99;
			my $closestDayFromSymptomToLocalPCR   = 99;
			# $symptomsByGroups{$randomizationGroup}->{'byAges'}->{$ageYears}++;
			# say "symptomCompdate : $symptomCompdate";
			# die;
			# p%centralPCRsByDates;
			# die;
			for my $visitCompdate (sort{$a <=> $b} keys %centralPCRsByDates) {
				my $visitDate      = $centralPCRsByDates{$visitCompdate}->{'visitDate'} // die;
				my $pcrResult      = $centralPCRsByDates{$visitCompdate}->{'pcrResult'} // die;
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
				$symptomsWithCentralPCR = 1;
				my $difToZero = abs(0 - $daysDifference);
				$closestDayFromSymptomToCentralPCR = $difToZero if $difToZero < $closestDayFromSymptomToCentralPCR;
				if ($pcrResult eq 'POS') {
					$symptomsWithPositiveCentralPCR = 1;
				}
				# say "$symptomDatetime -> $visitDate ($daysDifference days | $pcrResult)";
			}
			my %localDevices = ();
			my %localPositiveDevices = ();
			for my $visitCompdate (sort{$a <=> $b} keys %localPCRsByDates) {
				my $visitDate      = $localPCRsByDates{$visitCompdate}->{'visitDate'} // die;
				my $pcrResult      = $localPCRsByDates{$visitCompdate}->{'pcrResult'} // die;
				my $spDevId        = $localPCRsByDates{$visitCompdate}->{'spDevId'}   // die;
				my $visitDatetime  = "$visitDate 12:00:00";
				my $daysDifference = time::calculate_days_difference($symptomDatetime, $visitDatetime);
				if (!$symptomsBeforePCR) { # If symptomsBeforePCR = 0, skipping the symptoms which have occured before the PCR.
					next if $symptomCompdate < $visitCompdate; # Verify that the symptom have occured on the day or after the PCR.
				}
				next if $daysDifference > $daysOffset;
				$localDevices{$spDevId} = $pcrResult;
				# say "visitDate                   : $visitDate";
				# say "pcrResult                   : $pcrResult";
				# say "daysDifference              : $daysDifference";
				# die;
				$symptomsWithLocalPCR = 1;
				my $difToZero = abs(0 - $daysDifference);
				$closestDayFromSymptomToLocalPCR = $difToZero if $difToZero < $closestDayFromSymptomToLocalPCR;
				if ($pcrResult eq 'POS') {
					$symptomsWithPositiveLocalPCR = 1;
					$localPositiveDevices{$spDevId} = $pcrResult;
				}
				# say "$symptomDatetime -> $visitDate ($daysDifference days | $pcrResult)";
			}
			# say "symptomsWithCentralPCR         : $symptomsWithCentralPCR";
			# say "closestDayFromSymptomToCentralPCR : $closestDayFromSymptomToCentralPCR";
			if ($symptomsWithCentralPCR) {
				if ($symptomsWithPositiveCentralPCR == 1) {
					$stats{'symptomsAnalysis'}->{'symptoms'}->{'central'}->{'symptomsWithPCR'}->{'positivePCR'}->{$randomizationGroup}++;
					$stats{'symptomsAnalysis'}->{'symptoms'}->{'central'}->{'symptomsWithPCR'}->{'positivePCR'}->{'total'}++;
				}
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'central'}->{'symptomsWithPCR'}->{$randomizationGroup}++;
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'central'}->{'symptomsWithPCR'}->{'total'}++;
			} else {
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'central'}->{'symptomsWithoutPCR'}->{$randomizationGroup}++;
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'central'}->{'symptomsWithoutPCR'}->{'total'}++;
			}
			if ($symptomsWithLocalPCR) {
				if ($symptomsWithPositiveLocalPCR == 1) {
					$stats{'symptomsAnalysis'}->{'symptoms'}->{'local'}->{'symptomsWithPCR'}->{'positivePCR'}->{$randomizationGroup}++;
					$stats{'symptomsAnalysis'}->{'symptoms'}->{'local'}->{'symptomsWithPCR'}->{'positivePCR'}->{'total'}++;
				}
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'local'}->{'symptomsWithPCR'}->{$randomizationGroup}++;
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'local'}->{'symptomsWithPCR'}->{'total'}++;
			} else {
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'local'}->{'symptomsWithoutPCR'}->{$randomizationGroup}++;
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'local'}->{'symptomsWithoutPCR'}->{'total'}++;
			}
			if ($symptomsWithCentralPCR || $symptomsWithLocalPCR) {
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'localOrCentral'}->{'symptomsWithPCR'}->{$randomizationGroup}++;
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'localOrCentral'}->{'symptomsWithPCR'}->{'total'}++;
			} else {
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'localOrCentral'}->{'symptomsWithoutPCR'}->{$randomizationGroup}++;
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'localOrCentral'}->{'symptomsWithoutPCR'}->{'total'}++;
			}
			if ($symptomsWithCentralPCR && $symptomsWithLocalPCR) {
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'symptomsWithPCR'}->{$randomizationGroup}++;
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'symptomsWithPCR'}->{'total'}++;

				if ($symptomsWithPositiveLocalPCR == 0 && $symptomsWithPositiveCentralPCR == 1) {
					$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'negativeLocalPositiveCentral'}->{$randomizationGroup}++;
					$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'negativeLocalPositiveCentral'}->{'total'}++;
				}
				if ($symptomsWithPositiveLocalPCR == 1 && $symptomsWithPositiveCentralPCR == 0) {
					say $out "$subjectId;$randomizationGroup;$symptomDatetime;$visitName;$hasOfficialSymptoms;$closestDayFromSymptomToLocalPCR;$symptomsWithPositiveLocalPCR;$symptomsWithPositiveCentralPCR;";
					$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'positiveLocalNegativeCentral'}->{$randomizationGroup}++;
					$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'positiveLocalNegativeCentral'}->{'total'}++;
				}

				if (
					($symptomsWithPositiveCentralPCR == 1 && $symptomsWithPositiveLocalPCR == 1) ||
					($symptomsWithPositiveCentralPCR == 0 && $symptomsWithPositiveLocalPCR == 0)
				) {
					$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'noConflict'}->{$randomizationGroup}++;
					$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'noConflict'}->{'total'}++;
				} else {
					if ($symptomsWithPositiveLocalPCR == 1) {
						unless (keys %localDevices == keys %localPositiveDevices) {
							p%localDevices;
							p%localPositiveDevices;
							say "subjectId : $subjectId - conflict between local results";
							# die;
						}
					}
					$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'conflict'}->{'byGroups'}->{$randomizationGroup}->{'total'}++;
					for my $device (sort keys %localDevices) {
						$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'conflict'}->{'byDevices'}->{$device}++;
					}
					$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'conflict'}->{'total'}++;
				}
			} else {
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'symptomsWithoutPCR'}->{$randomizationGroup}++;
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'symptomsWithoutPCR'}->{'total'}++;
			}
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'symptomsSets'}->{$randomizationGroup}->{'total'}++;
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'symptomsSets'}->{'total'}++;
		}
	}
	close $out;
}

sub subject_central_pcrs_by_dates {
	my ($subjectId,
		$unblindCompdate) = @_;
	my %centralPCRsByDates    = ();
	my $hasPositiveCentralPCR = 0;
	my $referenceCompdate = ref_from_unblind($unblindCompdate);
	for my $visitDate (sort keys %{$pcrRecords{$subjectId}->{'mbVisits'}}) {

		# Skips the visits unless it contains PCRs.
		next unless exists $pcrRecords{$subjectId}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'};
		my $visitCompdate = $visitDate;
		$visitCompdate =~ s/\D//g;

		# Skips the visit unless it fits with the phase 3.
		next unless $visitCompdate >= 20200720;
		next unless $visitCompdate <= $referenceCompdate;
		my $pcrResult = $pcrRecords{$subjectId}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'}->{'mbResult'} // die;
		my $visitName = $pcrRecords{$subjectId}->{'mbVisits'}->{$visitDate}->{'visit'} // die;
		$visitName    = visit_to_visit_num($visitName);
		$centralPCRsByDates{$visitCompdate}->{'visitName'} = $visitName;
		$centralPCRsByDates{$visitCompdate}->{'visitDate'} = $visitDate;
		$centralPCRsByDates{$visitCompdate}->{'pcrResult'} = $pcrResult;
		if ($pcrResult eq 'POS') {
			$hasPositiveCentralPCR = 1;
		}
	}
	return ($hasPositiveCentralPCR,
		%centralPCRsByDates);
}

sub visit_to_visit_num {
	my $visitName = shift;
	# if ($visitName eq 'V1_DAY1_VAX1_L') {
	# 	$visitName = 0;
	# } elsif ($visitName eq 'V2_VAX2_L') {
	# 	$visitName = 0.5;
	# } elsif ($visitName eq 'COVID_A') {
	# 	$visitName = 1;
	# } elsif ($visitName eq 'COVID_AR1') {
	# 	$visitName = 1.5;
	# } elsif ($visitName eq 'COVID_AR2') {
	# 	$visitName = 1.75;
	# } elsif ($visitName eq 'COVID_B') {
	# 	$visitName = 2;
	# } elsif ($visitName eq 'COVID_BR1') {
	# 	$visitName = 2.5;
	# } elsif ($visitName eq 'COVID_BR2') {
	# 	$visitName = 2.75;
	# } elsif ($visitName eq 'COVID_C') {
	# 	$visitName = 3;
	# } elsif ($visitName eq 'COVID_CR1') {
	# 	$visitName = 3.5;
	# } elsif ($visitName eq 'COVID_CR2') {
	# 	$visitName = 3.75;
	# } elsif ($visitName eq 'COVID_D') {
	# 	$visitName = 4;
	# } elsif ($visitName eq 'COVID_DR1') {
	# 	$visitName = 4.5;
	# } elsif ($visitName eq 'COVID_E') {
	# 	$visitName = 5;
	# } elsif ($visitName eq 'COVID_ER1') {
	# 	$visitName = 5.5;
	# } elsif ($visitName eq 'COVID_F') {
	# 	$visitName = 6;
	# } elsif ($visitName eq 'COVID_FR1') {
	# 	$visitName = 6.5;
	# } elsif ($visitName eq 'V201_SURVEIL_CONSENT') {
	# 	$visitName = 10;
	# } elsif ($visitName eq 'SSWAB_WEEK2') {
	# 	$visitName = 0.5; # To verify prior any use  /!\
	# } elsif ($visitName eq 'SSWAB_WEEK4') {
	# 	$visitName = 0.65; # To verify prior any use  /!\
	# } elsif ($visitName eq 'SSWAB_WEEK6') {
	# 	$visitName = 0.75; # To verify prior any use  /!\
	# } elsif ($visitName eq 'SSWAB_WEEK8') {
	# 	$visitName = 0.85; # To verify prior any use  /!\
	# } else {
	# 	die "visitName : [$visitName]";
	# }
	return $visitName;
}

sub subject_local_pcrs_by_dates {
	my ($subjectId,
		$unblindCompdate) = @_;
	my %localPCRsByDates    = ();
	my $hasPositiveLocalPCR = 0;
	my $referenceCompdate = ref_from_unblind($unblindCompdate);
	for my $visitDate (sort keys %{$pcrRecords{$subjectId}->{'mbVisits'}}) {

		# Skips the visits unless it contains PCRs.
		next unless exists $pcrRecords{$subjectId}->{'mbVisits'}->{$visitDate}->{'SEVERE ACUTE RESP SYNDROME CORONAVIRUS 2'};
		# p$pcrRecords{$subjectId};
		# die;
		my $visitCompdate = $visitDate;
		$visitCompdate =~ s/\D//g;

		# Skips the visit unless it fits with the phase 3.
		next unless $visitCompdate >= 20200720;
		next unless $visitCompdate <= $referenceCompdate;
		my $pcrResult = $pcrRecords{$subjectId}->{'mbVisits'}->{$visitDate}->{'SEVERE ACUTE RESP SYNDROME CORONAVIRUS 2'}->{'mbResult'} // die;
		my $visitName = $pcrRecords{$subjectId}->{'mbVisits'}->{$visitDate}->{'visit'} // die;
		my $spDevId   = $pcrRecords{$subjectId}->{'mbVisits'}->{$visitDate}->{'SEVERE ACUTE RESP SYNDROME CORONAVIRUS 2'}->{'spDevId'}  // die;
		if ($spDevId) {
			die "spDevId: $spDevId" unless $spDevId && looks_like_number $spDevId;
			die unless exists $testsRefs{$spDevId};
			my $deviceType = $testsRefs{$spDevId}->{'Device Type'} // die;
			my $tradeName  = $testsRefs{$spDevId}->{'Trade Name'}  // die;
			$spDevId = "$deviceType - $tradeName ($spDevId)";
			# p$testsRefs{$spDevId};
			# die;
		} else {
			$spDevId = 'Not Provided';
		}
		$stats{'localPCRsAnalysis'}->{'total'}++;
		$stats{'localPCRsAnalysis'}->{$spDevId}++;
		$visitName    = visit_to_visit_num($visitName);
		if ($pcrResult eq 'POSITIVE') {
			$pcrResult = 'POS';
		} elsif ($pcrResult eq 'NEGATIVE') {
			$pcrResult = 'NEG';
		} elsif ($pcrResult eq 'INDETERMINATE' || $pcrResult eq '') {
			$pcrResult = 'UKN';
		} else {
			die "pcrResult : $pcrResult";
		}
		$localPCRsByDates{$visitCompdate}->{'visitName'} = $visitName;
		$localPCRsByDates{$visitCompdate}->{'visitDate'} = $visitDate;
		$localPCRsByDates{$visitCompdate}->{'pcrResult'} = $pcrResult;
		$localPCRsByDates{$visitCompdate}->{'spDevId'}   = $spDevId;
		if ($pcrResult eq 'POS') {
			$hasPositiveLocalPCR = 1;
		}
	}
	return ($hasPositiveLocalPCR,
		%localPCRsByDates);
}

sub subject_symptoms_by_dates {
	my ($subjectId,
		$unblindCompdate) = @_;
	# die "subjectId : $subjectId" unless exists $faces{$subjectId};
	# p$faces{$subjectId};
	# die;
	# p$symptoms{$subjectId};
	# die;
	my $referenceCompdate = ref_from_unblind($unblindCompdate);
	my %symptomsByDates = ();
	my $hasSymptoms     = 0;
	for my $symptomDatetime (sort keys %{$symptoms{$subjectId}->{'symptomsReports'}}) {
		my ($symptomDate)   = split ' ', $symptomDatetime;

		# Comment these lines to stick with the visit date.
		my ($formerSymptomDate, $onsetStartOffset);
		if (exists $faces{$subjectId}->{$symptomDate}) {
			my $altStartDate = $faces{$subjectId}->{$symptomDate}->{'symptomsDates'}->{'First Symptom Date'} // die;
			unless ($altStartDate eq $symptomDate) {
				if ($altStartDate =~ /^....-..-..$/) {
					$stats{'faceData'}->{'symptoms'}->{'correctedStart'}->{'total'}++;
					# say "Adjusting [$subjectId] - [$symptomDate] -> [$altStartDate]";
					$formerSymptomDate = $symptomDate;
					$onsetStartOffset  = time::calculate_days_difference("$symptomDate 12:00:00", "$altStartDate 12:00:00");
					$stats{'faceData'}->{'symptoms'}->{'correctedStart'}->{'offsets'}->{$onsetStartOffset}++;
					$symptomDate = $altStartDate;
				} else {
					$stats{'faceData'}->{'symptoms'}->{'invalidDate'}++;
				}
			} else {
				$stats{'faceData'}->{'symptoms'}->{'sameDate'}++;
			}
		} else {
			$stats{'faceData'}->{'symptoms'}->{'noVisitData'}++;
		}
		$stats{'faceData'}->{'symptoms'}->{'totalRowsParsed'}++;
		my $symptomCompdate = $symptomDate;
		$symptomCompdate    =~ s/\D//g;
		next unless $symptomCompdate <= $referenceCompdate;
		my $totalSymptoms   = 0;
		my $hasOfficialSymptoms = 0;
		my $endDatetime = $symptoms{$subjectId}->{'symptomsReports'}->{$symptomDatetime}->{'endDatetime'};
		my $visitName = $symptoms{$subjectId}->{'symptomsReports'}->{$symptomDatetime}->{'visitName'} // die;
		for my $symptomName (sort keys %{$symptoms{$subjectId}->{'symptomsReports'}->{$symptomDatetime}->{'symptoms'}}) {
			next unless $symptoms{$subjectId}->{'symptomsReports'}->{$symptomDatetime}->{'symptoms'}->{$symptomName} eq 'Y';
			my $symptomCategory = symptom_category_from_symptom($symptomName);
			if ($officialSymptomsOnly) {
				next unless $symptomCategory eq 'OFFICIAL';
			}
			$hasOfficialSymptoms = 1 if $symptomCategory eq 'OFFICIAL';
			$symptomsByDates{$symptomCompdate}->{'symptoms'}->{$symptomName} = 1;
			$totalSymptoms++;
		}
		next unless $totalSymptoms;
		$hasSymptoms  = 1;
		$symptomsByDates{$symptomCompdate}->{'onsetStartOffset'}    = $onsetStartOffset;
		$symptomsByDates{$symptomCompdate}->{'formerSymptomDate'}   = $formerSymptomDate;
		$symptomsByDates{$symptomCompdate}->{'symptomDate'}         = $symptomDate;
		$symptomsByDates{$symptomCompdate}->{'totalSymptoms'}       = $totalSymptoms;
		$symptomsByDates{$symptomCompdate}->{'visitName'}           = $visitName;
		$symptomsByDates{$symptomCompdate}->{'endDatetime'}         = $endDatetime;
		$symptomsByDates{$symptomCompdate}->{'hasOfficialSymptoms'} = $hasOfficialSymptoms;
	}
	# p%symptomsByDates;
	# die;
	return (
		$hasSymptoms,
		%symptomsByDates);
}

sub ref_from_unblind {
	my $unblindCompdate = shift;
	my $referenceCompdate;
	if ($unblindCompdate > $cutoffCompdate) {
		$referenceCompdate = $cutoffCompdate;
	} else {
		$referenceCompdate = $unblindCompdate;
	}
	return $referenceCompdate;
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