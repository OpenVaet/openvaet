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
my $cutoffCompdate       = '20211114';
my ($cY, $cM, $cD)       = $cutoffCompdate =~ /(....)(..)(..)/;
my $cutoffDatetime       = "$cY-$cM-$cD 12:00:00";
my $df                   = 1; # degrees of freedom

# Loading data required.
my $adslFile             = 'public/doc/pfizer_trials/pfizer_adsl_patients.json';
my $exclusionsFile       = 'public/doc/pfizer_trials/pfizer_excluded_patients.json';
my $deviationsFile       = 'public/doc/pfizer_trials/pfizer_sddv_patients.json';
my $lackPIOverFile       = 'public/doc/pfizer_trials/pfizer_suppdv_patients.json';
my $pcrRecordsFile       = 'public/doc/pfizer_trials/pfizer_mb_patients.json';
my $faceFile             = 'public/doc/pfizer_trials/pfizer_face_patients.json';
my $adaeFile             = 'public/doc/pfizer_trials/pfizer_adae_patients.json';
my $symptomsFile         = 'public/doc/pfizer_trials/pfizer_patients_symptoms.json';
my $randomizationFile    = 'public/doc/pfizer_trials/merged_doses_data.json';
my $p1SubjectsFile       = 'public/doc/pfizer_trials/phase1Subjects.json';
my $testsRefsFile        = 'public/doc/pfizer_trials/pfizer_di.json';
my $demographicFile      = 'public/doc/pfizer_trials/pfizer_trial_demographics_merged.json';
my $pdfCasesFile         = 'public/doc/pfizer_trials/pfizer_trial_cases_merged.json';
my $centralPCRsFile      = 'public/doc/pfizer_trials/subjects_with_pcr_and_symptoms.json';
my $advaFile             = "public/doc/pfizer_trials/pfizer_adva_patients.json";
my $screeningsFile       = "public/doc/pfizer_trials/subjects_screening_dates.json";
my $randomizationFile1   = 'public/doc/pfizer_trials/pfizer_trial_randomization_1.json';
my $pdfFile1             = 'excluded subjects 6 month.csv';
my $adc19efFile          = 'public/doc/pfizer_trials/pfizer_adc19ef_patients.json';
my $officialEfficacyFile = 'public/doc/pfizer_trials/officialEfficacy.json';
my $simuEfficacyFile     = 'public/doc/pfizer_trials/simulated_efficacy.json';
my $simuEffiAnomaFile    = 'public/doc/pfizer_trials/simulated_efficacy_anomalies.json';
my $efficacyFile         = 'public/doc/pfizer_trials/pfizer_trial_efficacy_cases.json';

my %officialEfficacy     = ();
my %adc19efs             = ();
my %pdf_exclusions_1     = ();
my %randomization1       = ();
my %lackPIOver           = ();
my %screenings           = ();
my %advaData             = ();
my %adsl                 = ();
my %adaes                = ();
my %faces                = ();
my %demographics         = ();
my %efficacy             = ();
my %phase1Subjects       = ();
my %exclusions           = ();
my %deviations           = ();
my %pcrRecords           = ();
my %symptoms             = ();
my %randomization        = ();
my %pdfCases             = ();
my %testsRefs            = ();
load_official_efficacy();
load_efficacy();
load_adc19ef();
load_pdf_exclusions_1();
load_pi_oversight();
load_randomization_subjects_1();
load_screening();
load_adae();
load_adsl();
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

parse_data();

delete $stats{'primaryBreakdown'}; # Comment this line if you wish to review the primary breakdown.
p%stats;

sub age_to_age_group {
	my $age = shift;
	my $ageGroup;
	if ($age > 5 && $age <= 14) {
		$ageGroup = '5-14';
	} elsif ($age >= 15 && $age <= 24) {
		$ageGroup = '15-24';
	} elsif ($age >= 25 && $age <= 34) {
		$ageGroup = '25-34';
	} elsif ($age >= 35 && $age <= 44) {
		$ageGroup = '35-44';
	} elsif ($age >= 45 && $age <= 54) {
		$ageGroup = '45-54';
	} elsif ($age >= 55 && $age <= 64) {
		$ageGroup = '55-64';
	} elsif ($age >= 65 && $age <= 74) {
		$ageGroup = '65-74';
	} elsif ($age >= 75 && $age <= 84) {
		$ageGroup = '75-84';
	} elsif ($age >= 85 && $age <= 94) {
		$ageGroup = '85-94';
	} else {
		die "age : $age";
	}
	return $ageGroup;
}

