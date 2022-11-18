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

my $advaFile          = "raw_data/pfizer_trials/adva/pfizer_adva_patients.json";
my $randomizationFile = "public/doc/pfizer_trials/pfizer_trial_randomization.json";
my $trialSubjectsFile = "public/doc/pfizer_trials/pfizer_trial_demographics.json";
my $positiveCasesFile = "public/doc/pfizer_trials/pfizer_trial_positive_cases_april_2021.json";
my $exclusionsFile1   = "public/doc/pfizer_trials/pfizer_trial_exclusions_1.json";
my $exclusionsFile2   = "public/doc/pfizer_trials/pfizer_trial_exclusions_2.json";


my %randomizationData = ();
my %trialSubjectsData = ();
my %positiveCasesData = ();
my %exclusionsData1   = ();
my %exclusionsData2   = ();
my %advaData          = ();
adva_data();           # Loads the JSON formatted ADVA data.
demographic_data();       # Loads the JSON formatted trial subjects data.
randomization_data();  # Loads the JSON formatted randomization data.
positive_cases_data(); # Loads the JSON formatted positive cases data.
exclusions_data_1();   # Loads the JSON formatted exclusions data 1.
exclusions_data_2();   # Loads the JSON formatted exclusions data 2.

my $missing = 0;
my $positiveCovidSwab = 0;
open my $out, '>:utf8', 'public/doc/pfizer_trial_cases_mapping/missing_patients_ids_in_files.csv';
open my $out2, '>:utf8', 'public/doc/pfizer_trial_cases_mapping/merged_april_2021_data.csv';
say $out2
	"patientId;trialSubjectsPageNumber;ageYears;hasHIV;isPhase1;" .
	"sex;screeningDate;randomizationGroup;randomizationPageNumber;randomizationDate;" .
	"dose1;dose1Date;dose2;dose2Date;dose3;" .
	"dose3Date;dose4;dose4Date;positiveCasePageNumber;visit1NBindingAssayTest;" .
	"nucleicAcidAmplificationTest1;nucleicAcidAmplificationTest2;swabDate;centralLabTest;symptomstartDate;" .
	"localLabTest;symptomsEndDate;";
