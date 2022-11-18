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

my $randomizationFile = "public/doc/pfizer_trials/pfizer_trial_randomization.json";
my $trialSubjectsFile = "public/doc/pfizer_trials/pfizer_trial_demographics.json";
my $file1             = 'public/doc/pfizer_trials/pfizer_trial_efficacy_cases.json';
my %randomizationData = ();
my %trialSubjectsData = ();
my %file1Data         = ();

randomization_data();
demographic_data();
load_file_1();
my %stats             = ();
my %patientsList      = ();
open my $out2, '>:utf8', 'public/doc/pfizer_trials/170_positive_efficacy.csv';
say $out2 "file;page number;entry number;subject id;symptoms start date;central lab test;" .
		"age (years);sex;screening date;randomization date;randomization group;is phase1;has HIV;dose 1 date;dose 1;dose 2 date;dose 2;";
for my $subjectId (sort keys %file1Data) {
	my $entryNum         = $file1Data{$subjectId}->{'entryNum'}         // die;
	my $pageNum          = $file1Data{$subjectId}->{'pageNum'}          // die;
	my $symptomstartDate = $file1Data{$subjectId}->{'symptomstartDate'} // die;
	my $centralLabTest   = 'Pos';
	my $ageYears   = $trialSubjectsData{$subjectId}->{'ageYears'}   // die;
	my $hasHIV   = $trialSubjectsData{$subjectId}->{'hasHIV'}   // die;
	my $isPhase1   = $trialSubjectsData{$subjectId}->{'isPhase1'}   // die;
	my $screeningDate   = $trialSubjectsData{$subjectId}->{'screeningDate'}   // die;
	my $sex   = $trialSubjectsData{$subjectId}->{'sex'}   // die;
	my $randomizationDate   = $randomizationData{$subjectId}->{'randomizationDate'}   // die;
	my $randomizationGroup   = $randomizationData{$subjectId}->{'randomizationGroup'}   // die;
	$randomizationGroup =~ s/μ/mc/;
	my $dose1Date   = $randomizationData{$subjectId}->{'doses'}->{'1'}->{'doseDate'}   // die;
	my $dose1   = $randomizationData{$subjectId}->{'doses'}->{'1'}->{'dose'}   // die;
	my $dose2Date   = $randomizationData{$subjectId}->{'doses'}->{'2'}->{'doseDate'}   // die;
	my $dose2   = $randomizationData{$subjectId}->{'doses'}->{'2'}->{'dose'}   // die;
	my $ageGroup = age_to_age_group($ageYears);
	$stats{$randomizationGroup}->{'totalCases'}++;
	$stats{$randomizationGroup}->{'bySexes'}->{$sex}++;
	$stats{$randomizationGroup}->{'byAges'}->{$ageGroup}++;
	$patientsList{$subjectId}->{'pageNum'} = $pageNum;
	$patientsList{$subjectId}->{'entryNum'} = $entryNum;
	$patientsList{$subjectId}->{'subjectId'} = $subjectId;
	$patientsList{$subjectId}->{'symptomstartDate'} = $symptomstartDate;
	$patientsList{$subjectId}->{'centralLabTest'} = $centralLabTest;
	$patientsList{$subjectId}->{'ageYears'} = $ageYears;
	$patientsList{$subjectId}->{'sex'} = $sex;
	$patientsList{$subjectId}->{'screeningDate'} = $screeningDate;
	$patientsList{$subjectId}->{'randomizationDate'} = $randomizationDate;
	$patientsList{$subjectId}->{'randomizationGroup'} = $randomizationGroup;
	$patientsList{$subjectId}->{'isPhase1'} = $isPhase1;
	$patientsList{$subjectId}->{'hasHIV'} = $hasHIV;
	$patientsList{$subjectId}->{'dose1Date'} = $dose1Date;
	$patientsList{$subjectId}->{'dose1'} = $dose1;
	$patientsList{$subjectId}->{'dose2Date'} = $dose2Date;
	$patientsList{$subjectId}->{'dose2'} = $dose2;
	say $out2 "pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements.pdf;$pageNum;$entryNum;$subjectId;$symptomstartDate;$centralLabTest;" .
		"$ageYears;$sex;$screeningDate;$randomizationDate;$randomizationGroup;$isPhase1;$hasHIV;$dose1Date;$dose1;$dose2Date;$dose2;";
}
close $out2;
open my $out, '>:utf8', 'public/doc/pfizer_trials/170_positive_efficacy.json';
print $out encode_json\%patientsList;
close $out;
my $totalPatients = keys %patientsList;
p%stats;
say "total patients in the final efficacy data : [$totalPatients]";

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

sub load_file_1 {
	my $json;
	open my $in, '<:utf8', $file1;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%file1Data = %$json;
	say "[$file1] -> patients : " . keys %file1Data;
}

sub age_to_age_group {
	my $age = shift;
	if ($age >= 16 && $age <= 55) {
		return '16 to 55 yr';
	} elsif ($age > 55) {
		return '>55';
	} else {
		die;
	}
}