sub load_official_efficacy {
	open my $in, '<:utf8', $officialEfficacyFile or die "Missing file [$officialEfficacyFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%officialEfficacy = %$json;
	say "[$officialEfficacyFile] -> subjects : " . keys %officialEfficacy;
}

sub chi_squared {
     my ($a, $b, $c, $d) = @_;
     return 0 if($a + $c == 0);
     return 0 if($b + $d == 0);
     my $n = $a + $b + $c + $d;
     return (($n * ($a * $d - $b * $c) ** 2) / (($a + $b)*($c + $d)*($a + $c)*($b + $d)));
}

sub load_pdf_exclusions_1 {
	open my $in, '<:utf8', $pdfFile1;
	my $lNum = 0;
	while (<$in>) {
		$lNum++;
		next if $lNum == 1;
		my (undef, $uSubjectId) = split ';', $_;
		my ($subjectId)       = $uSubjectId =~ /^C4591001 .... (.*)$/;
		die unless $subjectId && $subjectId =~ /^........$/;
		die unless $uSubjectId =~ /$subjectId$/;
		$pdf_exclusions_1{$subjectId} = 1;
	}
	close $in;
	say "[$pdfFile1] -> subjects : " . keys %pdf_exclusions_1;
}

sub load_pi_oversight {
	open my $in, '<:utf8', $lackPIOverFile or die "Missing file [$lackPIOverFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%lackPIOver = %$json;
	say "[$lackPIOverFile] -> subjects : " . keys %lackPIOver;
	# p%lackPIOver;
	# die;
}

sub load_adc19ef {
	open my $in, '<:utf8', $adc19efFile or die "Missing file [$adc19efFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%adc19efs = %$json;
	say "[$adc19efFile] -> subjects : " . keys %adc19efs;
}

sub load_screening {
	open my $in, '<:utf8', $screeningsFile or die "Missing file [$screeningsFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%screenings = %$json;
	say "[$screeningsFile] -> subjects : " . keys %screenings;
}

sub load_adae {
	open my $in, '<:utf8', $adaeFile or die "Missing file [$adaeFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%adaes = %$json;
	say "[$adaeFile] -> subjects : " . keys %adaes;
}

sub load_adsl {
	open my $in, '<:utf8', $adslFile or die "Missing file [$adslFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%adsl = %$json;
	say "[$adslFile] -> subjects : " . keys %adsl;
}

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
	say "[$advaFile] -> subjects : " . keys %advaData;
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

sub load_randomization_subjects_1 {
	open my $in, '<:utf8', $randomizationFile1;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%randomization1 = %$json;
	say "[$randomizationFile1] -> tests    : " . keys %randomization1;
}

sub load_efficacy {
	open my $in, '<:utf8', $efficacyFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%efficacy = %$json;
	say "[$efficacyFile] -> subjects : " . keys %efficacy;
	# p%efficacy;
	# die;
}

sub subject_central_pcrs_by_visits {
	my ($subjectId,
		$unblindCompdate) = @_;
	my %centralPCRsByVisits    = ();
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
		if (exists $centralPCRsByVisits{$visitName}->{'pcrResult'} && ($centralPCRsByVisits{$visitName}->{'pcrResult'} ne $pcrResult)) {
			next unless $pcrResult eq 'POS';
		}
		$centralPCRsByVisits{$visitName}->{'visitDate'}     = $visitDate;
		$centralPCRsByVisits{$visitName}->{'pcrResult'}     = $pcrResult;
		$centralPCRsByVisits{$visitName}->{'visitCompdate'} = $visitCompdate;
		if ($pcrResult eq 'POS') {
			$hasPositiveCentralPCR = 1;
		}
	}
	return (
		$hasPositiveCentralPCR,
		%centralPCRsByVisits);
}

