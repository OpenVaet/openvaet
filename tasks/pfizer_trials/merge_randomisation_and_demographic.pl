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

my $sasDataFile       = "raw_data/pfizer_trials/sas_data/pfizer_sas_data_patients.json";
my $randomizationFile = "public/doc/pfizer_trials/pfizer_trial_randomization.json";
my $advaFile          = "public/doc/pfizer_trials/pfizer_adva_patients.json";
my $trialSubjectsFile = "public/doc/pfizer_trials/pfizer_trial_demographics.json";
my $positiveCasesFile = "public/doc/pfizer_trials/pfizer_trial_positive_cases_april_2021.json";
my $exclusionsFile1   = "public/doc/pfizer_trials/pfizer_trial_exclusions_1.json";
my $exclusionsFile2   = "public/doc/pfizer_trials/pfizer_trial_exclusions_2.json";
my $allCasesApril2021 = "public/doc/pfizer_trials/pfizer_trial_positive_cases_april_2021.json";
# my $screeningDates    = 'public/doc/pfizer_trials/subjects_screening_dates.json';

my %sasData           = ();
my %screeningDates    = ();
my %randomizationData = ();
my %trialSubjectsData = ();
my %positiveCasesData = ();
my %exclusionsData1   = ();
my %exclusionsData2   = ();
my %advaData          = ();
my %positive2021Data  = ();
sas_data();                 # Loads the JSON formatted SAS data.
adva_data();                # Loads the JSON formatted ADVA data.
demographic_data();         # Loads the JSON formatted trial subjects data.
randomization_data();       # Loads the JSON formatted randomization data.
positive_cases_data();      # Loads the JSON formatted positive cases data.
positive_cases_2021_data(); # Loads the JSON formatted positive cases data.
exclusions_data_1();        # Loads the JSON formatted exclusions data 1.
exclusions_data_2();        # Loads the JSON formatted exclusions data 2.
# screening_dates();          # Loads the JSON formatted screening dates merged from overall analysis.

my $missing = 0;
my $positiveCovidSwab = 0;
open my $out, '>:utf8', 'public/doc/pfizer_trials/missing_patients_ids_in_files.csv';
open my $out2, '>:utf8', 'public/doc/pfizer_trials/merged_april_2021_data.csv';
say $out2
	"uSubjectId;trialSubjectsPageNumber;ageYears;hasHIV;isPhase1;" .
	"sex;screeningDate;randomizationGroup;randomizationPageNumber;randomizationDate;" .
	"dose1;dose1Date;dose2;dose2Date;dose3;" .
	"dose3Date;dose4;dose4Date;positiveCasePageNumber;visit1NBindingAssayTest;" .
	"nucleicAcidAmplificationTest1;nucleicAcidAmplificationTest2;swabDate;centralLabTest;symptomstartDate;" .
	"localLabTest;symptomsEndDate;";
