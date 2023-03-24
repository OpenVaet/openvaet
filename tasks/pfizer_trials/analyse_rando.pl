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

my %saSites = ();
$saSites{1229} = 1;
$saSites{1230} = 1;
$saSites{1246} = 1;
$saSites{1247} = 1;

# Loading data required.
my $adslFile             = 'public/doc/pfizer_trials/pfizer_adsl_patients.json';
my $exclusionsFile       = 'public/doc/pfizer_trials/pfizer_excluded_patients.json';
my $deviationsFile       = 'public/doc/pfizer_trials/pfizer_sddv_patients.json';
my $lackPIOverFile       = 'public/doc/pfizer_trials/pfizer_suppdv_patients.json';
my $pcrRecordsFile       = 'public/doc/pfizer_trials/pfizer_mb_patients.json';
my $faceFile             = 'public/doc/pfizer_trials/pfizer_face_patients.json';
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
my $officialEfficacyFile = 'public/doc/pfizer_trials/officialEfficacy.json';


my %duplicates           = ();
$duplicates{'10561101'}  = 11331382;
# $duplicates{'11331382'}  = 10561101;
$duplicates{'11101123'}  = 11331405;
# $duplicates{'11331405'}  = 11101123;
$duplicates{'11491117'}  = 12691090;
# $duplicates{'12691090'}  = 11491117;
$duplicates{'12691070'}  = 11351357;
# $duplicates{'11351357'}  = 12691070;
$duplicates{'11341006'}  = 10891112;
# $duplicates{'10891112'}  = 11341006;
$duplicates{'11231105'}  = 10711213;
# $duplicates{'10711213'}  = 11231105;
my %noVaxData            = ();
$noVaxData{'11631006'}   = 1;
$noVaxData{'11631005'}   = 1;
$noVaxData{'11631008'}   = 1;

my %officialEfficacy     = ();
my %pdf_exclusions_1     = ();
my %randomization1       = ();
my %lackPIOver           = ();
my %screenings           = ();
my %advaData             = ();
my %adsl                 = ();
my %faces                = ();
my %demographics         = ();
my %phase1Subjects       = ();
my %exclusions           = ();
my %deviations           = ();
my %pcrRecords           = ();
my %symptoms             = ();
my %randomization        = ();
my %pdfCases             = ();
my %testsRefs            = ();
load_official_efficacy();
load_pdf_exclusions_1();
load_pi_oversight();
load_randomization_subjects_1();
load_screening();
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

my %idsBySites = ();
my ($formerSite, $formerId);
for my $subjectId (sort{$a <=> $b} keys %adsl) {
	my $randomNumber = $adsl{$subjectId}->{'randomNumber'} // die;
	$idsBySites{$randomNumber} = $subjectId;
}
my %subjectsIds = ();
for my $randomNumber (sort{$a <=> $b} keys %idsBySites) {
	$stats{'parsed'}++;
	if ($formerId) {
		my $theoricalNext =  $formerId + 1;
		unless ($theoricalNext == $randomNumber) {
			my $upTo = $randomNumber - 1;
			# say "[$randomNumber] != $theoricalNext";
			for my $theorical ($theoricalNext .. $upTo) {
				$subjectsIds{$theorical} = 'Missing';
				say "Missing [$theorical]";
				$stats{'errors'}++;
			}
		} else {
			# say "Present [$trialSiteId$randomNumber]";
			$stats{'asExpected'}++;
		}
	} else {
		unless ($randomNumber == 1001) {
			# say "[$randomNumber] != 1001";
			my $upTo = $randomNumber - 1;
			for my $theorical (1001 .. $upTo) {
				$subjectsIds{$theorical} = 'Missing';
				say "Missing [$theorical]";
				$stats{'errors'}++;
			}
		} else {
			# say "Present [$trialSiteId$randomNumber]";
			$stats{'asExpected'}++;
		}
	}
	$subjectsIds{$randomNumber} = 'Present';
	$formerId = $randomNumber;
}

p%stats;

open my $out, '>:utf8', 'subjects_by_sites_incremental_numbers.csv';
say $out "Trial Site Id;Subject Id;Arm;Screening Datetime;Exists;";
for my $randomNumber (sort{$a <=> $b} keys %subjectsIds) {
	my $subjectId = $idsBySites{$randomNumber} // die;
	my $arm = $adsl{$subjectId}->{'arm'} // '';
	my $screeningDatetime = $adsl{$subjectId}->{'screeningDatetime'} // '';
	my $exists = $subjectsIds{$randomNumber} // die;
	say $out "$subjectId;$randomNumber;$arm;$screeningDatetime;$exists;";
}
close $out;

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
		die if exists $centralPCRsByVisits{$visitName}->{'pcrResult'} && ($centralPCRsByVisits{$visitName}->{'pcrResult'} ne $pcrResult);
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