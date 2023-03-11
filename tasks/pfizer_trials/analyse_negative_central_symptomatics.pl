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
# symptoms_positive_data();

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
	my $ageYears            = $demographics{$subjectId}->{'ageYears'}            // 'Unknown';
	my $unblindDatetime     = $advaData{$subjectId}->{'unblindDatetime'};
	$randomizationGroup     = 'BNT162b2' if $randomizationGroup =~ /BNT162b2 \(30/;
	my $unblindCompdate     = $cutoffCompdate;
	if ($unblindDatetime) {
		($unblindCompdate)   = split ' ', $unblindDatetime;
		$unblindCompdate        =~ s/\D//g;
	}
	if ($randomizationGroup eq 'Unknown') {
		$stats{'noKnownRandomizationGroup'}++;
		next;
	}

	my ($trialSiteId) = $subjectId =~ /(....)..../;

	# Reorganizing symptoms by dates.
	my ($hasSymptoms, 
		$firstSymptomDate,
		$firstSymptomVisit,
		%symptomsByDates) = subject_symptoms_by_dates($subjectId, $unblindCompdate);

	# Reorganizing Central PCRs by dates.
	my ($hasPositiveCentralPCR,
		$firstPositiveCentralPCRDate,
		$firstPositiveCentralPCRVisit,
		%centralPCRsByDates)    = subject_central_pcrs_by_dates($subjectId, $unblindCompdate);

	# Reorganizing Local PCRs by dates.
	my ($hasPositiveLocalPCR,
		$firstPositiveLocalPCRDate,
		$firstPositiveLocalPCRVisit,
		%localPCRsByDates)      = subject_local_pcrs_by_dates($subjectId, $unblindCompdate);

	$firstPositiveCentralPCRDate  = '' unless $firstPositiveCentralPCRDate;
	$firstPositiveLocalPCRDate    = '' unless $firstPositiveLocalPCRDate;
	$firstPositiveCentralPCRVisit = '' unless $firstPositiveCentralPCRVisit;
	$firstPositiveLocalPCRVisit   = '' unless $firstPositiveLocalPCRVisit;

	my $symptomsRefDate = $cutoffCompdate;
	if ($firstSymptomDate) {
		# $symptomsRefDate = $firstSymptomDate;
	}
	my ($fDY, $fDM, $fDD)    = $symptomsRefDate  =~ /(....)(..)(..)/;
	my ($fDsY, $fDsM, $fDsD) = $dose1Date        =~ /(....)(..)(..)/;

	my $daysOfExposureToSymptoms = time::calculate_days_difference("$fDsY-$fDsM-$fDsD 12:00:00", "$fDY-$fDM-$fDD 12:00:00");
	# say "hasSymptoms                  : [$hasSymptoms]";
	# say "firstSymptomDate             : [$firstSymptomDate]";
	# say "firstSymptomVisit            : [$firstSymptomVisit]";
	# say "hasPositiveCentralPCR        : [$hasPositiveCentralPCR]";
	# say "firstPositiveCentralPCRDate  : [$firstPositiveCentralPCRDate]";
	# say "firstPositiveCentralPCRVisit : [$firstPositiveCentralPCRVisit]";
	# say "hasPositiveLocalPCR          : [$hasPositiveLocalPCR]";
	# say "firstPositiveLocalPCRDate    : [$firstPositiveLocalPCRDate]";
	# say "firstPositiveLocalPCRVisit   : [$firstPositiveLocalPCRVisit]";
	# say "daysOfExposureToSymptoms     : [$daysOfExposureToSymptoms]";

	$stats{'subjects'}->{'total'}++;
	$stats{'subjects'}->{'byArm'}->{$trialSiteId}->{$randomizationGroup}->{'total'}++;
	$stats{'subjects'}->{'byArm'}->{$trialSiteId}->{$randomizationGroup}->{'totalDaysOfExposure'} += $daysOfExposureToSymptoms;
	if ($hasSymptoms) {
		$stats{'subjects'}->{'totalSymptomatic'}++;
		$stats{'subjects'}->{'byArm'}->{$trialSiteId}->{$randomizationGroup}->{'totalSymptomatic'}++;
	}
}