my %merged         = ();
my %stats          = ();
my %patientsList   = ();
my @daysOfFollowUp = ();
for my $subjectId (sort keys %randomizationData) {
	$patientsList{$subjectId} = 1;
	die unless exists $sasData{'subjects'}->{$subjectId};
	# p$randomizationData{$subjectId};
	# say "subjectId : $subjectId";
	my $trialSubjectsPageNumber = $trialSubjectsData{$subjectId}->{'pageNum'}                 // 'Ukn';
	my $ageYears                = $trialSubjectsData{$subjectId}->{'ageYears'}                // 'Ukn';
	my $hasHIV                  = $trialSubjectsData{$subjectId}->{'hasHIV'}                  // 'Ukn';
	my $isPhase1                = $trialSubjectsData{$subjectId}->{'isPhase1'}                // 'Ukn';
	my $sex                     = $trialSubjectsData{$subjectId}->{'sex'}                     // 'Ukn';
	my $screeningMonth          = $trialSubjectsData{$subjectId}->{'month'}                   // 'Ukn';
	my $screeningDate           = $trialSubjectsData{$subjectId}->{'screeningDate'}           // 'Ukn';
	my $screeningWeekNumber     = $trialSubjectsData{$subjectId}->{'weekNumber'}              // 'Ukn';
	my $screeningYear           = $trialSubjectsData{$subjectId}->{'year'}                    // 'Ukn';
	my $randomizationPageNumber = $randomizationData{$subjectId}->{'pageNum'}                 // die;
	my $randomizationGroup      = $randomizationData{$subjectId}->{'randomizationGroup'}      // 'Ukn';
	my $uSubjectId              = $randomizationData{$subjectId}->{'uSubjectId'}              // die;
	my $randomizationMonth      = $randomizationData{$subjectId}->{'randomizationMonth'}      // die;
	my $randomizationDate       = $randomizationData{$subjectId}->{'randomizationDate'}       // die;
	my $randomizationWeekNumber = $randomizationData{$subjectId}->{'randomizationWeekNumber'} // die;
	my $randomizationYear       = $randomizationData{$subjectId}->{'randomizationYear'}       // die;

	# Verifies how many doses are placebo and may have dosage to slide.
	verify_dosage($subjectId);

	# Creates end usage object.
	my %o = ();
	$o{'subjectId'}               = $subjectId;
	$o{'uSubjectId'}         = $uSubjectId;
	$o{'trialSubjectsPageNumber'} = $trialSubjectsPageNumber;
	$o{'ageYears'}                = $ageYears;
	$o{'hasHIV'}                  = $hasHIV;
	$o{'isPhase1'}                = $isPhase1;
	$o{'sex'}                     = $sex;
	$o{'screeningMonth'}          = $screeningMonth;
	$o{'screeningDate'}           = $screeningDate;
	$o{'screeningWeekNumber'}     = $screeningWeekNumber;
	$o{'screeningYear'}           = $screeningYear;
	$o{'randomizationGroup'}      = $randomizationGroup;
	$o{'randomizationPageNumber'} = $randomizationPageNumber;
	$o{'randomizationMonth'}      = $randomizationMonth;
	$o{'randomizationDate'}       = $randomizationDate;
	$o{'randomizationWeekNumber'} = $randomizationWeekNumber;
	$o{'randomizationYear'}       = $randomizationYear;
	for my $doseNum (sort{$a <=> $b} keys %{$randomizationData{$subjectId}->{'doses'}}) {
		my $dose           = $randomizationData{$subjectId}->{'doses'}->{$doseNum}->{'dose'}       // die;
		my $doseDate       = $randomizationData{$subjectId}->{'doses'}->{$doseNum}->{'doseDate'}   // die;
		my $dosage         = $randomizationData{$subjectId}->{'doses'}->{$doseNum}->{'dosage'};
		my $doseMonth      = $randomizationData{$subjectId}->{'doses'}->{$doseNum}->{'month'}      // die;
		my $doseYear       = $randomizationData{$subjectId}->{'doses'}->{$doseNum}->{'year'}       // die;
		my $doseWeekNumber = $randomizationData{$subjectId}->{'doses'}->{$doseNum}->{'weekNumber'} // die;
		$o{'doses'}->{$doseNum}->{'dose'}           = $dose;
		$o{'doses'}->{$doseNum}->{'doseDate'}       = $doseDate;
		$o{'doses'}->{$doseNum}->{'dosage'}         = $dosage;
		$o{'doses'}->{$doseNum}->{'doseMonth'}      = $doseMonth;
		$o{'doses'}->{$doseNum}->{'doseYear'}       = $doseYear;
		$o{'doses'}->{$doseNum}->{'doseWeekNumber'} = $doseWeekNumber;
	}

	# If the patient has suffered a positive case, incrementing data.
	my ($lastDose, $lastDoseDate);
	my ($positiveCasePageNumber, $symptomstartDate, $symptomsEndDate, $nucleicAcidAmplificationTest1, $nucleicAcidAmplificationTest2, $visit1NBindingAssayTest, $centralLabTest, $localLabTest, $swabDate);
	if (exists $positiveCasesData{$subjectId}) {
		$positiveCovidSwab++;
		$nucleicAcidAmplificationTest1 = $positiveCasesData{$subjectId}->{'nucleicAcidAmplificationTest1'} // die;
		$nucleicAcidAmplificationTest2 = $positiveCasesData{$subjectId}->{'nucleicAcidAmplificationTest2'} // die;
		$visit1NBindingAssayTest       = $positiveCasesData{$subjectId}->{'visit1NBindingAssayTest'}       // die;
		$symptomstartDate              = $positiveCasesData{$subjectId}->{'symptomstartDate'}              // die;
		$centralLabTest                = $positiveCasesData{$subjectId}->{'centralLabTest'}                // die;
		$swabDate                      = $positiveCasesData{$subjectId}->{'swabDate'}                      // die;
		$positiveCasePageNumber        = $positiveCasesData{$subjectId}->{'pageNum'}                       // die;
		$localLabTest                  = $positiveCasesData{$subjectId}->{'localLabTest'};
		$symptomsEndDate               = $positiveCasesData{$subjectId}->{'symptomsEndDate'};
		# say "symptomstartDate : $symptomstartDate";
		for my $doseNum (sort{$a <=> $b} keys %{$randomizationData{$subjectId}->{'doses'}}) {
			my $dose           = $randomizationData{$subjectId}->{'doses'}->{$doseNum}->{'dose'}       // die;
			my $doseDate       = $randomizationData{$subjectId}->{'doses'}->{$doseNum}->{'doseDate'}   // die;
			next if $doseDate > $symptomstartDate;
			$lastDose = $dose;
			$lastDoseDate = $doseDate;
		}
		die unless $lastDose;
	}
	$o{'positiveCasePageNumber'}        = $positiveCasePageNumber;
	$o{'symptomstartDate'}              = $symptomstartDate;
	$o{'symptomsEndDate'}               = $symptomsEndDate;
	$o{'centralLabTest'}                = $centralLabTest;
	$o{'localLabTest'}                  = $localLabTest;
	$o{'swabDate'}                      = $swabDate;
	$o{'visit1NBindingAssayTest'}       = $visit1NBindingAssayTest;
	$o{'nucleicAcidAmplificationTest1'} = $nucleicAcidAmplificationTest1;
	$o{'nucleicAcidAmplificationTest2'} = $nucleicAcidAmplificationTest2;
	$o{'trialSubjectsPageNumber'}       = $trialSubjectsPageNumber;
	$o{'ageYears'}                      = $ageYears;
	$o{'hasHIV'}                        = $hasHIV;
	$o{'isPhase1'}                      = $isPhase1;
	$o{'sex'}                           = $sex;
	$o{'screeningMonth'}                = $screeningMonth;
	$o{'screeningDate'}                 = $screeningDate;
	$o{'screeningWeekNumber'}           = $screeningWeekNumber;
	$o{'screeningYear'}                 = $screeningYear;
	$o{'randomizationGroup'}            = $randomizationGroup;
	$o{'randomizationPageNumber'}       = $randomizationPageNumber;
	$o{'randomizationMonth'}            = $randomizationMonth;
	$o{'randomizationDate'}             = $randomizationDate;
	$o{'randomizationWeekNumber'}       = $randomizationWeekNumber;
	$o{'randomizationYear'}             = $randomizationYear;

	my $dose1     = $o{'doses'}->{'1'}->{'dose'};
	my $dose1Date = $o{'doses'}->{'1'}->{'doseDate'};
	$o{'dose1'}                   = $dose1;
	$o{'dose1Date'}               = $dose1Date;
	my $dose2     = $o{'doses'}->{'2'}->{'dose'};
	my $dose2Date = $o{'doses'}->{'2'}->{'doseDate'};
	$o{'dose2'}                   = $dose2;
	$o{'dose2Date'}               = $dose2Date;
	my $dose3     = $o{'doses'}->{'3'}->{'dose'};
	my $dose3Date = $o{'doses'}->{'3'}->{'doseDate'};
	$o{'dose3'}                   = $dose3;
	$o{'dose3Date'}               = $dose3Date;
	my $dose4     = $o{'doses'}->{'4'}->{'dose'};
	my $dose4Date = $o{'doses'}->{'4'}->{'doseDate'};
	$o{'dose4'}                   = $dose4;
	$o{'dose4Date'}               = $dose4Date;

	############################## DEBUG.
	# Spread of cases by positive swap date.
	if (exists $positiveCasesData{$subjectId}) {

		# Fixing randomization group when missing.
		$o{'randomizationGroupFixed'} = 0;
		if ($randomizationGroup eq 'Ukn') {
			# next;
			$randomizationGroup = $o{'doses'}->{'1'}->{'dose'} // die;
			if ($randomizationGroup eq 'BNT162b2') {
				$randomizationGroup = $o{'doses'}->{'1'}->{'dose'} . ' ' . $o{'doses'}->{'1'}->{'dosage'};
			}
			$o{'randomizationGroup'}      = $randomizationGroup;
			$o{'randomizationGroupFixed'} = 1;
			# p%o;
		}
		my $randomizationGroup = $o{'randomizationGroup'} // die;
		my $swabDate = $positiveCasesData{$subjectId}->{'swabDate'} // die;
		# say "randomizationGroup : $randomizationGroup";
		# p$positive2021Data{$subjectId};
		next unless $dose2Date;
		if ($swabDate <= 20201114 && $swabDate >= ($dose2Date + 6)) {
			$stats{$randomizationGroup}->{$swabDate}++;
		}
		# p%o;
		# die;
	}

	next;

	# if ($uSubjectId eq 'C4591001 1001 10011004') {
	# 	p%o;
	# 	die;
	# }
	# p%o;
	# die;

	next unless $randomizationDate && ($randomizationDate >= '20200720' && $randomizationDate <= 20201114); # Fernando's 2 doses in efficacy group 14 November data supposed cut-off.
	next unless $dose1Date; # --> 43.442
	next unless $dose2Date; # --> 
	next unless $dose2Date && ($dose2Date <= 20201114); # Fernando's 2 doses in efficacy

	# Fixing randomization group when missing.
	$o{'randomizationGroupFixed'} = 0;
	if ($randomizationGroup eq 'Ukn') {
		# next;
		$randomizationGroup = $o{'doses'}->{'1'}->{'dose'} // die;
		if ($randomizationGroup eq 'BNT162b2') {
			$randomizationGroup = $o{'doses'}->{'1'}->{'dose'} . ' ' . $o{'doses'}->{'1'}->{'dosage'};
		}
		$o{'randomizationGroup'}      = $randomizationGroup;
		$o{'randomizationGroupFixed'} = 1;
		# p%o;
	}

	# Evaluating time to follow-up (data cut-off on November 14, 2020).
	# say "dose1Date : $dose1Date";
	next if $isPhase1;                                  # Excludes phase 1.
	next if $hasHIV;
	if (exists $exclusionsData1{$uSubjectId}) {
		my $exclusionsDate = $exclusionsData1{$uSubjectId}->{'exclusionsDate'} // die;
		if ($exclusionsDate <= 20201114) {
			next;
		}
	}
	if (exists $exclusionsData2{$uSubjectId}) {
		my $exclusionsDate = $exclusionsData2{$uSubjectId}->{'exclusionsDate'} // die;
		if ($exclusionsDate <= 20201114) {
			next;
		}
	}
	if ($visit1NBindingAssayTest) {
		next unless
		$visit1NBindingAssayTest       eq 'Neg' &&
		$nucleicAcidAmplificationTest1 eq 'Neg' &&
		$nucleicAcidAmplificationTest2 eq 'Neg';
	}
	my $daysDifferenceBetweenDoses1And2 = calc_days_difference($dose1Date, $dose2Date);
	next unless $daysDifferenceBetweenDoses1And2 >= 19 && $daysDifferenceBetweenDoses1And2 <= 42;
	my $dosesToCovidDaysDifference;
	if ($swabDate && $centralLabTest) {
		die unless $centralLabTest eq 'Pos';
		$dosesToCovidDaysDifference = calc_days_difference($dose2Date, $swabDate);
		next unless $dosesToCovidDaysDifference > 0 && $dosesToCovidDaysDifference > 7;
		# say "dose2Date : $dose2Date";
		# say "swabDate  : $swabDate";
		# say "dosesToCovidDaysDifference : $dosesToCovidDaysDifference";
	}
	my $daysToCutOff = calc_days_difference($dose2Date, '20201114');
	next unless $daysToCutOff >= 13;
	# push @daysOfFollowUp, $daysToCutOff;
	if ($swabDate && $swabDate <= 20201114) {
		# p%o;
		$stats{'byLastDose'}->{'Total'}++;
		$stats{'byLastDose'}->{$lastDose}++;
	}
	# p$advaData{$uSubjectId};
	# p%o;
	# die;
	# say "daysToCutOff : $daysToCutOff";
	# if ($randomizationGroup eq 'Ukn') {                 # Unknown randomization group.
	# 	next;
	# }
	# next unless $dose2Date && ($dose2Date <= 20201114); # Fernando's 2 doses in efficacy group 14 November data supposed cut-off.
	# next unless $dose1Date && $dose2Date;
	# die "ageYears : $ageYears" if $ageYears < 16;
	# $o{'dosesToCovidDaysDifference'}      = $dosesToCovidDaysDifference;
	# $o{'daysDifferenceBetweenDoses1And2'} = $daysDifferenceBetweenDoses1And2;

	# Incrementing stats.
	# $stats{'byDosesDaysDifference'}->{$daysDifferenceBetweenDoses1And2}++;
	$stats{'byGroups'}->{'Total'}++;
	$stats{'byGroups'}->{$randomizationGroup}++;
	# say $out2
	# 	"$uSubjectId;$trialSubjectsPageNumber;$ageYears;$hasHIV;$isPhase1;" .
	# 	"$sex;$screeningDate;$randomizationGroup;$randomizationPageNumber;$randomizationDate;" .
	# 	"$dose1;$dose1Date;$dose2;$dose2Date;$dose3;" .
	# 	"$dose3Date;$dose4;$dose4Date;$positiveCasePageNumber;$visit1NBindingAssayTest;" .
	# 	"$nucleicAcidAmplificationTest1;$nucleicAcidAmplificationTest2;$swabDate;$centralLabTest;$symptomstartDate;" .
	# 	"$localLabTest;$symptomsEndDate;";

	$merged{$uSubjectId} = \%o;
	# my $dose1Datetime           = $advaData{$subjectId}->{'dose1Datetime'} // die "subjectId : [$subjectId]";
	# my $advaPhase               = $advaData{$subjectId}->{'phase'}         // die "subjectId : [$subjectId]";
	# $o{'advaPhase'}             = $advaPhase;
	# p$randomizationData{$uSubjectId};
	# p$trialSubjectsData{$uSubjectId};
}
close $out2;


