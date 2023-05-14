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
my $adslFile             = 'public/doc/pfizer_trials/pfizer_adsl_patients.json';
my $exclusionsFile       = 'public/doc/pfizer_trials/pfizer_excluded_patients.json';
my $deviationsFile       = 'public/doc/pfizer_trials/pfizer_sddv_patients.json';
my $lackPIOverFile       = 'public/doc/pfizer_trials/pfizer_suppdv_patients.json';
my $pcrRecordsFile       = 'public/doc/pfizer_trials/pfizer_mb_patients.json';
my $symptomsFile         = 'public/doc/pfizer_trials/pfizer_patients_symptoms.json';
my $faceFile             = 'public/doc/pfizer_trials/pfizer_face_patients.json';
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
my %symptoms             = ();
my %faces                = ();
my %demographics         = ();
my %phase1Subjects       = ();
my %exclusions           = ();
my %deviations           = ();
my %pcrRecords           = ();
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
load_randomization();
load_exclusions();
load_deviations();
load_pcr_tests();
load_symptoms();
load_faces();
load_pdf_cases();
load_tests_refs();
load_adva_data();

my %stats = ();
my %randomizedSubjects = ();
my %randomizedSubjectsWithoutDose = ();
# symptoms_positive_data();

for my $subjectId (sort{$a <=> $b} keys %randomization) {
	my $randomizationDate = $randomization{$subjectId}->{'randomizationDate'};
	next if $randomizationDate > 20201114;
	my $ageYears = $adsl{$subjectId}->{'ageYears'} // die;
	next if $ageYears < 16;
	my $phase = $adsl{$subjectId}->{'phase'} // die;
	next if exists $phase1Subjects{$subjectId};
	my $dose1Date = $randomization{$subjectId}->{'dose1Date'};
	if (!$dose1Date) {
		$randomizedSubjectsWithoutDose{$subjectId}->{'randomizationData'} = 1;
	}
}
# p%randomizedSubjectsWithoutDose;
say "subject rando without dose : " . keys %randomizedSubjectsWithoutDose;
# die;