sub subject_local_pcrs_by_visits {
	my ($subjectId,
		$unblindCompdate)  = @_;
	my %localPCRsByVisits   = ();
	my $hasPositiveLocalPCR = 0;
	my $referenceCompdate   = ref_from_unblind($unblindCompdate);
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
		# $stats{'localPCRsAnalysis'}->{'total'}++;
		# $stats{'localPCRsAnalysis'}->{$spDevId}++;
		if ($pcrResult eq 'POSITIVE') {
			$pcrResult = 'POS';
		} elsif ($pcrResult eq 'NEGATIVE') {
			$pcrResult = 'NEG';
		} elsif ($pcrResult eq 'INDETERMINATE' || $pcrResult eq '') {
			$pcrResult = 'IND';
		} else {
			die "pcrResult : $pcrResult";
		}
		next if exists $localPCRsByVisits{$visitName}->{'pcrResult'} && ($localPCRsByVisits{$visitName}->{'pcrResult'} ne $pcrResult && $pcrResult ne 'POS');
		$localPCRsByVisits{$visitName}->{'visitDate'}     = $visitDate;
		$localPCRsByVisits{$visitName}->{'pcrResult'}     = $pcrResult;
		$localPCRsByVisits{$visitName}->{'visitCompdate'} = $visitCompdate;
		$localPCRsByVisits{$visitName}->{'spDevId'}       = $spDevId;
		if ($pcrResult eq 'POS') {
			# say "visitDate : $visitDate";
			# say "pcrResult : $pcrResult";
			# p%localPCRsByVisits;
			$hasPositiveLocalPCR = 1;
		}
	}

	return ($hasPositiveLocalPCR,
		%localPCRsByVisits);
}

sub subject_symptoms_by_visits {
	my ($subjectId,
		$unblindCompdate) = @_;
	my $referenceCompdate = ref_from_unblind($unblindCompdate);
	my %symptomsByVisits = ();
	my $hasSymptoms      = 0;
	for my $symptomDatetime (sort keys %{$symptoms{$subjectId}->{'symptomsReports'}}) {
		my ($symptomDate)   = split ' ', $symptomDatetime;
		my $compsympt = $symptomDate;
		$compsympt =~ s/\D//g;

		# Comment these lines to stick with the visit date.
		my ($formerSymptomDate, $onsetStartOffset);
		if (exists $faces{$subjectId}->{$symptomDate}) {
			my $altStartDate = $faces{$subjectId}->{$symptomDate}->{'symptomsDates'}->{'First Symptom Date'} // die;
			unless ($altStartDate eq $symptomDate) {
				if ($altStartDate =~ /^....-..-..$/) {
					my $compalt = $altStartDate;
					$compalt =~ s/\D//g;
					if ($compalt < $compsympt) {
						# $stats{'faceData'}->{'symptoms'}->{'correctedStart'}->{'total'}++;
						$formerSymptomDate = $symptomDate;
						$onsetStartOffset  = time::calculate_days_difference("$symptomDate 12:00:00", "$altStartDate 12:00:00");
						# $stats{'faceData'}->{'symptoms'}->{'correctedStart'}->{'offsets'}->{$onsetStartOffset}++;
						$symptomDate = $altStartDate;
					}
				} else {
					# $stats{'faceData'}->{'symptoms'}->{'invalidDate'}++;
				}
			} else {
				# $stats{'faceData'}->{'symptoms'}->{'sameDate'}++;
			}
		} else {
			# $stats{'faceData'}->{'symptoms'}->{'noVisitData'}++;
		}
		# $stats{'faceData'}->{'symptoms'}->{'totalRowsParsed'}++;
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
			$symptomsByVisits{$visitName}->{'symptoms'}->{$symptomName} = 1;
			$totalSymptoms++;
		}
		next unless $totalSymptoms;
		$hasSymptoms  = 1;
		$symptomsByVisits{$visitName}->{'onsetStartOffset'}    = $onsetStartOffset;
		$symptomsByVisits{$visitName}->{'formerSymptomDate'}   = $formerSymptomDate;
		$symptomsByVisits{$visitName}->{'symptomCompdate'}     = $symptomCompdate;
		$symptomsByVisits{$visitName}->{'symptomDate'}         = $symptomDate;
		$symptomsByVisits{$visitName}->{'totalSymptoms'}       = $totalSymptoms;
		$symptomsByVisits{$visitName}->{'endDatetime'}         = $endDatetime;
		$symptomsByVisits{$visitName}->{'hasOfficialSymptoms'} = $hasOfficialSymptoms;
	}
	# p%symptomsByVisits;
	# die;
	return (
		$hasSymptoms,
		%symptomsByVisits);
}