p%stats;
open my $out4, '>:utf8', 'chart_by_date.csv';
for my $arm (sort keys %stats) {
	my $cumTot = 0;
	for my $date (sort{$a <=> $b} keys %{$stats{$arm}}) {
		my ($y, $m, $d) = $date =~ /(....)(..)(..)/;
		my $printDt = "$y-$m-$d";
		my $total = $stats{$arm}->{$date} // die;
		$cumTot += $total;
		say $out4 "$arm;$printDt;$cumTot";
	}
}
close $out4;

# say "median : " . median(@daysOfFollowUp);

sub median
{
    my @vals = sort {$a <=> $b} @_;
    my $len = @vals;
    if($len%2) #odd?
    {
        return $vals[int($len/2)];
    }
    else #even
    {
        return ($vals[int($len/2)-1] + $vals[int($len/2)])/2;
    }
}



open my $out3, '>:utf8', 'raw_data/pfizer_trials/merged_randomization_and_demographic.json';
print $out3 encode_json\%merged;
close $out3;
say "positive : [$positiveCovidSwab] swabs subjects";
say "missing  : [$missing] in [trialSubjectsData] but in [randomizationData]";

$missing = 0;
my $okTot = 0;
for my $subjectId (sort keys %trialSubjectsData) {
	$patientsList{$subjectId} = 1;
	unless (exists $randomizationData{$subjectId}) {
		$missing++;
		my $pageNum = $trialSubjectsData{$subjectId}->{'pageNum'} // die;
		say $out "$subjectId;no trial subject randomization data;$pageNum";
		# p$trialSubjectsData{$subjectId};
		# p$randomizationData{$subjectId};
		# say "subjectId : $subjectId";
		# die;
	} else {
		$okTot++;
		# say "ok";
		# die;
	}
}
$missing = 0;
$okTot   = 0;
for my $subjectId (sort keys %positiveCasesData) {
	$patientsList{$subjectId} = 1;
	unless (exists $randomizationData{$subjectId}) {
		$missing++;
		my $pageNum = $positiveCasesData{$subjectId}->{'pageNum'} // die;
		say $out "$subjectId;positive case but no trial subject or randomization data;$pageNum";
		# p$positiveCasesData{$subjectId};
		# p$randomizationData{$subjectId};
		# p$trialSubjectsData{$subjectId};
		# say "subjectId : $subjectId";
		# die;
	} else {
		$okTot++;
		# say "ok";
		# die;
	}
}
say "missing  : [$missing] in [randomizationData] but in [positiveCasesData]. [$okTot] ok.";
close $out;
for my $subjectId (sort keys %exclusionsData1) {
	$patientsList{$subjectId} = 1;
}
for my $subjectId (sort keys %exclusionsData2) {
	$patientsList{$subjectId} = 1;
}
$missing = 0;
for my $subjectId (sort keys %advaData) {
	unless (exists $patientsList{$subjectId}) {
		$missing++;
		# say "$subjectId doesn't appear in the PDFs but appears in ADVA";
		# p$sasData{'subjects'}->{$subjectId};
		# p$randomizationData{$subjectId};
		# say "subjectId : $subjectId";
		# die;
	}
	$patientsList{$subjectId} = 1;
}
say "missing  : [$missing] in [randomizationData] but in [advaData]. [$okTot] ok.";
$missing = 0;
for my $subjectId (sort keys %{$sasData{'subjects'}}) {
	unless ($subjectId =~ /^\d\d\d\d\d\d\d\d$/) {
		p$sasData{'subjects'}->{$subjectId};
		die;
	}
	unless (exists $patientsList{$subjectId}) {
		$missing++;
		# say "$subjectId doesn't appear in the PDF";
		# p$sasData{'subjects'}->{$subjectId};
		# p$randomizationData{$subjectId};
		# say "subjectId : $subjectId";
		# die;
	}
	$patientsList{$subjectId} = 1;
}
say "missing  : [$missing] in [PDF data] but present in [SAS Files].";
my $totalPatientsIds = keys %patientsList;
say "total subjects identified : [$totalPatientsIds]";