my %trialSiteSites = ();
for my $trialSiteId (sort{$a <=> $b} keys %{$stats{'subjects'}->{'byArm'}}) {
	my $totalBNT162b2Subjects    = $stats{'subjects'}->{'byArm'}->{$trialSiteId}->{'BNT162b2'}->{'total'} // die;
	my $totalPlaceboSubjects     = $stats{'subjects'}->{'byArm'}->{$trialSiteId}->{'Placebo'}->{'total'}  // die;
	my $totalBNT162b2DOE         = $stats{'subjects'}->{'byArm'}->{$trialSiteId}->{'BNT162b2'}->{'totalDaysOfExposure'} // die;
	my $totalPlaceboDOE          = $stats{'subjects'}->{'byArm'}->{$trialSiteId}->{'Placebo'}->{'totalDaysOfExposure'}  // die;
	my $totalBNT162b2Symptomatic = $stats{'subjects'}->{'byArm'}->{$trialSiteId}->{'BNT162b2'}->{'totalSymptomatic'} // 0;
	my $totalPlaceboSymptomatic  = $stats{'subjects'}->{'byArm'}->{$trialSiteId}->{'Placebo'}->{'totalSymptomatic'}  // 0;
	my $iRBNT162b2               = $totalBNT162b2Symptomatic / $totalBNT162b2DOE * 10000;
	my $iRPlacebo                = $totalPlaceboSymptomatic  / $totalPlaceboDOE  * 10000;
	my $chi                      = chi_squared($totalBNT162b2Symptomatic, $totalBNT162b2DOE, $totalPlaceboSymptomatic, $totalPlaceboDOE);
	my $pValue                   = 1 - Math::CDF::pchisq($chi, $df);
	# say "chi : [$chi], p-value: [$pValue]";
	if ($chi < 0.01) {
		say "*" x 50;
		say "trialSiteId                  : [$trialSiteId]";
		say "totalBNT162b2Subjects        : [$totalBNT162b2Subjects]";
		say "totalPlaceboSubjects         : [$totalPlaceboSubjects]";
		say "totalBNT162b2DOE             : [$totalBNT162b2DOE]";
		say "totalPlaceboDOE              : [$totalPlaceboDOE]";
		say "totalBNT162b2Symptomatic     : [$totalBNT162b2Symptomatic]";
		say "totalPlaceboSymptomatic      : [$totalPlaceboSymptomatic]";
		say "iRBNT162b2                   : [$iRBNT162b2]";
		say "iRPlacebo                    : [$iRPlacebo]";
		say "chi                          : [$chi]";
		say "pValue                       : [$pValue]";
	}
}
# open my $out, '>:utf8', 'symptomatic_subjects_by_sites.csv';
# say $out "Trial Site Id;Chi;P-Value;BNT162b2 - Incidence Rate;BNT162b2 - Symptomatic Subjects;BNT162b2 - Days of Exposure;BNT162b2 - Total Subjects;Placebo - Incidence Rate;Placebo - Symptomatic Subjects;Placebo - Days of Exposure;Placebo - Total Subjects;";
# 	say $out "$trialSiteId;$chi;$pValue;$iRBNT162b2;$totalBNT162b2Symptomatic;$totalBNT162b2DOE;$totalBNT162b2Subjects;$iRPlacebo;$totalPlaceboSymptomatic;$totalPlaceboDOE;$totalPlaceboSubjects;"
# close $out;

my $chi = chi_squared(53516, 54867, 1475879, 1474440);
say "chi : [$chi]";
my $pValue = 1 - Math::CDF::pchisq($chi, $df);
say "chi : [$chi], p-value: [$pValue]";

sub chi_squared {
     my ($a, $b, $c, $d) = @_;
     return 0 if($a + $c == 0);
     return 0 if($b + $d == 0);
     my $n = $a + $b + $c + $d;
     return (($n * ($a * $d - $b * $c) ** 2) / (($a + $b)*($c + $d)*($a + $c)*($b + $d)));
}

# p%stats;
# die;

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