sub subject_central_pcrs_by_dates {
	my ($subjectId,
		$unblindCompdate) = @_;
	my %centralPCRsByVisits    = ();
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
		$centralPCRsByVisits{$visitName}->{'visitDate'}     = $visitDate;
		$centralPCRsByVisits{$visitName}->{'pcrResult'}     = $pcrResult;
		$centralPCRsByVisits{$visitName}->{'visitCompdate'} = $visitCompdate;
		if ($pcrResult eq 'POS') {
			$hasPositiveCentralPCR = 1;
		}
	}
	return (
		$hasPositiveCentralPCR,
		%centralPCRsByVisits);
}

sub subject_local_pcrs_by_dates {
	my ($subjectId,
		$unblindCompdate)  = @_;
	my %localPCRsByVisits   = ();
	my $hasPositiveLocalPCR = 0;
	my $referenceCompdate   = ref_from_unblind($unblindCompdate);
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
		# $stats{'localPCRsAnalysis'}->{'total'}++;
		# $stats{'localPCRsAnalysis'}->{$spDevId}++;
		if ($pcrResult eq 'POSITIVE') {
			$pcrResult = 'POS';
		} elsif ($pcrResult eq 'NEGATIVE') {
			$pcrResult = 'NEG';
		} elsif ($pcrResult eq 'INDETERMINATE' || $pcrResult eq '') {
			$pcrResult = 'IND';
		} else {
			die "pcrResult : $pcrResult";
		}
		$localPCRsByVisits{$visitName}->{'visitDate'}     = $visitDate;
		$localPCRsByVisits{$visitName}->{'pcrResult'}     = $pcrResult;
		$localPCRsByVisits{$visitName}->{'visitCompdate'} = $visitCompdate;
		$localPCRsByVisits{$visitName}->{'spDevId'}       = $spDevId;
		if ($pcrResult eq 'POS') {
			$hasPositiveLocalPCR = 1;
		}
	}
	return ($hasPositiveLocalPCR,
		%localPCRsByVisits);
}

sub subject_symptoms_by_dates {
	my ($subjectId,
		$unblindCompdate) = @_;
	my $referenceCompdate = ref_from_unblind($unblindCompdate);
	my %symptomsByVisits = ();
	my $hasSymptoms     = 0;
	my $firstSymptomDate;
	my $firstSymptomVisit;
	for my $symptomDatetime (sort keys %{$symptoms{$subjectId}->{'symptomsReports'}}) {
		my ($symptomDate)   = split ' ', $symptomDatetime;
		my $compsympt = $symptomDate;
		$compsympt =~ s/\D//g;

		# Comment these lines to stick with the visit date.
		my ($formerSymptomDate, $onsetStartOffset);
		if (exists $faces{$subjectId}->{$symptomDate}) {
			my $altStartDate = $faces{$subjectId}->{$symptomDate}->{'symptomsDates'}->{'First Symptom Date'} // die;
			unless ($altStartDate eq $symptomDate) {
				if ($altStartDate =~ /^....-..-..$/) {
					my $compalt = $altStartDate;
					$compalt =~ s/\D//g;
					if ($compalt < $compsympt) {
						# $stats{'faceData'}->{'symptoms'}->{'correctedStart'}->{'total'}++;
						$formerSymptomDate = $symptomDate;
						$onsetStartOffset  = time::calculate_days_difference("$symptomDate 12:00:00", "$altStartDate 12:00:00");
						# $stats{'faceData'}->{'symptoms'}->{'correctedStart'}->{'offsets'}->{$onsetStartOffset}++;
						$symptomDate = $altStartDate;
					}
				} else {
					# $stats{'faceData'}->{'symptoms'}->{'invalidDate'}++;
				}
			} else {
				# $stats{'faceData'}->{'symptoms'}->{'sameDate'}++;
			}
		} else {
			# $stats{'faceData'}->{'symptoms'}->{'noVisitData'}++;
		}
		# $stats{'faceData'}->{'symptoms'}->{'totalRowsParsed'}++;
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
			$symptomsByVisits{$symptomCompdate}->{'symptoms'}->{$symptomName} = 1;
			$totalSymptoms++;
		}
		next unless $totalSymptoms;
		$hasSymptoms  = 1;
		$symptomsByVisits{$symptomCompdate}->{'onsetStartOffset'}    = $onsetStartOffset;
		$symptomsByVisits{$symptomCompdate}->{'formerSymptomDate'}   = $formerSymptomDate;
		$symptomsByVisits{$symptomCompdate}->{'visitName'}           = $visitName;
		$symptomsByVisits{$symptomCompdate}->{'symptomDate'}         = $symptomDate;
		$symptomsByVisits{$symptomCompdate}->{'totalSymptoms'}       = $totalSymptoms;
		$symptomsByVisits{$symptomCompdate}->{'endDatetime'}         = $endDatetime;
		$symptomsByVisits{$symptomCompdate}->{'hasOfficialSymptoms'} = $hasOfficialSymptoms;
	}
	for my $compdate (sort{$a <=> $b} keys %symptomsByVisits) {
		my $visitName = $symptomsByVisits{$compdate}->{'visitName'} // die;
		if (!$firstSymptomDate) {
			$firstSymptomDate = $compdate;
			$firstSymptomVisit = $visitName;
			last;
		}
	}
	# p%symptomsByVisits;
	# die;
	return (
		$hasSymptoms,
		$firstSymptomDate,
		$firstSymptomVisit,
		%symptomsByVisits);
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