sub sas_data {
	my $json;
	open my $in, '<:utf8', $sasDataFile;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%sasData = %$json;
	say "[$sasDataFile] -> patients : " . keys %{$sasData{'subjects'}};
}

sub adva_data {
	my $json;
	open my $in, '<:utf8', $advaFile;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%advaData = %$json;
	say "[$advaFile] -> patients : " . keys %advaData;
}

sub demographic_data {
	my $json;
	open my $in, '<:utf8', $trialSubjectsFile;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%trialSubjectsData = %$json;
	say "[$trialSubjectsFile] -> patients : " . keys %trialSubjectsData;
}

sub randomization_data {
	my $json;
	open my $in, '<:utf8', $randomizationFile;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%randomizationData = %$json;
	say "[$randomizationFile] -> patients : " . keys %randomizationData;
}

sub positive_cases_data {
	my $json;
	open my $in, '<:utf8', $positiveCasesFile;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%positiveCasesData = %$json;
	say "[$positiveCasesFile] -> patients : " . keys %positiveCasesData;
}

sub positive_cases_2021_data {
	my $json;
	open my $in, '<:utf8', $allCasesApril2021;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%positive2021Data = %$json;
	say "[$allCasesApril2021] -> patients : " . keys %positive2021Data;
}

sub exclusions_data_1 {
	my $json;
	open my $in, '<:utf8', $exclusionsFile1;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%exclusionsData1 = %$json;
	say "[$exclusionsFile1] -> patients : " . keys %exclusionsData1;
}