sub subject_central_pcrs_by_dates {
	my ($subjectId,
		$unblindCompdate) = @_;
	my %centralPCRsByDates    = ();
	my $hasPositiveCentralPCR = 0;
	my $firstPositiveCentralPCRDate;
	my $firstPositiveCentralPCRVisit;
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
		$centralPCRsByDates{$visitCompdate}->{'visitDate'} = $visitDate;
		$centralPCRsByDates{$visitCompdate}->{'pcrResult'} = $pcrResult;
		$centralPCRsByDates{$visitCompdate}->{'visitName'} = $visitName;
		if ($pcrResult eq 'POS') {
			$hasPositiveCentralPCR = 1;
			if (!$firstPositiveCentralPCRDate) {

			}
		}
	}
	for my $compdate (sort{$a <=> $b} keys %centralPCRsByDates) {
		my $visitName = $centralPCRsByDates{$compdate}->{'visitName'} // die;
		my $pcrResult = $centralPCRsByDates{$compdate}->{'pcrResult'} // die;
		if ($pcrResult eq 'POS') {
			if (!$firstPositiveCentralPCRDate) {
				$firstPositiveCentralPCRDate = $compdate;
				$firstPositiveCentralPCRVisit = $visitName;
				last;
			}
		}
	}
	return (
		$hasPositiveCentralPCR,
		$firstPositiveCentralPCRDate,
		$firstPositiveCentralPCRVisit,
		%centralPCRsByDates);
}

sub subject_local_pcrs_by_dates {
	my ($subjectId,
		$unblindCompdate) = @_;
	my %localPCRsByDates    = ();
	my $hasPositiveLocalPCR = 0;
	my $firstPositiveLocalPCRDate;
	my $firstPositiveLocalPCRVisit;
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
		$localPCRsByDates{$visitCompdate}->{'visitDate'} = $visitDate;
		$localPCRsByDates{$visitCompdate}->{'pcrResult'} = $pcrResult;
		$localPCRsByDates{$visitCompdate}->{'visitName'} = $visitName;
		$localPCRsByDates{$visitCompdate}->{'spDevId'}   = $spDevId;
		if ($pcrResult eq 'POS') {
			$hasPositiveLocalPCR = 1;
		}
	}
	for my $compdate (sort{$a <=> $b} keys %localPCRsByDates) {
		my $visitName = $localPCRsByDates{$compdate}->{'visitName'} // die;
		my $pcrResult = $localPCRsByDates{$compdate}->{'pcrResult'} // die;
		if ($pcrResult eq 'POS') {
			if (!$firstPositiveLocalPCRDate) {
				$firstPositiveLocalPCRDate = $compdate;
				$firstPositiveLocalPCRVisit = $visitName;
				last;
			}
		}
	}
	return ($hasPositiveLocalPCR,
		$firstPositiveLocalPCRDate,
		$firstPositiveLocalPCRVisit,
		%localPCRsByDates);
}

sub subject_symptoms_by_dates {
	my ($subjectId,
		$unblindCompdate) = @_;
	my $referenceCompdate = ref_from_unblind($unblindCompdate);
	my %symptomsByDates = ();
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
			$symptomsByDates{$symptomCompdate}->{'symptoms'}->{$symptomName} = 1;
			$totalSymptoms++;
		}
		next unless $totalSymptoms;
		$hasSymptoms  = 1;
		$symptomsByDates{$symptomCompdate}->{'onsetStartOffset'}    = $onsetStartOffset;
		$symptomsByDates{$symptomCompdate}->{'formerSymptomDate'}   = $formerSymptomDate;
		$symptomsByDates{$symptomCompdate}->{'visitName'}           = $visitName;
		$symptomsByDates{$symptomCompdate}->{'symptomDate'}         = $symptomDate;
		$symptomsByDates{$symptomCompdate}->{'totalSymptoms'}       = $totalSymptoms;
		$symptomsByDates{$symptomCompdate}->{'endDatetime'}         = $endDatetime;
		$symptomsByDates{$symptomCompdate}->{'hasOfficialSymptoms'} = $hasOfficialSymptoms;
	}
	for my $compdate (sort{$a <=> $b} keys %symptomsByDates) {
		my $visitName = $symptomsByDates{$compdate}->{'visitName'} // die;
		if (!$firstSymptomDate) {
			$firstSymptomDate = $compdate;
			$firstSymptomVisit = $visitName;
			last;
		}
	}
	# p%symptomsByDates;
	# die;
	return (
		$hasSymptoms,
		$firstSymptomDate,
		$firstSymptomVisit,
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