my %merged         = ();
my %stats          = ();
my %patientsList   = ();
my @daysOfFollowUp = ();
for my $patientId (sort keys %randomizationData) {
	$patientsList{$patientId} = 1;
	# p$randomizationData{$patientId};
	# say "patientId : $patientId";
	my $trialSubjectsPageNumber = $trialSubjectsData{$patientId}->{'pageNum'}                 // 'Ukn';
	my $ageYears                = $trialSubjectsData{$patientId}->{'ageYears'}                // 'Ukn';
	my $hasHIV                  = $trialSubjectsData{$patientId}->{'hasHIV'}                  // 'Ukn';
	my $isPhase1                = $trialSubjectsData{$patientId}->{'isPhase1'}                // 'Ukn';
	my $sex                     = $trialSubjectsData{$patientId}->{'sex'}                     // 'Ukn';
	my $screeningMonth          = $trialSubjectsData{$patientId}->{'month'}                   // 'Ukn';
	my $screeningDate           = $trialSubjectsData{$patientId}->{'screeningDate'}           // 'Ukn';
	my $screeningWeekNumber     = $trialSubjectsData{$patientId}->{'weekNumber'}              // 'Ukn';
	my $screeningYear           = $trialSubjectsData{$patientId}->{'year'}                    // 'Ukn';
	my $randomizationPageNumber = $randomizationData{$patientId}->{'pageNum'}                 // die;
	my $randomizationGroup      = $randomizationData{$patientId}->{'randomizationGroup'}      // 'Ukn';
	my $randomizationMonth      = $randomizationData{$patientId}->{'randomizationMonth'}      // die;
	my $randomizationDate       = $randomizationData{$patientId}->{'randomizationDate'}       // die;
	my $randomizationWeekNumber = $randomizationData{$patientId}->{'randomizationWeekNumber'} // die;
	my $randomizationYear       = $randomizationData{$patientId}->{'randomizationYear'}       // die;

	# Verifies how many doses are placebo and may have dosage to slide.
	verify_dosage($patientId);

	# Creates end usage object.
	my %o = ();
	$o{'patientId'}               = $patientId;
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
	for my $doseNum (sort{$a <=> $b} keys %{$randomizationData{$patientId}->{'doses'}}) {
		my $dose           = $randomizationData{$patientId}->{'doses'}->{$doseNum}->{'dose'}       // die;
		my $doseDate       = $randomizationData{$patientId}->{'doses'}->{$doseNum}->{'doseDate'}   // die;
		my $dosage         = $randomizationData{$patientId}->{'doses'}->{$doseNum}->{'dosage'};
		my $doseMonth      = $randomizationData{$patientId}->{'doses'}->{$doseNum}->{'month'}      // die;
		my $doseYear       = $randomizationData{$patientId}->{'doses'}->{$doseNum}->{'year'}       // die;
		my $doseWeekNumber = $randomizationData{$patientId}->{'doses'}->{$doseNum}->{'weekNumber'} // die;
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
	if (exists $positiveCasesData{$patientId}) {
		$positiveCovidSwab++;
		$nucleicAcidAmplificationTest1 = $positiveCasesData{$patientId}->{'nucleicAcidAmplificationTest1'} // die;
		$nucleicAcidAmplificationTest2 = $positiveCasesData{$patientId}->{'nucleicAcidAmplificationTest2'} // die;
		$visit1NBindingAssayTest       = $positiveCasesData{$patientId}->{'visit1NBindingAssayTest'}       // die;
		$symptomstartDate              = $positiveCasesData{$patientId}->{'symptomstartDate'}              // die;
		$centralLabTest                = $positiveCasesData{$patientId}->{'centralLabTest'}                // die;
		$swabDate                      = $positiveCasesData{$patientId}->{'swabDate'}                      // die;
		$positiveCasePageNumber        = $positiveCasesData{$patientId}->{'pageNum'}                       // die;
		$localLabTest                  = $positiveCasesData{$patientId}->{'localLabTest'};
		$symptomsEndDate               = $positiveCasesData{$patientId}->{'symptomsEndDate'};
		# say "symptomstartDate : $symptomstartDate";
		for my $doseNum (sort{$a <=> $b} keys %{$randomizationData{$patientId}->{'doses'}}) {
			my $dose           = $randomizationData{$patientId}->{'doses'}->{$doseNum}->{'dose'}       // die;
			my $doseDate       = $randomizationData{$patientId}->{'doses'}->{$doseNum}->{'doseDate'}   // die;
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

	# if ($patientId eq 'C4591001 1001 10011004') {
	# 	p%o;
	# 	die;
	# }

	# Fixing randomization group when missing.
	# $o{'randomizationGroupFixed'} = 0;
	next unless $randomizationDate && ($randomizationDate >= '20200720' && $randomizationDate <= 20201114); # Fernando's 2 doses in efficacy group 14 November data supposed cut-off.
	next unless $dose1Date; # --> 43.442
	next unless $dose2Date; # --> 
	next unless $dose2Date && ($dose2Date <= 20201114); # Fernando's 2 doses in efficacy
	my $dose1Datetime           = $advaData{$patientId}->{'dose1Datetime'} // die "patientId : [$patientId]";
	my $advaPhase               = $advaData{$patientId}->{'phase'}         // die "patientId : [$patientId]";
	$o{'advaPhase'}             = $advaPhase;
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
	if (exists $exclusionsData1{$patientId}) {
		my $exclusionsDate = $exclusionsData1{$patientId}->{'exclusionsDate'} // die;
		if ($exclusionsDate <= 20201114) {
			next;
		}
	}
	if (exists $exclusionsData2{$patientId}) {
		my $exclusionsDate = $exclusionsData2{$patientId}->{'exclusionsDate'} // die;
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
	p$advaData{$patientId};
	p%o;
	die;
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
	# 	"$patientId;$trialSubjectsPageNumber;$ageYears;$hasHIV;$isPhase1;" .
	# 	"$sex;$screeningDate;$randomizationGroup;$randomizationPageNumber;$randomizationDate;" .
	# 	"$dose1;$dose1Date;$dose2;$dose2Date;$dose3;" .
	# 	"$dose3Date;$dose4;$dose4Date;$positiveCasePageNumber;$visit1NBindingAssayTest;" .
	# 	"$nucleicAcidAmplificationTest1;$nucleicAcidAmplificationTest2;$swabDate;$centralLabTest;$symptomstartDate;" .
	# 	"$localLabTest;$symptomsEndDate;";

	$merged{$patientId} = \%o;
	# p$randomizationData{$patientId};
	# p$trialSubjectsData{$patientId};
}
close $out2;


p%stats;

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
for my $patientId (sort keys %trialSubjectsData) {
	$patientsList{$patientId} = 1;
	unless (exists $randomizationData{$patientId}) {
		$missing++;
		my $pageNum = $trialSubjectsData{$patientId}->{'pageNum'} // die;
		say $out "$patientId;no trial subject randomization data;$pageNum";
		# p$trialSubjectsData{$patientId};
		# p$randomizationData{$patientId};
		# say "patientId : $patientId";
		# die;
	} else {
		$okTot++;
		# say "ok";
		# die;
	}
}
$missing = 0;
$okTot   = 0;
for my $patientId (sort keys %positiveCasesData) {
	$patientsList{$patientId} = 1;
	unless (exists $randomizationData{$patientId}) {
		$missing++;
		my $pageNum = $positiveCasesData{$patientId}->{'pageNum'} // die;
		say $out "$patientId;positive case but no trial subject or randomization data;$pageNum";
		# p$positiveCasesData{$patientId};
		# p$randomizationData{$patientId};
		# p$trialSubjectsData{$patientId};
		# say "patientId : $patientId";
		# die;
	} else {
		$okTot++;
		# say "ok";
		# die;
	}
}
say "missing : [$missing] in [randomizationData] but in [positiveCasesData]. [$okTot] ok.";
close $out;
for my $patientId (sort keys %exclusionsData1) {
	$patientsList{$patientId} = 1;
}
for my $patientId (sort keys %exclusionsData2) {
	$patientsList{$patientId} = 1;
}
for my $patientId (sort keys %advaData) {
	$patientsList{$patientId} = 1;
}
my $totalPatientsIds = keys %patientsList;
say "total patients : [$totalPatientsIds]";

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
	my ($patientId) = @_;
	my $totalPlacebosToSlide = 0;
	my $hasVaccine  = 0;
	for my $doseNum (sort{$a <=> $b} keys %{$randomizationData{$patientId}->{'doses'}}) {
		my $dose     = $randomizationData{$patientId}->{'doses'}->{$doseNum}->{'dose'}     // die;
		my $doseDate = $randomizationData{$patientId}->{'doses'}->{$doseNum}->{'doseDate'} // die;
		my $dosage   = $randomizationData{$patientId}->{'doses'}->{$doseNum}->{'dosage'};
		if ($dosage && $dose eq 'Placebo') {
			$totalPlacebosToSlide++;
		} else {
			$hasVaccine = 1 if $dose ne 'Placebo';
		}
	}
	for my $doseNum (sort{$a <=> $b} keys %{$randomizationData{$patientId}->{'doses'}}) {
		my $dose     = $randomizationData{$patientId}->{'doses'}->{$doseNum}->{'dose'}     // die;
		my $doseDate = $randomizationData{$patientId}->{'doses'}->{$doseNum}->{'doseDate'} // die;
		my $dosage   = $randomizationData{$patientId}->{'doses'}->{$doseNum}->{'dosage'};
		my $doseTo = $doseNum + $totalPlacebosToSlide;
		if ($dosage && $dose eq 'Placebo' && $hasVaccine == 1 && exists $randomizationData{$patientId}->{'doses'}->{$doseTo}) {
			$randomizationData{$patientId}->{'doses'}->{$doseNum}->{'dosage'} = undef;
			$randomizationData{$patientId}->{'doses'}->{$doseTo}->{'dosage'}  = $dosage;
		} else {
			if ($dosage && $dose eq 'Placebo') {
				$randomizationData{$patientId}->{'doses'}->{$doseNum}->{'dosage'} = undef;
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