my %missingTests = ();
my %missingVisit1Tests = ();
open my $outChildren, '>:utf8', '2306_children.csv';
say $outChildren "uSubjectId;subjectId;ageYears;arm;sex;randomizationDatetime;";
for my $subjectId (sort{$a <=> $b} keys %adsl) {
	my $phase = $adsl{$subjectId}->{'phase'} // die;
	my $ageYears = $adsl{$subjectId}->{'ageYears'} // die;
	my $arm = $adsl{$subjectId}->{'arm'} // die;
	my $hasHIV = $adsl{$subjectId}->{'hasHIV'} // die;
	my $uSubjectId = $adsl{$subjectId}->{'uSubjectId'} // die;
	my $unblindingDate = $adsl{$subjectId}->{'unblindingDate'} || $cutoffCompdate;
	$stats{'0_primaryBreakdown'}->{$phase}->{'total'}++;
	if ($ageYears < 16) {
		$stats{'0_primaryBreakdown'}->{$phase}->{'byAges'}->{'under16'}++;
	} else {
		$stats{'0_primaryBreakdown'}->{$phase}->{'byAges'}->{'16+'}++;
	}

	# Verifying phase.
	next unless $phase eq 'Phase 3' || $phase eq 'Phase 3_ds6000' || $phase eq 'Phase 2_ds360/ds6000';
	$phase = 'Phase 2 - 3';
	my $sex = $adsl{$subjectId}->{'sex'} // die;
	my $randomizationDatetime = $adsl{$subjectId}->{'randomizationDatetime'} // '';
	my $randomizationDate = $adsl{$subjectId}->{'randomizationDate'};


	# Verifying screening failures.
	$stats{'1_phase3'}->{'totalPhaseSubjects'}++;
	if ($arm eq 'NOT ASSIGNED') {
		$stats{'1_phase3'}->{'0_noScreening'}->{'skippedByNotAssigned'}++;
		unless (exists $screenings{$subjectId}) {
			$stats{'1_phase3'}->{'0_noScreening'}->{'total'}++;
		}
		next;
	}
	if ($arm eq 'SCREEN FAILURE') {
		$stats{'1_phase3'}->{'0_noScreening'}->{'skippedByScreenedFailure'}++;
		unless (exists $screenings{$subjectId}) {
			$stats{'1_phase3'}->{'0_noScreening'}->{'total'}++;
		}
		next;
	}
	die if $ageYears >= 16 && !exists $screenings{$subjectId};
	die unless $randomizationDate;

	# Verifying randomization dates.
	$stats{'1_phase3'}->{'1_randomized'}->{'totalRandomized'}++;
	if ($randomizationDate > 20201114) {
		$stats{'1_phase3'}->{'1_randomized'}->{'totalRandomizedPostCutOff'}++;
		next;
	}

	# Verifying duplicates & no vax data subjects.
	if (exists $duplicates{$subjectId}) {
		$stats{'1_phase3'}->{'1_randomized'}->{'excludedDuplicates'}++;
		next;
	}
	if (exists $noVaxData{$subjectId}) {
		$stats{'1_phase3'}->{'1_randomized'}->{'excludedNoVaxData'}++;
		next;
	}
	$randomizedSubjects{'adsl'}->{$subjectId} = 1;
	$stats{'1_phase3'}->{'1_randomized'}->{'totalRandomizedPriorCutOff'}++;
	$stats{'1_phase3'}->{'1_randomized'}->{'byArm'}->{$arm}->{'total'}++;


	# Verifying Dose 1.
	my $dose1Date = $adsl{$subjectId}->{'dose1Date'};
	unless ($dose1Date) {
		if ($ageYears >= 16) {
			$stats{'1_phase3'}->{'2_dose1'}->{'noDose1'}->{'total'}++;
			$stats{'1_phase3'}->{'2_dose1'}->{'noDose1'}->{$arm}++;
			unless (exists $randomization1{$subjectId}) {
				# p$randomization{$subjectId};
				# p$adsl{$subjectId};
				# die;
			}
			$randomizedSubjectsWithoutDose{$subjectId}->{'adslData'} = 1;
			next;
		} else {
			die;
		}
	}
	if ($dose1Date > 20201114) {
		$stats{'1_phase3'}->{'2_dose1'}->{'dose1PostCutOff'}++;
		next;
	}
	$stats{'1_phase3'}->{'2_dose1'}->{'totalDose1PriorCutOff'}++;
	$stats{'1_phase3'}->{'2_dose1'}->{'byArm'}->{$arm}->{'total'}++;

	# Verifying DB D1 Efficacy Tags.
	my $aai1effl = $adsl{$subjectId}->{'aai1effl'} // die;
	my $mulenRfl = $adsl{$subjectId}->{'mulenRfl'} // die;
	if ($mulenRfl ne 'Y' && $aai1effl eq 'Y') {
		$stats{'1_phase3'}->{'3_tagBasedExclusions'}->{'dose1TheoricalEfficacy'}++;
	}

	# Verifying Visit 1 Tests.
	my ($hasPositiveCentralPCR,
		%centralPCRsByVisits) = subject_central_pcrs_by_visits($subjectId, $unblindingDate);
	my ($hasPositiveLocalPCR,
		%localPCRsByVisits)   = subject_local_pcrs_by_visits($subjectId, $unblindingDate);
	unless (exists $advaData{$subjectId}) {
		$stats{'1_phase3'}->{'4_visit1Testing'}->{'noAdvaData'}++;
		$missingTests{$subjectId}->{'noAdva'} = $arm;
		next;
	}
	unless (keys %centralPCRsByVisits || keys %localPCRsByVisits) {
		$stats{'1_phase3'}->{'4_visit1Testing'}->{'noPcrData'}++;
		$missingTests{$subjectId}->{'noMb'} = $arm;
		next;
	}
	my $missingVisit1Record = 0;
	unless (exists $advaData{$subjectId}->{'visits'}->{'V1_DAY1_VAX1_L'}->{'N-binding antibody - N-binding Antibody Assay'}) {
		$stats{'1_phase3'}->{'4_visit1Testing'}->{'noVisit1AdvaData'}++;
		$missingVisit1Record = 1;
		$missingVisit1Tests{$subjectId}->{'missingFromAdva'} = 1;
	}
	unless (exists $centralPCRsByVisits{'V1_DAY1_VAX1_L'}->{'pcrResult'} || exists $localPCRsByVisits{'V1_DAY1_VAX1_L'}->{'pcrResult'}) {
		$stats{'1_phase3'}->{'4_visit1Testing'}->{'noVisit1PCRData'}++;
		$missingVisit1Record = 1;
		$missingVisit1Tests{$subjectId}->{'missingFromPCR'} = 1;
	}
	if ($missingVisit1Record) {
		$stats{'1_phase3'}->{'4_visit1Testing'}->{'missingVisit1Data'}++;
		$missingVisit1Tests{$subjectId}->{'ageYears'} = $ageYears;
		$missingVisit1Tests{$subjectId}->{'arm'} = $arm;
		$missingVisit1Tests{$subjectId}->{'sex'} = $sex;
		$missingVisit1Tests{$subjectId}->{'randomizationDatetime'} = $randomizationDatetime;
		next;
	}
	$stats{'1_phase3'}->{'4_visit1Testing'}->{'totalWithVisitDataPriorCutOff'}++;
	$stats{'1_phase3'}->{'4_visit1Testing'}->{'byArm'}->{$arm}->{'totalWithVisitDataPriorCutOff'}++;

	# Verifying HIV
	if ($hasHIV) {
		$stats{'1_phase3'}->{'5_tagBasedExclusions'}->{'hivPositive'}++;
		next;
	}
	$stats{'1_phase3'}->{'5_tagBasedExclusions'}->{'totalPriorCutOff'}++;
	$stats{'1_phase3'}->{'5_tagBasedExclusions'}->{'byArm'}->{$arm}->{'total'}++;
	# p%centralPCRsByVisits;
	# die;

	# Verifing VISIT 1 Test Results.
	my $v1D1NBinding   = $advaData{$subjectId}->{'visits'}->{'V1_DAY1_VAX1_L'}->{'N-binding antibody - N-binding Antibody Assay'} // die;
	my $v1D1CentralPCR = $centralPCRsByVisits{'V1_DAY1_VAX1_L'}->{'pcrResult'} // die;
	my $v1D1LocalPCR   = $localPCRsByVisits{'V1_DAY1_VAX1_L'}->{'pcrResult'};
	die if $v1D1LocalPCR;
	if ($v1D1NBinding eq 'POS' && $v1D1CentralPCR eq 'POS') {
		$stats{'1_phase3'}->{'6_visit1Testing'}->{'totalVisit1PositiveBothPriorCutOff'}++;
		$stats{'1_phase3'}->{'6_visit1Testing'}->{'byArm'}->{$arm}->{'totalVisit1PositiveBoth'}++;
	}
	if ($v1D1NBinding eq 'POS' || $v1D1CentralPCR eq 'POS') {
		# p$adsl{$subjectId};
		# die;
		$stats{'1_phase3'}->{'6_visit1Testing'}->{'totalVisit1PositivePriorCutOff'}++;
		$stats{'1_phase3'}->{'6_visit1Testing'}->{'byArm'}->{$arm}->{'totalVisit1Positive'}++;
		if ($v1D1NBinding eq 'POS') {
			$stats{'1_phase3'}->{'6_visit1Testing'}->{'totalVisit1PositiveNBinding'}++;
		}
		if ($v1D1CentralPCR eq 'POS') {
			$stats{'1_phase3'}->{'6_visit1Testing'}->{'totalVisit1PositivePCR'}++;
		}
		next;
	}
	$stats{'1_phase3'}->{'6_visit1Testing'}->{'totalVisit1NegativePriorCutOff'}++;
	$stats{'1_phase3'}->{'6_visit1Testing'}->{'byArm'}->{$arm}->{'totalVisit1Negative'}++;

	# Testing D1 Tags.
	if ($mulenRfl ne 'Y' && $aai1effl eq 'Y') {
		$stats{'1_phase3'}->{'7_postVisit1Testing'}->{'dose1Efficacy'}++;
	} else {
		if ($mulenRfl eq 'Y') {
			$stats{'1_phase3'}->{'7_postVisit1Testing'}->{'excludedDuplicate'}++;
			next;
		}
		if ($aai1effl ne 'Y') {
			$stats{'1_phase3'}->{'7_postVisit1Testing'}->{'WouldBeExcludedD1Efficacy'}++;
			# next;
			# p%centralPCRsByVisits;
			# p$advaData{$subjectId};
			# p$adsl{$subjectId};
			# die;
		}
	}
	$stats{'1_phase3'}->{'7_postVisit1Testing'}->{'totalVisit1NegativePriorCutOff'}++;
	$stats{'1_phase3'}->{'7_postVisit1Testing'}->{'byArm'}->{$arm}->{'totalVisit1Negative'}++;

	# Verifying deviations.
	# my $hasDeviation = 0;
	# my %deviationsByDates = ();
	# for my $deviationDate (sort keys %{$deviations{$subjectId}}) {
	# 	my $deviationCompdate = $deviationDate;
	# 	$deviationCompdate =~ s/\D//g;
	# 	next if $deviationCompdate > 20201114;
	# 	next unless $deviations{$subjectId}->{$deviationDate}->{'dvCat'} eq 'Important';
	# 	$deviationsByDates{$deviationCompdate}->{'dvCat'} = $deviations{$subjectId}->{$deviationDate}->{'dvCat'};
	# 	$deviationsByDates{$deviationCompdate}->{'dvTerm'} = $deviations{$subjectId}->{$deviationDate}->{'dvTerm'};
	# 	$deviationsByDates{$deviationCompdate}->{'epoch'} = $deviations{$subjectId}->{$deviationDate}->{'epoch'};
	# 	$hasDeviation = 1;
	# }
	# if ($hasDeviation == 1) {
	# 	$stats{'1_phase3'}->{'8_postD1Deviations'}->{'importantDeviationsPriorCutOff'}++;
	# 	$stats{'1_phase3'}->{'8_postD1Deviations'}->{'byArm'}->{$arm}->{'importantDeviations'}++;
	# 	next;
	# }
	# $stats{'1_phase3'}->{'8_postD1Deviations'}->{'totalVisit1NegativePriorCutOff'}++;
	# $stats{'1_phase3'}->{'8_postD1Deviations'}->{'byArm'}->{$arm}->{'totalVisit1Negative'}++;

	# # Verifying exclusions.
	# if (exists $pdf_exclusions_1{$subjectId}) {
	# 	$stats{'1_phase3'}->{'9_postD1Exclusions'}->{'importantExclusionsPriorCutOff'}++;
	# 	$stats{'1_phase3'}->{'9_postD1Exclusions'}->{'byArm'}->{$arm}->{'importantExclusions'}++;
	# 	next;
	# }
	# $stats{'1_phase3'}->{'9_postD1Exclusions'}->{'totalVisit1NegativePriorCutOff'}++;
	# $stats{'1_phase3'}->{'9_postD1Exclusions'}->{'byArm'}->{$arm}->{'totalVisit1Negative'}++;

	# Verifying Dose 2.
	my $dose2Date = $adsl{$subjectId}->{'dose2Date'};
	unless ($dose2Date) {
		$stats{'1_phase3'}->{'10_dose2'}->{'noDose2'}->{'total'}++;
		$stats{'1_phase3'}->{'10_dose2'}->{'noDose2'}->{$arm}++;
		next;
	}
	if ($dose2Date > 20201114) {
		$stats{'1_phase3'}->{'10_dose2'}->{'dose2PostCutOff'}++;
		next;
	}
	$stats{'1_phase3'}->{'10_dose2'}->{'totalDose2PriorCutOff'}++;
	$stats{'1_phase3'}->{'10_dose2'}->{'byArm'}->{$arm}->{'total'}++;
	if ($dose2Date > 20201107) {
		$stats{'1_phase3'}->{'11_dose2'}->{'dose2PostEfficacyCutOff'}++;
		next;
	}
	$stats{'1_phase3'}->{'11_dose2'}->{'dose2PriorEfficacyCutOff'}++;
	$stats{'1_phase3'}->{'11_dose2'}->{'byArm'}->{$arm}->{'priorEfficacyCutOff'}++;

	# Verifying interval between injections.
	my $dose1Datetime    = $adsl{$subjectId}->{'dose1Datetime'} // die;
	my $dose2Datetime    = $adsl{$subjectId}->{'dose2Datetime'} // die;
	my $daysBetweenDoses = time::calculate_days_difference($dose1Datetime, $dose2Datetime);
	if ($daysBetweenDoses < 19 || $daysBetweenDoses > 42) {
		$stats{'1_phase3'}->{'12_dose2'}->{'outOf19To42DaysInterval'}++;
		next;
	}
	$stats{'1_phase3'}->{'12_dose2'}->{'in19To42DaysInterval'}++;
	$stats{'1_phase3'}->{'12_dose2'}->{'byArm'}->{$arm}->{'in19To42DaysInterval'}++;

	# Verifying if subject tested positive for Covid prior 7 days post dose 2.
	if ($hasPositiveCentralPCR || $hasPositiveLocalPCR) {
		# p%centralPCRsByVisits;
		# p%localPCRsByVisits;
		say "hasPositiveCentralPCR : $hasPositiveCentralPCR";
		say "hasPositiveLocalPCR   : $hasPositiveLocalPCR";
		my $earliestCovid = '99999999';
		for my $visit (sort keys %centralPCRsByVisits) {
			my $visitCompdate = $centralPCRsByVisits{$visit}->{'visitCompdate'} // die;
			my $pcrResult     = $centralPCRsByVisits{$visit}->{'pcrResult'}     // die;
			if ($pcrResult eq 'POS') {
				$earliestCovid = $visitCompdate if $visitCompdate < $earliestCovid;
			}
		}
		for my $visit (sort keys %localPCRsByVisits) {
			my $visitCompdate = $localPCRsByVisits{$visit}->{'visitCompdate'} // die;
			my $pcrResult     = $localPCRsByVisits{$visit}->{'pcrResult'}     // die;
			if ($pcrResult eq 'POS') {
				$earliestCovid = $visitCompdate if $visitCompdate < $earliestCovid;
			}
		}
		die if $earliestCovid eq '99999999';
		if ($earliestCovid <= $dose2Date) {
			$stats{'1_phase3'}->{'13_dose2'}->{'covidPriorOrOnDose2'}++;
			next;
		} else {
			my ($eCY, $eCM, $eCD) = $earliestCovid =~ /(....)(..)(..)/;
			say "$eCY-$eCM-$eCD 12:00:00, $dose2Datetime";
			my $daysFromCovidToDose2 = time::calculate_days_difference("$eCY-$eCM-$eCD 12:00:00", $dose2Datetime);
			if ($daysFromCovidToDose2 <= 7) {
				$stats{'1_phase3'}->{'13_dose2'}->{'covidPrior7DaysPostDose2'}++;
				next;
			}
		}
	}
	$stats{'1_phase3'}->{'13_dose2'}->{'noCovid7DaysPostDose2'}++;
	$stats{'1_phase3'}->{'13_dose2'}->{'byArm'}->{$arm}->{'noCovid7DaysPostDose2'}++;

	# Verifying which subjects at this stage aren't included in the "official" ones.
	unless (exists $officialEfficacy{$subjectId}) {
		$stats{'1_phase3'}->{'13_dose2'}->{'notInOfficialEfficacy'}++;
		$stats{'1_phase3'}->{'13_dose2'}->{'byArm'}->{$arm}->{'notInOfficialEfficacy'}++;
		# say "*" x 50;
		# say "subjectId : $subjectId";
		# p$adsl{$subjectId};
		# p%centralPCRsByVisits;
		# p%localPCRsByVisits;
		# die;
	}



	# Reorganizing symptoms by dates.
	my ($hasSymptoms, %symptomsByVisit) = subject_symptoms_by_visits($subjectId, $unblindingDate);
	next unless keys %symptomsByVisit && $hasSymptoms;
	$stats{'1_phase3'}->{'14_efficacyPopulation'}->{'symptomatic'}++;
	$stats{'1_phase3'}->{'14_efficacyPopulation'}->{'byArm'}->{$arm}->{'symptomatic'}++;
	for my $visitName (sort keys %symptomsByVisit) {
		my $symptomDate         = $symptomsByVisit{$visitName}->{'symptomDate'}         // die;
		my $totalSymptoms       = $symptomsByVisit{$visitName}->{'totalSymptoms'}       || die;
		my $hasOfficialSymptoms = $symptomsByVisit{$visitName}->{'hasOfficialSymptoms'} // die;
		my $symptomDatetime     = "$symptomDate 12:00:00";
		$stats{'symptomsAnalysis'}->{'visits'}->{'total'}++;
		$stats{'symptomsAnalysis'}->{'visits'}->{$arm}++;

		# Fetching nearest test from the symptoms occurence.
		my $symptomsWithCentralPCR            = 0;
		my $symptomsWithLocalPCR              = 0;
		my $symptomsWithPositiveCentralPCR    = 0;
		my $symptomsWithPositiveLocalPCR      = 0;
		my $centralVisitDate = $centralPCRsByVisits{$visitName}->{'visitDate'};
		my $centralPcrResult = $centralPCRsByVisits{$visitName}->{'pcrResult'};
		if ($centralPcrResult && ($centralPcrResult eq 'NEG' || $centralPcrResult eq 'POS')) {
			$symptomsWithCentralPCR = 1;
		}
		if ($centralPcrResult && $centralPcrResult eq 'POS') {
			$symptomsWithPositiveCentralPCR = 1;
		}
		my $localVisitDate       = $localPCRsByVisits{$visitName}->{'visitDate'};
		my $localPcrResult       = $localPCRsByVisits{$visitName}->{'pcrResult'};
		my $localSpDevId         = $localPCRsByVisits{$visitName}->{'spDevId'};
		my %localDevices         = ();
		my %localPositiveDevices = ();
		if ($localPcrResult && ($localPcrResult eq 'NEG' || $localPcrResult eq 'POS')) {
			$symptomsWithLocalPCR = 1;
			$localDevices{$localSpDevId} = $localPcrResult;
		}
		if ($localPcrResult && ($localPcrResult eq 'POS')) {
			$symptomsWithPositiveLocalPCR = 1;
			$localPositiveDevices{$localSpDevId} = $localPcrResult;
		}
		if ($symptomsWithCentralPCR) {
			if ($symptomsWithPositiveCentralPCR == 1) {
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'central'}->{'symptomsWithPCR'}->{'positivePCR'}->{$arm}++;
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'central'}->{'symptomsWithPCR'}->{'positivePCR'}->{'total'}++;
			}
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'central'}->{'symptomsWithPCR'}->{$arm}++;
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'central'}->{'symptomsWithPCR'}->{'total'}++;
		} else {
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'central'}->{'symptomsWithoutPCR'}->{$arm}++;
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'central'}->{'symptomsWithoutPCR'}->{'total'}++;
		}
		if ($symptomsWithLocalPCR) {
			if ($symptomsWithPositiveLocalPCR == 1) {
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'local'}->{'symptomsWithPCR'}->{'positivePCR'}->{$arm}++;
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'local'}->{'symptomsWithPCR'}->{'positivePCR'}->{'total'}++;
			}
			# say $out "$subjectId;$arm;$symptomDatetime;$visitName;$hasOfficialSymptoms;$symptomsWithPositiveLocalPCR;$symptomsWithPositiveCentralPCR;$centralVisitDate;$centralPcrResult;$localVisitDate;$localPcrResult;$localSpDevId;";
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'local'}->{'symptomsWithPCR'}->{$arm}++;
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'local'}->{'symptomsWithPCR'}->{'total'}++;
		} else {
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'local'}->{'symptomsWithoutPCR'}->{$arm}++;
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'local'}->{'symptomsWithoutPCR'}->{'total'}++;
		}
		if ($symptomsWithCentralPCR || $symptomsWithLocalPCR) {
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'localOrCentral'}->{'symptomsWithPCR'}->{$arm}++;
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'localOrCentral'}->{'symptomsWithPCR'}->{'total'}++;
		} else {
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'localOrCentral'}->{'symptomsWithoutPCR'}->{$arm}++;
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'localOrCentral'}->{'symptomsWithoutPCR'}->{'total'}++;
		}
		if ($symptomsWithCentralPCR && $symptomsWithLocalPCR) {
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'symptomsWithPCR'}->{$arm}++;
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'symptomsWithPCR'}->{'total'}++;

			if ($symptomsWithPositiveLocalPCR == 0 && $symptomsWithPositiveCentralPCR == 1) {
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'negativeLocalPositiveCentral'}->{$arm}++;
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'negativeLocalPositiveCentral'}->{'total'}++;
			}
			if ($symptomsWithPositiveLocalPCR == 1 && $symptomsWithPositiveCentralPCR == 0) {
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'positiveLocalNegativeCentral'}->{$arm}++;
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'positiveLocalNegativeCentral'}->{'total'}++;
			}

			if (
				($symptomsWithPositiveCentralPCR == 1 && $symptomsWithPositiveLocalPCR == 1) ||
				($symptomsWithPositiveCentralPCR == 0 && $symptomsWithPositiveLocalPCR == 0)
			) {
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'noConflict'}->{$arm}++;
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
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'conflict'}->{'byGroups'}->{$arm}->{'total'}++;
				for my $device (sort keys %localDevices) {
					$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'conflict'}->{'byDevices'}->{$device}++;
				}
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'conflict'}->{'total'}++;
			}
		} else {
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'symptomsWithoutPCR'}->{$arm}++;
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'localAndCentral'}->{'symptomsWithoutPCR'}->{'total'}++;
		}
		$stats{'symptomsAnalysis'}->{'symptoms'}->{'symptomsSets'}->{$arm}->{'total'}++;
		$stats{'symptomsAnalysis'}->{'symptoms'}->{'symptomsSets'}->{'total'}++;
	}
	# die "indeed" if $subjectId eq '10681009';
}
close $outChildren;