sub parse_data {
	for my $subjectId (sort{$a <=> $b} keys %adsl) {
		my ($trialSiteId)  = $subjectId =~ /^(....)....$/;
		$trialSiteId       = 1231 if $trialSiteId eq '4444';
		my $aai1effl       = $adsl{$subjectId}->{'aai1effl'}       // die;
		my $mulenRfl       = $adsl{$subjectId}->{'mulenRfl'}       // die;
		my $phase          = $adsl{$subjectId}->{'phase'}          // die;
		my $saffl          = $adsl{$subjectId}->{'saffl'}          // die;
		my $ageYears       = $adsl{$subjectId}->{'ageYears'}       // die;
		my $ageGroup       = age_to_age_group($ageYears);
		my $arm            = $adsl{$subjectId}->{'arm'}            // die;
		my $hasHIV         = $adsl{$subjectId}->{'hasHIV'}         // die;
		my $uSubjectId     = $adsl{$subjectId}->{'uSubjectId'}     // die;
		my $unblindingDate = $adsl{$subjectId}->{'unblindingDate'} || $cutoffCompdate;

		# Verifying phase.
		next unless $phase eq 'Phase 3' || $phase eq 'Phase 3_ds6000' || $phase eq 'Phase 2_ds360/ds6000';
		next if $mulenRfl  && $mulenRfl eq 'Y';
		$phase = 'Phase 2 - 3';
		my $sex = $adsl{$subjectId}->{'sex'} // die;
		my $randomizationDatetime = $adsl{$subjectId}->{'randomizationDatetime'} // '';
		my $randomizationDate = $adsl{$subjectId}->{'randomizationDate'};
		# next if (!$randomizationDate || ($randomizationDate > $cutoffCompdate));

		# Dose 1.
		my $dose1Date = $adsl{$subjectId}->{'dose1Date'};
		my $dose1Datetime = $adsl{$subjectId}->{'dose1Datetime'};

		# Dose 2 date + 7 Days.
		my $dose2Date = $adsl{$subjectId}->{'dose2Date'};

		my $v1NBinding       = $advaData{$subjectId}->{'visits'}->{'V1_DAY1_VAX1_L'}->{'tests'}->{'N-binding antibody - N-binding Antibody Assay'};
		my $v3NBinding       = $advaData{$subjectId}->{'visits'}->{'V3_MONTH1_POSTVAX2_L'}->{'tests'}->{'N-binding antibody - N-binding Antibody Assay'};
		# next unless exists $simulatedEfficacy{$subjectId} || exists $simuEffiAnomalies{$subjectId};

		unless ($v1NBinding) {
			$stats{'0_noV1Test'}->{'total'}++;
			$stats{'0_noV1Test'}->{$arm}++;
			next;
		}
		$stats{'1_totalSubjectsV1'}->{'total'}++;
		$stats{'1_totalSubjectsV1'}->{$arm}->{'total'}++;
	 	$stats{'1_totalSubjectsV1'}->{$arm}->{$v1NBinding}++;
		next if $v1NBinding eq 'POS';
		$stats{'2_totalSubjectsV1Neg'}->{'total'}++;
		$stats{'2_totalSubjectsV1Neg'}->{$arm}++;
		next unless $dose2Date;
		$stats{'3_Dose2'}->{'total'}++;
		$stats{'3_Dose2'}->{$arm}++;
		my $dose2Datetime       = $adsl{$subjectId}->{'dose2Datetime'};
		my $dose2Uts            = time::datetime_to_timestamp($dose2Datetime);
		$dose2Uts               = $dose2Uts + 86400 * 30;
		my $scheduledV3Datetime = time::timestamp_to_datetime($dose2Uts);
		my ($scheduledV3Date)   = split ' ', $scheduledV3Datetime;
		$scheduledV3Date        =~ s/\D//g;
		# say "dose2Datetime       : $dose2Datetime";
		# say "scheduledV3Datetime : $scheduledV3Datetime";

		# Verifying Visit 1 Tests.
		my ($hasPositiveCentralPCR,
			%centralPCRsByVisits) = subject_central_pcrs_by_visits($subjectId, $scheduledV3Date);
		my ($hasPositiveLocalPCR,
			%localPCRsByVisits)   = subject_local_pcrs_by_visits($subjectId, $scheduledV3Date);
		my ($hasSymptoms,
			%symptomsByVisits)    = subject_symptoms_by_visits($subjectId, $scheduledV3Date);
		
		# Verifing VISIT 1 Test Results.
		my $v1D1CentralPCR   = $centralPCRsByVisits{'V1_DAY1_VAX1_L'}->{'pcrResult'};
		my $v2D2CentralPCR   = $centralPCRsByVisits{'V2_VAX2_L'}->{'pcrResult'};
		next if !$v1D1CentralPCR;
		$stats{'3_totalSubjectsV1PCR'}->{'total'}++;
		$stats{'3_totalSubjectsV1PCR'}->{$arm}++; 
		next if $v1D1CentralPCR ne 'NEG';
		$stats{'4_totalSubjectsV1PCRNeg'}->{'total'}++;
		$stats{'4_totalSubjectsV1PCRNeg'}->{$arm}++;
		next if !$v2D2CentralPCR;
		$stats{'5_totalSubjectsV2PCR'}->{'total'}++;
		$stats{'5_totalSubjectsV2PCR'}->{$arm}++; 
		next if $v2D2CentralPCR ne 'NEG';
		$stats{'6_totalSubjectsV2PCRNeg'}->{'total'}++;
		$stats{'6_totalSubjectsV2PCRNeg'}->{$arm}++;
		if (exists $efficacy{$subjectId}) {
			$stats{'7_totalSubjectsEfficacy'}->{'total'}++;
			$stats{'7_totalSubjectsEfficacy'}->{$arm}++;
		}
		if ($v3NBinding) {
			$stats{'9_v1ToV3'}->{'total'}++;
			$stats{'9_v1ToV3'}->{$arm}->{'total'}++;
			$stats{'9_v1ToV3'}->{$arm}->{$v1NBinding}->{$v3NBinding}++;
		} else {
			$stats{'8_noV3'}->{'total'}++;
			$stats{'8_noV3'}->{$arm}->{'total'}++;
			$stats{'8_noV3'}->{$arm}->{$hasPositiveCentralPCR}++;
		}
		if ($v3NBinding eq 'POS' && exists $efficacy{$subjectId}) {
			$stats{'10_totalSubjectsEfficacyPostV3'}->{'total'}++;
			$v3NBinding = '' unless $v3NBinding;
			$stats{'10_totalSubjectsEfficacyPostV3'}->{$arm}->{$v1NBinding}->{$v3NBinding}++;
		}
	}
}