sub exclusions_data_2 {
	my $json;
	open my $in, '<:utf8', $exclusionsFile2;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%exclusionsData2 = %$json;
	say "[$exclusionsFile2] -> patients : " . keys %exclusionsData2;
}

sub verify_dosage {
	my ($subjectId) = @_;
	my $totalPlacebosToSlide = 0;
	my $hasVaccine  = 0;
	for my $doseNum (sort{$a <=> $b} keys %{$randomizationData{$subjectId}->{'doses'}}) {
		my $dose     = $randomizationData{$subjectId}->{'doses'}->{$doseNum}->{'dose'}     // die;
		my $doseDate = $randomizationData{$subjectId}->{'doses'}->{$doseNum}->{'doseDate'} // die;
		my $dosage   = $randomizationData{$subjectId}->{'doses'}->{$doseNum}->{'dosage'};
		if ($dosage && $dose eq 'Placebo') {
			$totalPlacebosToSlide++;
		} else {
			$hasVaccine = 1 if $dose ne 'Placebo';
		}
	}
	for my $doseNum (sort{$a <=> $b} keys %{$randomizationData{$subjectId}->{'doses'}}) {
		my $dose     = $randomizationData{$subjectId}->{'doses'}->{$doseNum}->{'dose'}     // die;
		my $doseDate = $randomizationData{$subjectId}->{'doses'}->{$doseNum}->{'doseDate'} // die;
		my $dosage   = $randomizationData{$subjectId}->{'doses'}->{$doseNum}->{'dosage'};
		my $doseTo = $doseNum + $totalPlacebosToSlide;
		if ($dosage && $dose eq 'Placebo' && $hasVaccine == 1 && exists $randomizationData{$subjectId}->{'doses'}->{$doseTo}) {
			$randomizationData{$subjectId}->{'doses'}->{$doseNum}->{'dosage'} = undef;
			$randomizationData{$subjectId}->{'doses'}->{$doseTo}->{'dosage'}  = $dosage;
		} else {
			if ($dosage && $dose eq 'Placebo') {
				$randomizationData{$subjectId}->{'doses'}->{$doseNum}->{'dosage'} = undef;
			}
		}
	}
}

sub calc_days_difference {
	my ($date1, $date2) = @_;
	die unless $date1 && $date2;
	my $date1Ftd = date_from_compdate($date1);
	my $date2Ftd = date_from_compdate($date2);
	# say "date1Ftd : $date1Ftd";
	# say "date2Ftd : $date2Ftd";
	my $daysDifference = time::calculate_days_difference($date1Ftd, $date2Ftd);
	return $daysDifference;
}

sub date_from_compdate {
	my ($date) = shift;
	my ($y, $m, $d) = $date =~ /(....)(..)(..)/;
	die unless $y && $m && $d;
	return "$y-$m-$d 12:00:00";
}