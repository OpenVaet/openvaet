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

my $caseFile1 = 'public/doc/pfizer_trials/pfizer_trial_efficacy_cases.json';
my $caseFile2 = 'public/doc/pfizer_trials/pfizer_trial_efficacy_cases_2.json';
my $cutoffCompdate = '20201114';

my %case1 = ();
my %case2 = ();
my %pcrRecords = ();
my $pcrRecordsFile = 'public/doc/pfizer_trials/pfizer_mb_patients.json';

load_pcr_tests();
load_case_subjects_1();
load_case_subjects_2();

my %stats = ();
my %cases = ();
for my $subjectId (sort{$a <=> $b} keys %case1) {
	unless (exists $cases{$subjectId}) {
		$cases{$subjectId} = \%{$case1{$subjectId}};
	}
	my $symptomstartDate = $case1{$subjectId}->{'symptomstartDate'} // die;
	my ($hasPositiveCentralPCR,
		%centralPCRsByVisits) = subject_central_pcrs_by_visits($subjectId);
	my $earliestCovid = '99999999';
	for my $visit (sort keys %centralPCRsByVisits) {
		my $visitCompdate = $centralPCRsByVisits{$visit}->{'visitCompdate'} // die;
		my $pcrResult     = $centralPCRsByVisits{$visit}->{'pcrResult'}     // die;
		if ($pcrResult eq 'POS') {
			$earliestCovid = $visitCompdate if $visitCompdate < $earliestCovid;
		}
	}
	if ($earliestCovid eq '99999999') {
		say "no date found for [$subjectId]";
		$stats{$symptomstartDate}++;
		# p$cases{$subjectId};
	} else {
		$stats{$earliestCovid}++;
		# p$cases{$subjectId};
	}
}
say "total subjects : " . keys %cases;
my $totalCases = 0;
open my $out, '>:utf8', 'cases_by_dates.csv';
for my $symptomstartDate (sort{$a <=> $b} keys %stats) {
	my ($y, $m, $d) = $symptomstartDate =~ /(....)(..)(..)/;
	my $totalOnDate = $stats{$symptomstartDate} // die;
	$totalCases += $totalOnDate;
	say $out "$y-$m-$d;$totalOnDate;$totalCases;";
}
close $out;
say "totalCases : $totalCases";
die;

sub load_case_subjects_1 {
	open my $in, '<:utf8', $caseFile1;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%case1 = %$json;
	say "[$caseFile1] -> patients : " . keys %case1;
}

sub load_case_subjects_2 {
	open my $in, '<:utf8', $caseFile2;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%case2 = %$json;
	say "[$caseFile2] -> patients : " . keys %case2;
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

sub subject_central_pcrs_by_visits {
	my ($subjectId) = @_;
	my %centralPCRsByVisits    = ();
	my $hasPositiveCentralPCR = 0;
	for my $visitDate (sort keys %{$pcrRecords{$subjectId}->{'mbVisits'}}) {

		# Skips the visits unless it contains PCRs.
		next unless exists $pcrRecords{$subjectId}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'};
		my $visitCompdate = $visitDate;
		$visitCompdate =~ s/\D//g;

		# Skips the visit unless it fits with the phase 3.
		next unless $visitCompdate >= 20200720;
		next unless $visitCompdate <= $cutoffCompdate;
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