open my $outMissingVisit1, '>:utf8', 'subjects_with_dose1_and_no_test.csv';
say $outMissingVisit1 "subjectId;ageYears;arm;sex;randomizationDatetime;missingFromAdva;missingFromPCR;";
for my $subjectId (sort{$a <=> $b} keys %missingVisit1Tests) {
	my $ageYears              = $missingVisit1Tests{$subjectId}->{'ageYears'}              // die;
	my $arm                   = $missingVisit1Tests{$subjectId}->{'arm'}                   // die;
	my $sex                   = $missingVisit1Tests{$subjectId}->{'sex'}                   // die;
	my $randomizationDatetime = $missingVisit1Tests{$subjectId}->{'randomizationDatetime'} // die;
	my $missingFromAdva       = $missingVisit1Tests{$subjectId}->{'missingFromAdva'}       || 0;
	my $missingFromPCR        = $missingVisit1Tests{$subjectId}->{'missingFromPCR'}        || 0;
	say $outMissingVisit1 "$subjectId;$ageYears;$arm;$sex;$randomizationDatetime;$missingFromAdva;$missingFromPCR;";
}
close $outMissingVisit1;
# delete $stats{'0_primaryBreakdown'}; # Comment this line if you wish to review the primary breakdown.
p%stats;
# p%missingTests; # Stores the subjects absent from ADVA or PCR results.

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